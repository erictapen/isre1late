// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use serde::Deserialize;
use time::OffsetDateTime;

#[derive(Deserialize, Debug)]
pub struct TripsOverview {
    pub trips: Vec<Trip>,
}

#[derive(Deserialize, Debug)]
pub struct TripOverview {
    pub trip: Trip,
    #[serde(with = "time::serde::timestamp")]
    pub realtimeDataUpdatedAt: OffsetDateTime,
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
    #[serde(with = "time::serde::rfc3339::option")]
    pub plannedDeparture: Option<OffsetDateTime>,
}

#[derive(Deserialize, Debug)]
pub struct TripStop {
    pub name: String,
}
