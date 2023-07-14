// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::schema::*;
use crate::transport_rest_vbb_v6::TripOverview;
use diesel::prelude::*;
use log::debug;
use serde::Serialize;
use time::OffsetDateTime;

#[derive(Queryable, Insertable)]
#[diesel(table_name = fetched_json)]
pub struct SelectFetchedJson {
    pub id: i64,
    pub fetched_at: OffsetDateTime,
    pub url: String,
    pub body: String,
}

#[derive(Queryable, Insertable)]
#[diesel(table_name = fetched_json)]
pub struct FetchedJson {
    pub fetched_at: OffsetDateTime,
    pub url: String,
    pub body: String,
}

/// Don't take any assumptions about this struct's id field!
#[derive(Queryable, Insertable, Serialize, Debug, Clone)]
#[diesel(table_name = delay_records)]
pub struct DelayRecordWithID {
    pub id: i64,
    pub fetched_json_id: i64,
    pub trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    pub time: OffsetDateTime,
    pub previous_station: i64,
    pub next_station: i64,
    pub percentage_segment: f64,
    pub delay: i64,
}

#[derive(Queryable, Insertable, Serialize, Debug, Clone)]
pub struct DelayRecord {
    pub fetched_json_id: i64,
    pub trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    pub time: OffsetDateTime,
    pub previous_station: i64,
    pub next_station: i64,
    pub percentage_segment: f64,
    pub delay: i64,
}

impl From<DelayRecordWithID> for DelayRecord {
    fn from(item: DelayRecordWithID) -> Self {
        DelayRecord {
            fetched_json_id: item.fetched_json_id,
            trip_id: item.trip_id,
            time: item.time,
            previous_station: item.previous_station,
            next_station: item.next_station,
            percentage_segment: item.percentage_segment,
            delay: item.delay,
        }
    }
}

/// Convert a TripOverview into a DelayRecord.
///
/// If we can't determine both a previous_station and a next_station, Nothing is returned.
///
/// # Arguments
///
/// * `fetched_at` - TripOverviews don't always provide a datetime, so we need a fallback which
/// should be used from the fetched_at field from the database.
pub fn delay_record_from_trip_overview(
    to: TripOverview,
    fetched_json_id: i64,
    fetched_at: OffsetDateTime,
) -> Option<DelayRecord> {
    // Sometimes realtimeDataUpdatedAt is null, we just use the time the crawler got the response
    // then.
    let current_time = match to.realtimeDataUpdatedAt {
        Some(ct) => ct,
        None => {
            debug!(
                "realtimeDataUpdatedAt is not available, using fetched_at field from db instead"
            );
            fetched_at
        }
    };
    let trip = to.trip;

    let mut previous_station = None;
    let mut next_station = None;

    let mut previous_departure = None;
    let mut next_arrival = None;

    let mut delay = None;

    let mut percentage_segment = -1.0;

    for stopover in trip.stopovers {
        if stopover
            .plannedDeparture
            .map_or(false, |d| current_time > d)
        {
            previous_station = Some(stopover.stop.id);
            previous_departure = stopover.plannedDeparture;
        } else if stopover.plannedArrival.map_or(false, |a| current_time < a) {
            next_station = Some(stopover.stop.id);
            next_arrival = stopover.plannedArrival;
            delay = stopover.arrivalDelay;

            // We just assume the passed track linearly by time, for the lack of better data.
            percentage_segment = match (
                previous_departure.map(OffsetDateTime::unix_timestamp),
                next_arrival.map(OffsetDateTime::unix_timestamp),
            ) {
                (Some(d), Some(a)) => (current_time.unix_timestamp() - d) as f64 / (a - d) as f64,
                _ => 0.0,
            };

            break;
        }
        // Train should be waiting in the next_station currently
        else {
            next_station = Some(stopover.stop.id);
            delay = stopover.departureDelay;
            percentage_segment = 1.0;
            break;
        }
    }

    debug!(
        "{} should be between {} and {}",
        current_time,
        previous_departure.unwrap_or(OffsetDateTime::UNIX_EPOCH),
        next_arrival.unwrap_or(OffsetDateTime::UNIX_EPOCH)
    );
    debug!(
        "{} should be between {} and {}",
        current_time.unix_timestamp(),
        previous_departure
            .unwrap_or(OffsetDateTime::UNIX_EPOCH)
            .unix_timestamp(),
        next_arrival
            .unwrap_or(OffsetDateTime::UNIX_EPOCH)
            .unix_timestamp()
    );
    debug!("percentage_segment: {}", percentage_segment);
    assert!(percentage_segment >= 0.0);
    assert!(percentage_segment <= 1.0);

    if let (Some(previous_station), Some(next_station)) = (previous_station, next_station) {
        Some(DelayRecord {
            fetched_json_id: fetched_json_id,
            trip_id: trip.id,
            time: current_time,
            previous_station: previous_station,
            next_station: next_station,
            percentage_segment: percentage_segment,
            delay: delay.unwrap_or(0),
        })
    } else {
        None
    }
}

/// The serialisation of an delay event; A time and a span in space where a given trip had a
/// certain delay.
#[derive(Queryable, Insertable, Serialize, Debug, Clone, PartialEq)]
#[diesel(table_name = delay_events)]
pub struct DelayEvent {
    pub from_id: i64,
    pub to_id: i64,
    pub trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    pub time: OffsetDateTime,
    pub duration: i64,
    pub previous_station: i64,
    pub next_station: i64,
    pub percentage_segment: f64,
    pub delay: i64,
}
