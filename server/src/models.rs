// SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::schema::*;
use diesel::prelude::*;
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

/// The serialisation of an delay event; A time and a span in space where a given trip had a
/// certain delay.
#[derive(Queryable, Insertable, Serialize, Debug, Clone)]
#[diesel(table_name = delay_events)]
pub struct DelayEvent {
    trip_id: String,
    #[serde(with = "time::serde::timestamp")]
    time: OffsetDateTime,
    previous_station: i64,
    next_station: i64,
    percentage_segment_from: f64,
    percentage_segment_to: f64,
    delay: i64,
}
