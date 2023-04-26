// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use self::models::*;
use crate::client::{ClientMsg, client_msg_from_trip_overview};
use diesel::pg::PgConnection;
use diesel::prelude::*;
use docopt::Docopt;
use serde::Deserialize;
use std::error::Error;
use bus::{BusReadHandle, Bus};
use log::{info, warn, error};
use std::sync::Arc;

use axum::{
    extract::ws::{WebSocketUpgrade, WebSocket},
    extract::State,
    routing::get,
    response::{IntoResponse, Response},
    Router,
};

use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

mod transport_rest_vbb_v6;
use transport_rest_vbb_v6::TripOverview;

pub mod client;
pub mod crawler;
pub mod models;
pub mod schema;

const USAGE: &'static str = "
Usage: isre1late-server --port <port>
       isre1late-server validate-hafas-schema
       isre1late-server run-db-migrations
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --port <port>        TCP port on which the server listens. [default: 8080]
";

#[derive(Deserialize)]
struct CliArgs {
    flag_port: u16,
    cmd_validate_hafas_schema: bool,
    cmd_run_db_migrations: bool,
}

/// Validate our representation of HAFAS types and also delete and refill delays and trips table.
fn validate_hafas_schema(db: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    use self::schema::fetched_json::dsl::fetched_json;
    use crate::schema::delays::dsl::delays;
    use crate::schema::trips::dsl::trips;

    info!("Validating HAFAS schema..");
    diesel::delete(delays).execute(db)?;
    diesel::delete(trips).execute(db)?;

    let bodies_iter =
        fetched_json.load_iter::<SelectFetchedJson, diesel::pg::PgRowByRowLoadingMode>(db)?;

    let mut error_count: i64 = 0;

    for fj_res in bodies_iter {
        let SelectFetchedJson { id, body, .. } = match fj_res {
            Ok(fj) => fj,
            Err(e) => {
                error!("{}", e);
                continue;
            }
        };
        match serde_json::from_str::<TripOverview>(&body.as_ref()) {
            Ok(_) => {}
            Err(err) => {
                // error!("Couldn't deserialize: {}", body.unwrap());
                error!("{}: {}", id, err);
                error_count += 1;
            }
        }
    }
    error!("Encountered {} errors.", error_count);
    Ok(())
}

fn run_db_migrations(db: &mut PgConnection) -> () {
    info!("Runnung migrations...");
    let migrations_run = db
        .run_pending_migrations(MIGRATIONS)
        .expect("Failed to run migrations.");
    info!(
        "Ran {} pending migrations: {:?}",
        migrations_run.len(),
        migrations_run
    );
}

// #[get("/delays")]
// fn delays(ws: ws::WebSocket, bus_read_handle: &rocket::State<bus::BusReadHandle<ClientMsg>>) -> ws::Channel<'static> {
//     info!("Receiving websocket request");
//     let mut rx = bus_read_handle.clone().add_rx();
//     ws.channel(move |mut stream| {
//         Box::pin(async move {
//             while let Ok(msg) = rx.recv() {
//                 // We don't expect JSON serialisation to fail.
//                 let json_msg = serde_json::to_string(&msg).unwrap();
//                 let _ = stream.send(ws::Message::Text(json_msg)).await;
//             }
// 
//             Ok(())
//         })
//     })
// }

async fn delays_handler(ws: WebSocketUpgrade, State(state): State<Arc<BusReadHandle<ClientMsg>>>) -> Response {
     info!("Receiving websocket upgrade request");
    ws.on_upgrade(|socket| handle_delays_socket(socket, state))
}

async fn handle_delays_socket(mut socket: WebSocket, bus_read_handle: Arc<BusReadHandle<ClientMsg>>) {
     info!("Receiving websocket request");
     let mut rx = Arc::clone(&bus_read_handle).clone().add_rx();

     while let Ok(msg) = rx.recv() {
         // We don't expect JSON serialisation to fail.
         let json_msg = serde_json::to_string(&msg).unwrap();
         let _ = socket.send(axum::extract::ws::Message::Text(json_msg)).await;
     }
}

#[tokio::main]
async fn main() {
    // Setup logging
    if systemd_journal_logger::connected_to_journal() {
        // If journald is available.
        systemd_journal_logger::init().unwrap();
        log::set_max_level(log::LevelFilter::Info);
    } else {
        // Otherwise fall back to logging to standard error.
        simple_logger::SimpleLogger::new().env().init().unwrap();
    }

    let args: CliArgs = Docopt::new(USAGE)
        .and_then(|d| d.deserialize())
        .unwrap_or_else(|e| e.exit());

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let mut db: PgConnection = PgConnection::establish(&db_url)
        .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));

    if args.cmd_validate_hafas_schema {
        validate_hafas_schema(&mut db).unwrap_or_else(|e| {
            error!("{}", e);
            std::process::exit(1);
        });
        std::process::exit(0);
    } else if args.cmd_run_db_migrations {
        run_db_migrations(&mut db);
        std::process::exit(0);
    }

    run_db_migrations(&mut db);

    let bus: Bus<client::ClientMsg> = bus::Bus::new(10*1024);
    let bus_read_handle = bus.read_handle();

    std::thread::spawn(move || {
        crawler::crawler(&mut db, bus).unwrap_or_else(|e| {
            error!("{}", e);
            std::process::exit(1);
        });
    });

    let app = axum::Router::new().route("/delays", get(delays_handler))
        .with_state(Arc::new(bus_read_handle));

    // run it with hyper on localhost:3000
    axum::Server::bind(&"0.0.0.0:3000".parse().unwrap())
        .serve(app.into_make_service())
        .await
        .unwrap();

}
