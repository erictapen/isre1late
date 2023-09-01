// SPDX-FileCopyrightText: 2023 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::models::DelayEvent;
use diesel::ExpressionMethods;
use diesel::QueryDsl;
use diesel::RunQueryDsl;
use rocket::http::Status;
use rocket::serde::json::Json;
//use rocket::*;
use crate::transport_rest_vbb_v6::{HafasMsg, Trip, TripOverview};
use log::info;
use rocket::tokio;
use rocket::{get, routes};
use rocket_sync_db_pools::{database, diesel};
use time::{Duration, OffsetDateTime};

#[database("isre1late")]
struct DbConn(diesel::PgConnection);

async fn load_delay_events(
    conn: DbConn,
    from: OffsetDateTime,
) -> Result<Json<Vec<DelayEvent>>, Status> {
    conn.run(move |db| {
        use crate::schema::delay_events;

        info!("Sending DelayEvents coming from {}", from);

        delay_events::dsl::delay_events
            .select((
                delay_events::from_id,
                delay_events::to_id,
                delay_events::trip_id,
                delay_events::time,
                delay_events::duration,
                delay_events::previous_station,
                delay_events::next_station,
                delay_events::percentage_segment,
                delay_events::delay,
            ))
            .filter(delay_events::time.gt(from))
            .load::<DelayEvent>(db)
    })
    .await
    .map(Json)
    .map_err(|_| rocket::http::Status::InternalServerError)
}

/// Load delay_events for the last 24 hours
#[get("/api/delay_events/day")]
async fn delay_events_day(conn: DbConn) -> Result<Json<Vec<DelayEvent>>, Status> {
    let from = OffsetDateTime::now_utc() - Duration::DAY;
    load_delay_events(conn, from).await
}

/// Load delay_events for the last 7 days
#[get("/api/delay_events/week")]
async fn delay_events_week(conn: DbConn) -> Result<Json<Vec<DelayEvent>>, Status> {
    let from = OffsetDateTime::now_utc() - Duration::WEEK;
    load_delay_events(conn, from).await
}

/// Detailed information about one Trip, identified by its trip_id.
#[get("/api/trip/<trip_id>")]
async fn trip(conn: DbConn, trip_id: String) -> Result<Json<Trip>, Status> {
    conn.run(move |db| {
        use crate::schema::fetched_json;

        fetched_json::dsl::fetched_json
            .select(fetched_json::body)
            .filter(fetched_json::url.eq(crate::crawler::trips_url(&trip_id)))
            .then_order_by(fetched_json::fetched_at.asc())
            .limit(1)
            .load::<String>(db)
    })
    .await
    .map_err(|_| rocket::http::Status::InternalServerError)
    .and_then(|json_strs| {
        let json_str = json_strs.get(0).ok_or(rocket::http::Status::NotFound)?;
        match crate::transport_rest_vbb_v6::deserialize(json_str) {
            Ok(HafasMsg::TripOverview(TripOverview { trip, .. })) => Ok(trip),
            _ => Err(rocket::http::Status::InternalServerError),
        }
    })
    .map(Json)
}

pub fn webserver(
    db_url: &str,
    listen: std::net::IpAddr,
    port: u16,
) -> Result<i32, Box<dyn std::error::Error>> {
    use rocket::figment::Figment;
    use rocket::figment::{
        util::map,
        value::{Map, Value},
    };

    let rt = tokio::runtime::Runtime::new()?;

    let config = rocket::Config {
        port: port,
        address: listen,
        ..rocket::Config::debug_default()
    };
    let db_map: Map<_, Value> = map! {
        "url" => db_url.into(),
    };
    let figment = Figment::from(config).merge(("databases", map!["isre1late" => db_map]));
    let builder = rocket::custom(&figment)
        .mount("/", routes![delay_events_day, delay_events_week, trip])
        .attach(DbConn::fairing());
    rt.block_on(async move {
        let _ = builder.launch().await;
    });
    Ok(0)
}
