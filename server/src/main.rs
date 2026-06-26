// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate serde_with;

use self::models::*;
use crate::models::DelayRecord;
use clap::{Parser, Subcommand};
use diesel::pg::PgConnection;
use diesel::prelude::*;
use log::{error, info};

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

#[derive(Parser, Debug)]
struct CliArgs {
    #[arg(long)]
    port: u16,
    #[arg(long)]
    ws_port: u16,
    #[arg(short, long)]
    listen: std::net::IpAddr,
    #[command(subcommand)]
    command: Option<CliCommand>,
}

#[derive(Clone, Debug, Subcommand)]
enum CliCommand {
    ValidateHafasSchema,
    RunDbMigrations,
    TrainZstdDict,
}

fn run_db_migrations(db: &mut PgConnection) {
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

fn train_zstd_dict(db: &mut PgConnection) {
    let fetched_json: Vec<FetchedJson> =
        diesel::sql_query("SELECT * FROM fetched_json TABLESAMPLE BERNOULLI(0.01) LIMIT 1000")
            .get_results(db)
            .unwrap();

    let samples: Vec<String> = fetched_json.into_iter().map(|f| f.body).collect();

    let sample_len = samples.len();

    println!("{} Samples available", sample_len);

    let dict_data = zstd::dict::from_samples(&samples, 50 * 1024 * 1024).unwrap();
    let dict = zstd::dict::CDict::create(&dict_data, 22);

    let mut compressor = zstd::bulk::Compressor::with_dictionary(22, &dict_data).unwrap();

    let compression_ratios = samples
        .into_iter()
        .map(|s| (s.len(), compressor.compress(&s.into_bytes()).unwrap().len()))
        .map(|(uncompressed, compressed)| uncompressed as f64 / compressed as f64);

    let compression_ratio = compression_ratios.sum::<f64>() / sample_len as f64;
    println!(
        "On {} samples achieved an average compression ratio of {}",
        sample_len, compression_ratio
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

    let args = CliArgs::parse();

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");

    {
        let mut db: PgConnection = PgConnection::establish(&db_url)
            .unwrap_or_else(|_| panic!("Error connecting to {}", db_url));

        run_db_migrations(&mut db);

        if let Some(CliCommand::ValidateHafasSchema) = args.command {
            crate::cli_utils::validate_hafas_schema(&mut db).unwrap_or_else(|e| {
                error!("{}", e);
                std::process::exit(1);
            });
            std::process::exit(0);
        } else if let Some(CliCommand::RunDbMigrations) = args.command {
            // We already ran the migrations above.
            std::process::exit(0);
        } else if let Some(CliCommand::TrainZstdDict) = args.command {
            train_zstd_dict(&mut db);
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
            crate::ws_api::websocket_server(&mut db, bus_read_handle, args.listen, args.ws_port)
                .unwrap();
        });
    }

    // Start webserver
    {
        crate::web_api::webserver(&db_url, args.listen, args.port).unwrap();
    }

    // TODO use sd-notify to signal the service manager that all processes are up and running.
}
