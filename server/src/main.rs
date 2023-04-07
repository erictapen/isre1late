// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use docopt::Docopt;
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::error::Error;
use std::path::PathBuf;

mod transport_rest_vbb_v6;
use transport_rest_vbb_v6::Trips;

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

fn main() -> Result<(), Box<dyn Error>> {
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
          ( trip_id BIGSERIAL NOT NULL PRIMARY KEY
          , observed_at TIMESTAMP NOT NULL
          , generated_at TIMESTAMP NOT NULL
          , latitude REAL NOT NULL
          , longitude REAL NOT NULL
          , delay INTEGER
          )",
        params![],
    )?;

    loop {
        let response = reqwest::blocking::get(format!("{}?lineName=RE1", trips_basepath))?;

        let fetched_trips = response.json::<Trips>()?;
        println!("{:#?}", &fetched_trips);

        for trip in fetched_trips.trips {
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
        }
    }

    Ok(())
}
