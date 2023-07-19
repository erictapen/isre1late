use diesel::QueryDsl;
use diesel::RunQueryDsl;
use http::Status;
use rocket::*;
use rocket_sync_db_pools::{database, diesel};
use tokio;

#[database("isre1late")]
struct DbConn(diesel::PgConnection);

#[get("/api/delay_events")]
async fn delay_events(conn: DbConn) -> Result<String, Status> {
    use crate::schema::delay_events;

    conn.run(|db| {
        delay_events::dsl::delay_events
            .count()
            .get_result::<i64>(db)
    })
    .await
    .map(|i| i.to_string())
    .map_err(|_| rocket::http::Status::InternalServerError)
}

pub fn webserver(
    db_url: &str,
    listen: std::net::IpAddr,
    port: u16,
) -> Result<i32, Box<dyn std::error::Error>> {
    use crate::web_api::figment::Figment;
    use rocket::figment::{
        util::map,
        value::{Map, Value},
    };

    let rt = tokio::runtime::Runtime::new()?;

    let config = rocket::Config {
        port: port,
        address: listen,
        ..Config::debug_default()
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
