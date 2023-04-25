use crate::models::*;
use crate::transport_rest_vbb_v6::{TripOverview, TripsOverview};
use diesel::pg::PgConnection;
use diesel::prelude::*;
use diesel::ExpressionMethods;
use std::error::Error;
use std::thread::sleep;
use std::time::{Duration, Instant};
use time::OffsetDateTime;

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

fn insert_trip(db: &mut PgConnection, new_trip: Trip) -> Result<i64, diesel::result::Error> {
    use crate::schema::trips;

    diesel::insert_into(trips::table)
        .values(new_trip)
        .on_conflict(trips::text_id)
        .do_update()
        .set((
            trips::text_id.eq(trips::text_id),
            trips::first_observed.eq(trips::first_observed),
        ))
        .get_result(db)
        .map(|t| {
            let SelectTrip {
                id: current_trip_id,
                ..
            } = t;
            current_trip_id
        })
}
fn insert_delay(
    db: &mut PgConnection,
    new_delay: crate::Delay,
) -> Result<(), diesel::result::Error> {
    use crate::schema::delays;

    diesel::insert_into(delays::table)
        .values(new_delay)
        .execute(db)
        .map(|_| ())
}

pub fn crawler(db: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    // It looks like, HAFAS is only cabable of showing new state every 30seconds anyway.
    let loop_interval = Duration::from_secs(30);
    let mut next_execution = Instant::now() + loop_interval;

    loop {
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
            // let new_trip = Trip {
            //     first_observed: OffsetDateTime::now_utc(),
            //     text_id: trip.id.clone(),
            //     origin: trip.origin.name,
            //     destination: trip.destination.name,
            //     planned_departure_from_origin: trip.plannedDeparture,
            // };
            // let current_trip_id = match insert_trip(db, new_trip) {
            //     Ok(res) => res,
            //     Err(e) => {
            //         error!("Error inserting into trips: {}", e);
            //         continue;
            //     }
            // };

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
            let _trip_overview: TripOverview = match serde_json::from_str(&trip_overview_json) {
                Ok(res) => res,
                Err(e) => {
                    error!("Failed to deserialize trip overview: {}", e);
                    continue;
                }
            };
            // let (latitude, longitude) = trip_overview
            //     .trip
            //     .currentLocation
            //     .map_or((None, None), |tl| (Some(tl.latitude), Some(tl.longitude)));
            // let new_delay = Delay {
            //     trip_id: current_trip_id,
            //     observed_at: OffsetDateTime::now_utc(),
            //     generated_at: trip_overview.realtimeDataUpdatedAt,
            //     latitude: latitude,
            //     longitude: longitude,
            //     delay: trip_overview.trip.arrivalDelay,
            // };
            // match insert_delay(db, new_delay) {
            //     Ok(_) => (),
            //     Err(e) => {
            //         error!("{}", e);
            //         continue;
            //     }
            // };
        }
        sleep(next_execution - Instant::now());
        next_execution += loop_interval;
    }
}
