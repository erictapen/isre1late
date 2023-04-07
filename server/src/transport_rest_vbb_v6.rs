// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use serde::Deserialize;
use time::OffsetDateTime;

#[derive(Deserialize, Debug)]
pub struct Trips {
    pub trips: Vec<Trip>,
}

#[derive(Deserialize, Debug)]
pub struct Trip {
    pub id: String,
    pub origin: TripOrigin,
    pub destination: TripDestination,
    #[serde(with = "time::serde::rfc3339")]
    pub departure: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    pub plannedDeparture: OffsetDateTime,
    pub currentLocation: TripLocation,
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
}

#[derive(Deserialize, Debug)]
pub struct TripStop {
    pub name: String,
}
