// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate log;

use docopt::Docopt;
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::error::Error;
use std::path::PathBuf;
use std::thread::sleep;
use std::time::{Duration, Instant};

mod transport_rest_vbb_v6;
use transport_rest_vbb_v6::{TripOverview, TripsOverview};

const USAGE: &'static str = "
Usage: isre1late-server --db <db> --port <port>
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --db <db>            Path to sqlite database. [default: ./db.sqlite]
    --port <port>        TCP port on which the server listens. [default: 8080]
";

#[derive(Deserialize)]
struct CliArgs {
    flag_db: PathBuf,
    flag_port: u16,
}

const trips_basepath: &'static str = "https://v6.vbb.transport.rest/trips";

fn fetch_json_and_store_in_db(db: &Connection, url: String) -> String {
    let response_text = reqwest::blocking::get(url.clone()).unwrap().text().unwrap();
    db.execute(
        "INSERT INTO fetched_json(fetched_at, url, body) VALUES(CURRENT_TIMESTAMP, $1, $2);",
        params![url, response_text],
    )
    .unwrap();
    response_text
}

fn main() -> Result<(), Box<dyn Error>> {
    // Setup logging
    if systemd_journal_logger::connected_to_journal() {
        // If journald is available.
        systemd_journal_logger::init().unwrap();
        log::set_max_level(log::LevelFilter::Info);
    } else {
        // Otherwise fall back to logging to standard error.
        simple_logger::SimpleLogger::new().init().unwrap();
    }

    let args: CliArgs = Docopt::new(USAGE)
        .and_then(|d| d.deserialize())
        .unwrap_or_else(|e| e.exit());

    let db = Connection::open(args.flag_db)?;

    db.execute(
        "CREATE TABLE IF NOT EXISTS trips
          ( id INTEGER PRIMARY KEY AUTOINCREMENT
          , first_observed TIMESTAMP NOT NULL
          , text_id TEXT UNIQUE NOT NULL
          , origin TEXT NOT NULL
          , destination TEXT NOT NULL
          , planned_departure_from_origin TIMESTAMP NOT NULL
          )",
        params![],
    )?;
    db.execute(
        "CREATE TABLE IF NOT EXISTS delays
          ( trip_id INTEGER NOT NULL
          , observed_at TIMESTAMP NOT NULL
          , generated_at TIMESTAMP NOT NULL
          , latitude REAL
          , longitude REAL
          , delay INTEGER
          )",
        params![],
    )?;
    db.execute(
        "CREATE TABLE IF NOT EXISTS fetched_json
          ( id INTEGER NOT NULL PRIMARY KEY
          , fetched_at TIMESTAMP NOT NULL
          , url TEXT NOT NULL
          , body TEXT NOT NULL
          )",
        params![],
    )?;

    // It looks like, HAFAS is only cabable of showing new state every 30seconds anyway.
    let loop_interval = Duration::from_secs(30);
    let mut next_execution = Instant::now() + loop_interval;

    loop {
        info!("Fetching currently running trips.");
        let trips_overview_url = format!("{}?lineName=RE1&operatorNames=ODEG", trips_basepath);
        let trips_overview: TripsOverview =
            serde_json::from_str(&fetch_json_and_store_in_db(&db, trips_overview_url))?;

        info!(
            "Fetched {:?} currently running trips.",
            &trips_overview.trips.len()
        );

        for trip in trips_overview.trips {
            db.execute(
                "INSERT OR IGNORE
                 INTO trips(first_observed, text_id, origin, destination, planned_departure_from_origin)
                 VALUES(CURRENT_TIMESTAMP, $1, $2, $3, $4);",
                params![
                    trip.id,
                    trip.origin.name,
                    trip.destination.name,
                    trip.plannedDeparture
                ],
            )?;
            let current_trip_id = db.last_insert_rowid();
            // With this endpoint, we can access the delay data per trip.
            let trip_url = format!("{}/{}", trips_basepath, urlencoding::encode(&trip.id));
            info!("Fetching trip data from {}", trip_url);
            let trip_overview: TripOverview =
                serde_json::from_str(&fetch_json_and_store_in_db(&db, trip_url))?;
            let (latitude, longitude) = trip_overview
                .trip
                .currentLocation
                .map_or((None, None), |tl| (Some(tl.latitude), Some(tl.longitude)));
            db.execute(
                "INSERT
                 INTO delays(trip_id, observed_at, generated_at, latitude, longitude, delay)
                 VALUES($1, CURRENT_TIMESTAMP, $2, $3, $4, $5);",
                params![
                    current_trip_id,
                    trip_overview.realtimeDataUpdatedAt,
                    latitude,
                    longitude,
                    trip_overview.trip.arrivalDelay
                ],
            )?;
        }
        sleep(next_execution - Instant::now());
        next_execution += loop_interval;
    }

    Ok(())
}
