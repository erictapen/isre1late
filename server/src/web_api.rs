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
use time::OffsetDateTime;

#[database("isre1late")]
struct DbConn(diesel::PgConnection);

#[get("/api/delay_events/day")]
async fn delay_events(conn: DbConn) -> Result<Json<Vec<DelayEvent>>, Status> {
    conn.run(|db| {
        use crate::schema::delay_events;
        let now = OffsetDateTime::now_utc();
        let start_of_day = now.date().midnight();

        info!("Sending DelayEvents coming from {}", start_of_day);

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
            .filter(delay_events::time.gt(start_of_day))
            .load::<DelayEvent>(db)
    })
    .await
    .map(Json)
    .map_err(|_| rocket::http::Status::InternalServerError)
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
        .mount("/", routes![delay_events])
        .attach(DbConn::fairing());
    rt.block_on(async move {
        let _ = builder.launch().await;
    });
    Ok(0)
}
