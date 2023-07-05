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
