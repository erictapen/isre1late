// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate serde_with;

use self::models::*;
use crate::client::ClientMsg;
use bus::{Bus, BusReadHandle};
use diesel::pg::PgConnection;
use diesel::prelude::*;
use docopt::Docopt;
use log::{debug, error, info, warn};
use serde::Deserialize;
use std::error::Error;

use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

mod transport_rest_vbb_v6;

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
    -l, --listen IP      IP address to listen on, e.g. ::. [default: ::1]

";

#[derive(Deserialize)]
struct CliArgs {
    flag_port: u16,
    flag_listen: std::net::IpAddr,
    cmd_validate_hafas_schema: bool,
    cmd_run_db_migrations: bool,
}

/// Validate our representation of HAFAS types.
fn validate_hafas_schema(db: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    use self::schema::fetched_json::dsl::fetched_json;
    use std::{error::Error, fmt};
    use transport_rest_vbb_v6::HafasMsg;

    #[derive(Debug)]
    struct SomeErrorsEncountered;

    impl Error for SomeErrorsEncountered {}

    impl fmt::Display for SomeErrorsEncountered {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "Some errors encountered")
        }
    }

    info!("Validating HAFAS schema...");
    let start = time::OffsetDateTime::now_utc();

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
        match serde_json::from_str::<HafasMsg>(&body.as_ref()) {
            Ok(_) => {}
            Err(err) => {
                // error!("Couldn't deserialize: {}", body.unwrap());
                error!("{}: {}", id, err);
                error_count += 1;
            }
        }
    }

    let duration = time::OffsetDateTime::now_utc() - start;

    if error_count > 0 {
        error!("Encountered {} errors in {duration:.3}", error_count);
        Err(Box::new(SomeErrorsEncountered))
    } else {
        info!("Encountered no errors in {duration:.3}");
        Ok(())
    }
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

/// Open the webserver and publish fetched data via Websockets.
fn websocket_server(
    db: &mut PgConnection,
    bus_read_handle: BusReadHandle<ClientMsg>,
    listen: std::net::IpAddr,
    port: u16,
) -> Result<(), Box<dyn Error>> {
    use std::net::{IpAddr, SocketAddr, SocketAddrV4, SocketAddrV6};

    let socket_addr: std::net::SocketAddr = match listen {
        IpAddr::V4(addr) => SocketAddr::V4(SocketAddrV4::new(addr, port)),
        IpAddr::V6(addr) => SocketAddr::V6(SocketAddrV6::new(addr, port, 0, 0)),
    };

    let server = std::net::TcpListener::bind(socket_addr).unwrap_or_else(|_| {
        error!("Can't bind to {}", socket_addr);
        std::process::exit(1);
    });
    info!("Server started.");
    for stream in server.incoming() {
        use tungstenite::handshake::server::{Request, Response};

        let mut historic_seconds = 3600;

        let ws_callback = |request: &Request, response: Response| {
            #[derive(Deserialize, Debug)]
            struct Query {
                historic: u64,
            }

            if let Some(query_str) = request.uri().query() {
                debug!("query_str: {}", query_str);
                match serde_qs::from_str(&query_str) {
                    Err(e) => {
                        error!("{}", e);
                    }
                    Ok(Query { historic }) => {
                        // We don't allow more than 6 hours for now
                        // Otherwise the current server goes OOM.
                        historic_seconds = std::cmp::min(historic, 3600 * 6);
                    }
                }
            }

            match request.uri().path() {
                "/api/delays" => {
                    debug!("The request's route is: /api/delays");
                    Ok(response)
                }
                other_path => {
                    warn!("Path {} is not available.", other_path);
                    let not_found = Response::builder()
                        .status(tungstenite::http::StatusCode::NOT_FOUND)
                        .body(Some("Path not found.".into()))
                        .expect("This should never fail.");
                    Err(not_found)
                }
            }
        };
        match stream {
            Ok(stream) => {
                let mut websocket = match tungstenite::accept_hdr(stream, ws_callback) {
                    Ok(ws) => ws,
                    Err(e) => {
                        warn!("{}", e);
                        continue;
                    }
                };

                use self::schema::fetched_json::dsl::fetched_json;
                use crate::schema::fetched_json::fetched_at;

                let mut rx = bus_read_handle.add_rx();

                use std::net::TcpStream;
                use tungstenite::protocol::WebSocket;
                use tungstenite::Message::Text;

                fn send_message(
                    websocket: &mut WebSocket<TcpStream>,
                    msg: ClientMsg,
                ) -> Result<(), ()> {
                    match websocket.write_message(Text(
                        serde_json::to_string(&msg).expect("This shouldn't fail."),
                    )) {
                        Err(e) => {
                            warn!(
                                "{:?}: Couldn't send message to subscriber: {}",
                                std::thread::current().id(),
                                e
                            );
                            Err(())
                        }
                        Ok(_) => {
                            debug!(
                                "{:?}: Sent message to subscriber successfully.",
                                std::thread::current().id()
                            );
                            Ok(())
                        }
                    }
                }

                {
                    let old_delays = fetched_json
                        .filter(fetched_at.gt(time::OffsetDateTime::now_utc()
                            - std::time::Duration::from_secs(historic_seconds)))
                        .then_order_by(fetched_at.asc())
                        .load::<SelectFetchedJson>(db)
                        .unwrap_or_else(|e| {
                            panic!("Unable to load data from fetched_json: {}", e);
                        });

                    for fj in old_delays {
                        if let Ok(trip_overview) = serde_json::from_str(&fj.body) {
                            let _ = send_message(
                                &mut websocket,
                                client::client_msg_from_trip_overview(trip_overview, fj.fetched_at),
                            );
                        }
                    }
                }

                debug!("Sent old messages to client, switching to live update now.");

                std::thread::spawn(move || {
                    while let Ok(msg) = rx.recv() {
                        if send_message(&mut websocket, msg).is_err() {
                            break;
                        };
                    }

                    info!("Closing websocket");
                    websocket
                        .close(None)
                        .unwrap_or_else(|_| warn!("Can't close websocket in a normal way."));
                    websocket
                        .write_pending()
                        .unwrap_or_else(|_| warn!("Couldn't write pending close frame."));
                });
            }
            Err(_) => {
                warn!("Close connection.");
                continue;
            }
        };
    }
    Ok(())
}

fn main() {
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

    {
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
    }

    // The spmc bus with which the crawler can communicate with all open websocket threads.
    let bus: Bus<client::ClientMsg> = bus::Bus::new(10 * 1024);
    // With this handle we can produce new channel receivers per new websocket connection.
    let bus_read_handle = bus.read_handle();

    {
        let db_url = db_url.clone();
        std::thread::spawn(move || {
            let mut db: PgConnection = PgConnection::establish(&db_url)
                .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
            crawler::crawler(&mut db, bus).unwrap_or_else(|e| {
                error!("{}", e);
                std::process::exit(1);
            });
        });
    }

    {
        let mut db: PgConnection = PgConnection::establish(&(db_url.clone()))
            .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
        websocket_server(&mut db, bus_read_handle, args.flag_listen, args.flag_port).unwrap();
    }
}
