use crate::{DelayRecord, SelectFetchedJson};
use bus::BusReadHandle;
use diesel::PgConnection;
use log::{debug, error, info, warn};
use serde::Deserialize;
use std::error::Error;

/// Open the webserver and publish fetched data via Websockets.
pub fn websocket_server(
    db: &mut PgConnection,
    bus_read_handle: BusReadHandle<DelayRecord>,
    listen: std::net::IpAddr,
    port: u16,
) -> Result<(), Box<dyn Error>> {
    use crate::models::delay_record_from_trip_overview;
    use crate::schema::fetched_json;
    use diesel::ExpressionMethods;
    use diesel::QueryDsl;
    use diesel::RunQueryDsl;
    use std::net::{IpAddr, SocketAddr, SocketAddrV4, SocketAddrV6};

    let socket_addr: std::net::SocketAddr = match listen {
        IpAddr::V4(addr) => SocketAddr::V4(SocketAddrV4::new(addr, port)),
        IpAddr::V6(addr) => SocketAddr::V6(SocketAddrV6::new(addr, port, 0, 0)),
    };

    let server = std::net::TcpListener::bind(socket_addr).unwrap_or_else(|_| {
        error!("Can't bind to {}", socket_addr);
        std::process::exit(1);
    });
    info!("Server started.");
    for stream in server.incoming() {
        use tungstenite::handshake::server::{Request, Response};

        // Default is one hour.
        let mut historic_seconds = 3600;

        let ws_callback = |request: &Request, response: Response| {
            #[derive(Deserialize, Debug)]
            struct Query {
                historic: u64,
            }

            if let Some(query_str) = request.uri().query() {
                debug!("query_str: {}", query_str);
                match serde_qs::from_str(&query_str) {
                    Err(e) => {
                        error!("{}", e);
                    }
                    Ok(Query { historic }) => {
                        historic_seconds = std::cmp::min(historic, 3600 * 24 * 31);
                    }
                }
            }

            match request.uri().path() {
                "/api/ws/delays" => {
                    debug!("The request's route is: /api/ws/delays");
                    Ok(response)
                }
                other_path => {
                    warn!("Path {} is not available.", other_path);
                    let not_found = Response::builder()
                        .status(tungstenite::http::StatusCode::NOT_FOUND)
                        .body(Some("Path not found.".into()))
                        .expect("This should never fail.");
                    Err(not_found)
                }
            }
        };
        match stream {
            Ok(stream) => {
                let mut websocket = match tungstenite::accept_hdr(stream, ws_callback) {
                    Ok(ws) => ws,
                    Err(e) => {
                        warn!("{}", e);
                        continue;
                    }
                };

                use crate::schema::fetched_json::fetched_at;
                use fetched_json::dsl::fetched_json;

                let mut rx = bus_read_handle.add_rx();

                use std::net::TcpStream;
                use tungstenite::protocol::WebSocket;
                use tungstenite::Message::Text;

                fn send_message(
                    websocket: &mut WebSocket<TcpStream>,
                    msg: DelayRecord,
                ) -> Result<(), ()> {
                    match websocket.write_message(Text(
                        serde_json::to_string(&msg).expect("This shouldn't fail."),
                    )) {
                        Err(e) => {
                            warn!(
                                "{:?}: Couldn't send message to subscriber: {}",
                                std::thread::current().id(),
                                e
                            );
                            Err(())
                        }
                        Ok(_) => {
                            debug!(
                                "{:?}: Sent message to subscriber successfully.",
                                std::thread::current().id()
                            );
                            Ok(())
                        }
                    }
                }

                {
                    use std::time::Duration;
                    use time::OffsetDateTime;

                    let old_delays = fetched_json
                        .filter(
                            fetched_at
                                .gt(OffsetDateTime::now_utc()
                                    - Duration::from_secs(historic_seconds)),
                        )
                        .then_order_by(fetched_at.asc())
                        .load_iter::<SelectFetchedJson, diesel::pg::PgRowByRowLoadingMode>(db)
                        .unwrap_or_else(|e| {
                            panic!("Unable to load data from fetched_json: {}", e);
                        });

                    for fj_result in old_delays {
                        let fj = fj_result?;
                        if let Ok(trip_overview) = serde_json::from_str(&fj.body) {
                            if let Some(delay_record) =
                                delay_record_from_trip_overview(trip_overview, fj.id, fj.fetched_at)
                            {
                                let _ = send_message(&mut websocket, delay_record);
                            }
                        }
                    }
                }

                debug!("Sent old messages to client, switching to live update now.");

                std::thread::spawn(move || {
                    while let Ok(msg) = rx.recv() {
                        if send_message(&mut websocket, msg).is_err() {
                            break;
                        };
                    }

                    info!("Closing websocket");
                    websocket
                        .close(None)
                        .unwrap_or_else(|_| warn!("Can't close websocket in a normal way."));
                    websocket
                        .write_pending()
                        .unwrap_or_else(|_| warn!("Couldn't write pending close frame."));
                });
            }
            Err(_) => {
                warn!("Close connection.");
                continue;
            }
        };
    }
    Ok(())
}
