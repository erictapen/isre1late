// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// I'd rather keep the names from the JSON representation.
#![allow(non_snake_case)]

use monostate::MustBe;
use serde::Deserialize;
use serde_with::DisplayFromStr;
use time::OffsetDateTime;

/// Sometimes the nginx server itself returns an error.
const BAD_GATEWAY_FRAGMENT: &'static str = "502 Bad Gateway";

/// Wrapper function that allows us to deserialize empty strings.
pub fn deserialize(json: &str) -> Result<HafasMsg, serde_json::Error> {
    serde_json::from_str(json).or_else(|e| {
        if json.is_empty() {
            Ok(HafasMsg::EmptyBody())
        } else if json.contains(BAD_GATEWAY_FRAGMENT) {
            Ok(HafasMsg::BadGatewayError())
        } else {
            Err(e)
        }
    })
}

/// Some kind of umbrella type for all the stuff we can receive from HAFAS.
#[derive(Deserialize, Debug)]
#[serde(untagged)]
pub enum HafasMsg {
    TripOverview(TripOverview),
    TripsOverview(TripsOverview),
    TransportRestErr(TransportRestErr),
    HafasErr(HafasErr),
    EmptyBody(),
    BadGatewayError(),
}

#[derive(Deserialize, Debug)]
pub struct TransportRestErr {
    pub message: String,
    pub r#type: String,
    pub errno: String,
    pub code: String,
}

#[derive(Deserialize, Debug)]
pub struct HafasErr {
    pub message: String,
    pub isHafasError: MustBe!(true),
    pub hafasDescription: Option<String>,
}

/// Message we get from calling <https://v6.vbb.transport.rest/trips>
#[derive(Deserialize, Debug)]
pub struct TripsOverview {
    pub trips: Vec<Trip>,
}

/// Message we get from calling <https://v6.vbb.transport.rest/trips/{id}>
#[derive(Deserialize, Debug)]
pub struct TripOverview {
    pub trip: Trip,
    #[serde(with = "time::serde::timestamp::option")]
    pub realtimeDataUpdatedAt: Option<OffsetDateTime>,
}

#[derive(Deserialize, Debug)]
pub struct Trip {
    pub id: String,
    pub origin: TripOrigin,
    pub destination: TripDestination,
    #[serde(with = "time::serde::rfc3339::option")]
    pub departure: Option<OffsetDateTime>,
    #[serde(with = "time::serde::rfc3339")]
    pub plannedDeparture: OffsetDateTime,
    pub currentLocation: Option<TripLocation>,
    pub stopovers: Vec<TripStopover>,
    pub departureDelay: Option<i64>,
    pub arrivalDelay: Option<i64>,
}

#[derive(Deserialize, Debug)]
pub struct TripOrigin {
    pub name: String,
}

#[derive(Deserialize, Debug)]
pub struct TripDestination {
    pub name: String,
}

#[derive(Deserialize, Debug)]
pub struct TripLocation {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Deserialize, Debug)]
pub struct TripStopover {
    pub stop: TripStop,
    #[serde(with = "time::serde::rfc3339::option")]
    pub plannedArrival: Option<OffsetDateTime>,
    pub arrivalDelay: Option<i64>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub plannedDeparture: Option<OffsetDateTime>,
    pub departureDelay: Option<i64>,
}

#[serde_as]
#[derive(Deserialize, Debug)]
pub struct TripStop {
    pub name: String,
    #[serde_as(as = "DisplayFromStr")]
    pub id: i64,
}
