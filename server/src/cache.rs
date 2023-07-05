use diesel::pg::PgConnection;
use log::debug;
use std::error::Error;
use time::Duration;

pub fn update_caches(db1: &mut PgConnection, db2: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    update_delay_events(db1, db2)?;
    Ok(())
}

pub fn update_delay_events(
    db1: &mut PgConnection,
    db2: &mut PgConnection,
) -> Result<(), Box<dyn Error>> {
    use crate::client::{client_msg_from_trip_overview, ClientMsg};
    use crate::models::DelayEvent;
    use crate::schema::delay_events;
    use crate::schema::fetched_json;
    use diesel::pg::PgRowByRowLoadingMode;
    use diesel::QueryDsl;
    // use diesel::query_dsl::methods::{FilterDsl, LimitDsl, OrderDsl, SelectDsl, ThenOrderDsl};
    use diesel::{ExpressionMethods, RunQueryDsl};
    use indicatif::{ProgressBar, ProgressStyle};
    use std::collections::HashMap;
    use time::OffsetDateTime;

    let bodies_count: i64 = fetched_json::dsl::fetched_json.count().get_result(db1)?;

    let latest_to_id: i64 = *delay_events::dsl::delay_events
        .select(delay_events::to_id)
        .order(delay_events::id.desc())
        .limit(1)
        .load::<i64>(db1)?
        .first()
        .unwrap_or(&0);

    let progress_bar = ProgressBar::new((bodies_count - latest_to_id) as u64);
    progress_bar.set_style(
        ProgressStyle::with_template(
            "[{elapsed}/{eta}] {wide_bar} {per_sec} {human_pos}/{human_len}",
        )
        .unwrap(),
    );

    let fetched_json_iter = fetched_json::dsl::fetched_json
        .select((
            fetched_json::id,
            fetched_json::fetched_at,
            fetched_json::body,
        ))
        .filter(fetched_json::id.gt(latest_to_id))
        .then_order_by(fetched_json::id.asc())
        .load_iter::<(i64, OffsetDateTime, String), PgRowByRowLoadingMode>(db1)?;

    // This is going to grow over the entirety of the db, but it should never be larger than a few
    // MB.
    let mut trip_id_map = HashMap::new();

    for select_result in fetched_json_iter {
        let (new_row_id, fetched_at, json_body) = select_result?;

        if let Ok(trip_overview) = serde_json::from_str(&json_body) {
            // stripped down version of ClientMsg
            #[derive(Debug)]
            struct DelayRecord {
                time: OffsetDateTime,
                previous_station: i64,
                next_station: i64,
                percentage_segment: f64,
                delay: i64,
            }

            let new_client_msg: ClientMsg =
                client_msg_from_trip_overview(trip_overview, fetched_at);

            let trip_id = new_client_msg.trip_id.clone();

            let new_delay_record = {
                let new_cm = new_client_msg;

                if let (Some(previous_station), Some(next_station)) =
                    (new_cm.previous_station, new_cm.next_station)
                {
                    assert!(previous_station != next_station);

                    DelayRecord {
                        time: new_cm.time,
                        previous_station: previous_station,
                        next_station: next_station,
                        percentage_segment: new_cm.percentage_segment,
                        delay: new_cm.delay,
                    }
                } else {
                    continue;
                }
            };

            match trip_id_map.get(&trip_id) {
                None => {
                    // We expect new_delay_record to be the starting point of a trip.
                    trip_id_map.insert(trip_id, (new_row_id, new_delay_record));
                }
                Some((old_row_id, old_delay_record)) => {
                    let old = old_delay_record;
                    let new = new_delay_record;

                    // The duration in seconds inbetween the two data points.
                    let duration = (new.time - old.time).whole_seconds();

                    if old.previous_station == new.previous_station
                        && old.next_station == new.next_station
                    {
                        // The trip didn't change the segment inbetween the two datapoints.
                        let delay_event = DelayEvent {
                            from_id: *old_row_id,
                            to_id: new_row_id,
                            trip_id: trip_id,
                            time: old.time + ((new.time - old.time) / 2),
                            duration: duration,
                            previous_station: old.previous_station,
                            next_station: old.next_station,
                            percentage_segment: old.percentage_segment
                                + ((new.percentage_segment - old.percentage_segment) / 2.0),
                            delay: (old.delay + new.delay) / 2,
                        };

                        diesel::insert_into(delay_events::table)
                            .values(&delay_event)
                            .execute(db2)?;
                    } else if old.next_station == new.previous_station {
                        // The trip passed a station inbetwwen the two datapoints, so we have to
                        // create two delay events.

                        // The ratio we assume between the two delay events. This is inaccurate and
                        // will likely cause artifacts, as we are using percentage of distance as a
                        // proxy for time. For the real value we'd need an actual timetable.
                        let ratio = (1.0 - old.percentage_segment) / new.percentage_segment;

                        // The timestamp inbetween the two delay events, e.g. an idealised point in
                        // time where the train was in the station.
                        let switch_time =
                            old.time + Duration::seconds((duration as f64 * ratio) as i64);

                        let time1 = old.time + ((switch_time - old.time) / 2);
                        let time2 = switch_time + ((new.time - switch_time) / 2);
                        let duration1 = (switch_time - old.time).whole_seconds();
                        let duration2 = (new.time - switch_time).whole_seconds();
                        let percentage_segment1 = (old.percentage_segment + 1.0) / 2.0;
                        let percentage_segment2 = (0.0 + new.percentage_segment) / 2.0;

                        let delay_event1 = DelayEvent {
                            from_id: *old_row_id,
                            to_id: new_row_id,
                            trip_id: trip_id.clone(),
                            time: time1,
                            duration: duration1,
                            previous_station: old.previous_station,
                            next_station: old.next_station,
                            percentage_segment: percentage_segment1,
                            delay: (old.delay as f64 * ratio) as i64,
                        };
                        let delay_event2 = DelayEvent {
                            from_id: *old_row_id,
                            to_id: new_row_id,
                            trip_id: trip_id.clone(),
                            time: time2,
                            duration: duration2,
                            previous_station: new.previous_station,
                            next_station: new.next_station,
                            percentage_segment: percentage_segment2,
                            delay: (old.delay as f64 * (1.0 - ratio)) as i64,
                        };

                        diesel::insert_into(delay_events::table)
                            .values(&vec![delay_event1, delay_event2])
                            .execute(db2)?;
                    } else {
                        debug!("Can't build a delay_event, as Between {} and {} more than one station was passed.", old_row_id, new_row_id);
                    }
                }
            }
        }
        progress_bar.inc(1);
    }

    progress_bar.finish();

    Ok(())
}
