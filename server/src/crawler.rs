// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::client::ClientMsg;
use crate::models::*;
use crate::transport_rest_vbb_v6::{TripOverview, TripsOverview};
use bus::Bus;
use diesel::pg::PgConnection;
use diesel::prelude::*;
use log::{debug, error, info};
use std::error::Error;
use std::thread::sleep;
use std::time::{Duration, Instant};
use time::OffsetDateTime;

use crate::client::client_msg_from_trip_overview;

const TRIPS_BASEPATH: &'static str = "https://v6.vbb.transport.rest/trips";

fn fetch_json_and_store_in_db(
    db: &mut PgConnection,
    url: String,
) -> Result<String, Box<dyn Error>> {
    use crate::schema::fetched_json;

    let response_text = reqwest::blocking::get(url.clone())?.text()?;
    let fetched_json = FetchedJson {
        fetched_at: OffsetDateTime::now_utc(),
        url: url,
        body: response_text.clone(),
    };
    diesel::insert_into(fetched_json::table)
        .values(&fetched_json)
        .execute(db)?;

    Ok(response_text)
}

pub fn crawler(db: &mut PgConnection, mut bus: Bus<ClientMsg>) -> Result<(), Box<dyn Error>> {
    // It looks like, HAFAS is only cabable of showing new state every 30seconds anyway.
    let loop_interval = Duration::from_secs(30);

    loop {
        let next_execution = Instant::now() + loop_interval;

        info!("Fetching currently running trips.");
        let trips_overview_url = format!("{}?lineName=RE1&operatorNames=ODEG", TRIPS_BASEPATH);
        let trips_overview_json = match fetch_json_and_store_in_db(db, trips_overview_url) {
            Ok(fj) => fj,
            Err(e) => {
                error!("{}", e);
                continue;
            }
        };
        let trips_overview: TripsOverview = match serde_json::from_str(&trips_overview_json) {
            Ok(res) => res,
            Err(e) => {
                error!("Failed to deserialize trips overview: {}", e);
                continue;
            }
        };

        info!(
            "Fetched {:?} currently running trips.",
            &trips_overview.trips.len()
        );

        for trip in trips_overview.trips {
            // With this endpoint, we can access the delay data per trip.
            let trip_url = format!("{}/{}", TRIPS_BASEPATH, urlencoding::encode(&trip.id));
            info!("Fetching trip data from {}", trip_url);
            let trip_overview_json = match fetch_json_and_store_in_db(db, trip_url) {
                Ok(fj) => fj,
                Err(e) => {
                    error!("{}", e);
                    continue;
                }
            };
            let trip_overview: TripOverview = match serde_json::from_str(&trip_overview_json) {
                Ok(res) => res,
                Err(e) => {
                    error!("Failed to deserialize trip overview: {}", e);
                    continue;
                }
            };

            let client_msg_res = client_msg_from_trip_overview(trip_overview);
            debug!("{:?}", client_msg_res);
            match client_msg_res {
                Ok(client_msg) => {
                    bus.broadcast(client_msg);
                }
                Err(e) => {
                    error!("{}", e);
                }
            }
        }
        sleep(next_execution - Instant::now());
    }
}
