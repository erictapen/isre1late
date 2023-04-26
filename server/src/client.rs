// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::transport_rest_vbb_v6::TripOverview;
use log::{debug, error, info, warn};
use serde::Serialize;
use time::OffsetDateTime;

#[derive(Serialize, Debug, Clone)]
pub struct ClientMsg {
    trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    time: OffsetDateTime,
    previous_station: Option<String>,
    next_station: Option<String>,
    percentage_segment: f64,
    delay: i64,
}

pub fn client_msg_from_trip_overview(to: TripOverview) -> Result<ClientMsg, String> {
    let current_time = to.realtimeDataUpdatedAt;
    let trip = to.trip;

    let mut previous_station = None;
    let mut next_station = None;

    let mut previous_departure = None;
    let mut next_arrival = None;

    for stopover in trip.stopovers {
        if stopover
            .plannedDeparture
            .map_or(false, |d| current_time > d)
        {
            previous_station = Some(stopover.stop.name);
            previous_departure = stopover.plannedDeparture;
        } else if stopover.plannedArrival.map_or(false, |a| current_time < a) {
            next_station = Some(stopover.stop.name);
            next_arrival = stopover.plannedArrival;
            break;
        } else {
            // TODO Train should be in the station currently
            break;
        }
    }

    let percentage_segment = match (
        previous_departure.map(OffsetDateTime::unix_timestamp),
        next_arrival.map(OffsetDateTime::unix_timestamp),
    ) {
        (Some(d), Some(a)) => (current_time.unix_timestamp() - d) as f64 / (a - d) as f64,
        _ => 0.0,
    };

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

    Ok(ClientMsg {
        trip_id: trip.id,
        time: current_time,
        previous_station: previous_station,
        next_station: next_station,
        percentage_segment: percentage_segment,
        delay: trip.departureDelay.unwrap_or(0),
    })
}
