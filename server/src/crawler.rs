// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::cache::{delay_events_from_delay_record, CacheState};
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

const TRIPS_PATH: &'static str = "/trips";

fn fetch_json_and_store_in_db(
    db: &mut PgConnection,
    url: String,
    fetched_at: OffsetDateTime,
) -> Result<(i64, String), Box<dyn Error>> {
    use crate::schema::fetched_json;

    let response_text = reqwest::blocking::get(url.clone())?.text()?;
    let fetched_json = FetchedJson {
        fetched_at: fetched_at,
        url: url,
        body: response_text.clone(),
    };
    match &diesel::insert_into(fetched_json::table)
        .values(&fetched_json)
        .get_results::<SelectFetchedJson>(db)?[..]
    {
        [sfj] => Ok((sfj.id, response_text)),
        _ => Err("Invalid amount of rows returned".into()),
    }
}

pub fn crawler(
    db: &mut PgConnection,
    mut bus: Bus<DelayRecord>,
    mut cache_state: CacheState,
) -> Result<(), Box<dyn Error>> {
    // It looks like, HAFAS is only cabable of showing new state every 30seconds anyway.
    let loop_interval = Duration::from_secs(30);

    let hafas_base_url = std::env::var("HAFAS_BASE_URL").expect("HAFAS_BASE_URL must be set");

    loop {
        let next_execution = Instant::now() + loop_interval;

        let trips_overview: TripsOverview = {
            info!("Fetching currently running trips.");
            let url = format!("{hafas_base_url}{TRIPS_PATH}?lineName=RE1&operatorNames=ODEG");
            let fetched_at = OffsetDateTime::now_utc();
            let (_, json) = match fetch_json_and_store_in_db(db, url, fetched_at) {
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
            let (row_id, json) = match fetch_json_and_store_in_db(db, url, fetched_at) {
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

            let delay_record = delay_record_from_trip_overview(trip_overview, row_id, fetched_at);
            debug!("{:?}", delay_record);
            if let Some(delay_record) = delay_record {
                bus.broadcast(delay_record.clone());

                use crate::schema::delay_records;
                diesel::insert_into(delay_records::table)
                    .values(&delay_record)
                    .execute(db)?;

                let delay_events: Vec<DelayEvent> =
                    delay_events_from_delay_record(&mut cache_state.trip_id_map, &delay_record);

                use crate::schema::delay_events;
                diesel::insert_into(delay_events::table)
                    .values(&delay_events)
                    .execute(db)
                    .unwrap();
            }
        }
        sleep(next_execution - Instant::now());
    }
}
