// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::client::ClientMsg;
use crate::models::*;
use crate::transport_rest_vbb_v6::{deserialize, HafasMsg, TripOverview, TripsOverview};
use bus::Bus;
use diesel::pg::PgConnection;
use diesel::prelude::*;
use log::{debug, error, info};
use std::error::Error;
use std::thread::sleep;
use std::time::{Duration, Instant};
use time::OffsetDateTime;

use crate::client::client_msg_from_trip_overview;

const TRIPS_PATH: &'static str = "/trips";

fn fetch_json_and_store_in_db(
    db: &mut PgConnection,
    url: String,
    fetched_at: OffsetDateTime,
) -> Result<String, Box<dyn Error>> {
    use crate::schema::fetched_json;

    let response_text = reqwest::blocking::get(url.clone())?.text()?;
    let fetched_json = FetchedJson {
        fetched_at: fetched_at,
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

    let hafas_base_url = std::env::var("HAFAS_BASE_URL").expect("HAFAS_BASE_URL must be set");

    loop {
        let next_execution = Instant::now() + loop_interval;

        let trips_overview: TripsOverview = {
            info!("Fetching currently running trips.");
            let url = format!("{hafas_base_url}{TRIPS_PATH}?lineName=RE1&operatorNames=ODEG");
            let fetched_at = OffsetDateTime::now_utc();
            let json = match fetch_json_and_store_in_db(db, url, fetched_at) {
                Ok(fj) => fj,
                Err(e) => {
                    error!("{}", e);
                    continue;
                }
            };
            match deserialize(&json) {
                Ok(HafasMsg::TripsOverview(res)) => res,
                Ok(_) => {
                    error!("HafasMsg is not a TripsOverview");
                    continue;
                }
                Err(e) => {
                    error!("Failed to deserialize trips overview: {}", e);
                    continue;
                }
            }
        };

        info!(
            "Fetched {:?} currently running trips.",
            &trips_overview.trips.len()
        );

        for trip in trips_overview.trips {
            // With this endpoint, we can access the delay data per trip.
            let url = format!(
                "{hafas_base_url}{TRIPS_PATH}/{}",
                urlencoding::encode(&trip.id)
            );
            info!("Fetching trip data from {}", url);
            let fetched_at = OffsetDateTime::now_utc();
            let json = match fetch_json_and_store_in_db(db, url, fetched_at) {
                Ok(fj) => fj,
                Err(e) => {
                    error!("{}", e);
                    continue;
                }
            };
            let trip_overview: TripOverview = match deserialize(&json) {
                Ok(HafasMsg::TripOverview(res)) => res,
                Ok(_) => {
                    error!("HafasMsg is not a TripOverview");
                    continue;
                }
                Err(e) => {
                    error!("Failed to deserialize trip overview: {}", e);
                    continue;
                }
            };

            let client_msg = client_msg_from_trip_overview(trip_overview, fetched_at);
            debug!("{:?}", client_msg);
            bus.broadcast(client_msg);
        }
        sleep(next_execution - Instant::now());
    }
}
