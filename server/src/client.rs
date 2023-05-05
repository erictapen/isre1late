// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::transport_rest_vbb_v6::TripOverview;
use log::debug;
use serde::Serialize;
use time::OffsetDateTime;

#[derive(Serialize, Debug, Clone)]
pub struct ClientMsg {
    trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    time: OffsetDateTime,
    previous_station: Option<i64>,
    next_station: Option<i64>,
    percentage_segment: f64,
    delay: i64,
}

/// Convert a TripOverview into a ClientMsg, intended for the webclient.
///
/// # Arguments
///
/// * `fetched_at` - TripOverviews don't always provide a datetime, so we need a fallback which
/// should be used from the fetched_at field from the database.
pub fn client_msg_from_trip_overview(to: TripOverview, fetched_at: OffsetDateTime) -> ClientMsg {
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

    ClientMsg {
        trip_id: trip.id,
        time: current_time,
        previous_station: previous_station,
        next_station: next_station,
        percentage_segment: percentage_segment,
        delay: delay.unwrap_or(0),
    }
}
