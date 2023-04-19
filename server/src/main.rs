// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate log;
#[macro_use]
extern crate rocket;

use self::models::*;
use diesel::pg::PgConnection;
use diesel::prelude::*;
use docopt::Docopt;
use rocket::futures::{SinkExt, StreamExt};
use serde::Deserialize;
use std::error::Error;
use std::thread::sleep;
use std::time::{Duration, Instant};
use time::OffsetDateTime;

use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

mod transport_rest_vbb_v6;
use transport_rest_vbb_v6::{TripOverview, TripsOverview};

pub mod models;
pub mod schema;

const USAGE: &'static str = "
Usage: isre1late-server --port <port>
       isre1late-server validate-hafas-schema
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --port <port>        TCP port on which the server listens. [default: 8080]
";

#[derive(Deserialize)]
struct CliArgs {
    flag_port: u16,
    cmd_validate_hafas_schema: bool,
}

const TRIPS_BASEPATH: &'static str = "https://v6.vbb.transport.rest/trips";

fn fetch_json_and_store_in_db(db: &mut PgConnection, url: String) -> String {
    use crate::schema::fetched_json;

    let response_text = reqwest::blocking::get(url.clone()).unwrap().text().unwrap();
    let fetched_json = FetchedJson {
        fetched_at: OffsetDateTime::now_utc(),
        url: url,
        body: response_text.clone(),
    };
    diesel::insert_into(fetched_json::table)
        .values(&fetched_json)
        .execute(db)
        .expect("Error saving fetched json.");

    response_text
}

fn validate_hafas_schema(db: &mut PgConnection) -> () {
    info!("Validating Hafas schema");
    let bodies = self::schema::fetched_json::dsl::fetched_json
        .load::<SelectFetchedJson>(db)
        .expect("Error loading fetched JSON.");

    let mut error_count: i64 = 0;

    for SelectFetchedJson { id, body, .. } in bodies {
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
}

#[get("/echo")]
fn echo(ws: ws::WebSocket) -> ws::Channel<'static> {
    ws.channel(move |mut stream| {
        Box::pin(async move {
            while let Some(message) = stream.next().await {
                let _ = stream.send(message?).await;
            }

            Ok(())
        })
    })
}

fn crawler(db: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    // It looks like, HAFAS is only cabable of showing new state every 30seconds anyway.
    let loop_interval = Duration::from_secs(30);
    let mut next_execution = Instant::now() + loop_interval;

    loop {
        info!("Fetching currently running trips.");
        let trips_overview_url = format!("{}?lineName=RE1&operatorNames=ODEG", TRIPS_BASEPATH);
        let trips_overview: TripsOverview =
            serde_json::from_str(&fetch_json_and_store_in_db(db, trips_overview_url))?;

        info!(
            "Fetched {:?} currently running trips.",
            &trips_overview.trips.len()
        );

        for trip in trips_overview.trips {
            use crate::schema::{delays, trips};
            use diesel::upsert::excluded;

            let new_trip = Trip {
                first_observed: OffsetDateTime::now_utc(),
                text_id: trip.id.clone(),
                origin: trip.origin.name,
                destination: trip.destination.name,
                planned_departure_from_origin: trip.plannedDeparture,
            };
            let SelectTrip {
                id: current_trip_id,
                ..
            } = diesel::insert_into(trips::table)
                .values(new_trip)
                .on_conflict(trips::text_id)
                .do_update()
                .set((
                    trips::text_id.eq(trips::text_id),
                    trips::first_observed.eq(trips::first_observed),
                ))
                .get_result(db)
                .expect("Error inserting into trips.");

            // With this endpoint, we can access the delay data per trip.
            let trip_url = format!("{}/{}", TRIPS_BASEPATH, urlencoding::encode(&trip.id));
            info!("Fetching trip data from {}", trip_url);
            let trip_overview: TripOverview =
                serde_json::from_str(&fetch_json_and_store_in_db(db, trip_url))?;
            let (latitude, longitude) = trip_overview
                .trip
                .currentLocation
                .map_or((None, None), |tl| (Some(tl.latitude), Some(tl.longitude)));
            let new_delay = Delay {
                trip_id: current_trip_id,
                observed_at: OffsetDateTime::now_utc(),
                generated_at: trip_overview.realtimeDataUpdatedAt,
                latitude: latitude,
                longitude: longitude,
                delay: trip_overview.trip.arrivalDelay,
            };
            diesel::insert_into(delays::table)
                .values(new_delay)
                .execute(db)
                .expect("Error inserting into delays.");
        }
        sleep(next_execution - Instant::now());
        next_execution += loop_interval;
    }
}

#[launch]
fn rocket() -> _ {
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

    info!("Runnung migrations...");
    let migrations_run = db
        .run_pending_migrations(MIGRATIONS)
        .expect("Failed to run migrations");
    info!(
        "Ran {} pending migrations: {:?}",
        migrations_run.len(),
        migrations_run
    );

    if args.cmd_validate_hafas_schema {
        validate_hafas_schema(&mut db);
        std::process::exit(0);
    }

    std::thread::spawn(move || {
        crawler(&mut db);
        std::process::exit(1);
    });

    // let rocket_config = rocket::config::Config::figment()
    //     .merge(("port", args.flag_port))
    //     .merge(("address", "::1"));

    rocket::build().mount("/", routes![echo])
}
