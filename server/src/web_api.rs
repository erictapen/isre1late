use rocket::*;
use tokio;

#[get("/delay_events")]
fn delay_events() -> &'static str {
    "Hello, world!"
}

pub fn webserver(port: u16) -> Result<i32, Box<dyn std::error::Error>> {
    let config = rocket::Config {
        port: port,
        ..Config::debug_default()
    };
    let rt = tokio::runtime::Runtime::new()?;
    let builder = rocket::custom(&config).mount("/", routes![delay_events]);
    rt.block_on(async move {
        let _ = builder.launch().await;
    });
    Ok(0)
}
