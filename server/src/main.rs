// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate serde_with;

use self::models::*;
use crate::models::DelayRecord;
use diesel::pg::PgConnection;
use diesel::prelude::*;
use docopt::Docopt;
use log::{error, info};
use serde::Deserialize;

use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

mod transport_rest_vbb_v6;

mod cache;
mod cli_utils;
mod crawler;
mod models;
mod schema;
mod web_api;
mod ws_api;

/// I gave up on giving validate-hafas-schema an extra argument where one could just validate one
/// id. Docopt won here.
const USAGE: &'static str = "
Usage: isre1late-server --port <port> --ws-port <wsport>
       isre1late-server validate-hafas-schema
       isre1late-server run-db-migrations
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --port <port>        TCP port on which the webserver listens. [default: 8080]
    --ws-port <wsport>   TCP port on which the websocket server listens. [default: 8081]
    -l, --listen IP      IP address to listen on, e.g. ::. [default: ::1]

";

#[derive(Deserialize)]
struct CliArgs {
    flag_port: u16,
    flag_ws_port: u16,
    flag_listen: std::net::IpAddr,
    cmd_validate_hafas_schema: bool,
    cmd_run_db_migrations: bool,
}

fn run_db_migrations(db: &mut PgConnection) -> () {
    info!("Running migrations...");
    let migrations_run = db
        .run_pending_migrations(MIGRATIONS)
        .expect("Failed to run migrations.");
    info!(
        "Ran {} pending migrations: {:?}",
        migrations_run.len(),
        migrations_run
    );
}

fn main() {
    // Setup logging
    if systemd_journal_logger::connected_to_journal() {
        // If journald is available.
        systemd_journal_logger::JournalLog::new()
            .unwrap()
            .with_syslog_identifier("isre1late".to_string())
            .install()
            .unwrap();
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

        run_db_migrations(&mut db);

        if args.cmd_validate_hafas_schema {
            crate::cli_utils::validate_hafas_schema(&mut db).unwrap_or_else(|e| {
                error!("{}", e);
                std::process::exit(1);
            });
            std::process::exit(0);
        } else if args.cmd_run_db_migrations {
            // We already ran the migrations above.
            std::process::exit(0);
        }
    }

    let cache_state: cache::CacheState = {
        let mut db1: PgConnection = PgConnection::establish(&db_url)
            .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
        let db2: PgConnection = PgConnection::establish(&db_url)
            .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
        crate::cache::update_caches(&mut db1, db2)
            .unwrap_or_else(|e| panic!("Unable to update cache tables in DB: {}", e))
    };

    // The spmc bus with which the crawler can communicate with all open websocket threads.
    let bus = bus::Bus::new(10 * 1024);
    // With this handle we can produce a new channel receiver per new websocket connection.
    let bus_read_handle = bus.read_handle();

    // Start crawler
    {
        let db_url = db_url.clone();
        std::thread::spawn(move || {
            let mut db: PgConnection = PgConnection::establish(&db_url)
                .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
            crawler::crawler(&mut db, bus, cache_state).unwrap_or_else(|e| {
                error!("{}", e);
                std::process::exit(1);
            });
        });
    }

    // Start websocket server
    {
        let mut db: PgConnection = PgConnection::establish(&(db_url.clone()))
            .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));
        std::thread::spawn(move || {
            crate::ws_api::websocket_server(
                &mut db,
                bus_read_handle,
                args.flag_listen,
                args.flag_ws_port,
            )
            .unwrap();
        });
    }

    // Start webserver
    {
        crate::web_api::webserver(&db_url, args.flag_listen, args.flag_port).unwrap();
    }
}
