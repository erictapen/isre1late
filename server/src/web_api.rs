use crate::models::DelayEvent;
use diesel::ExpressionMethods;
use diesel::QueryDsl;
use diesel::RunQueryDsl;
use rocket::http::Status;
use rocket::serde::json::Json;
//use rocket::*;
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
        .mount("/", routes![delay_events_day, delay_events_week])
        .attach(DbConn::fairing());
    rt.block_on(async move {
        let _ = builder.launch().await;
    });
    Ok(0)
}
