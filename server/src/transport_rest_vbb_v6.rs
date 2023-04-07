// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use serde::Deserialize;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

#[derive(Deserialize, Debug)]
pub struct Trips {
    trips: Vec<Trip>,
}

#[derive(Deserialize, Debug)]
pub struct Trip {
    // origin: TripOrigin,
    // destination: TripDestination,
    #[serde(with = "time::serde::rfc3339")]
    departure: OffsetDateTime,
}
