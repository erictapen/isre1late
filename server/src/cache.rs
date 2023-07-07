use crate::client::ClientMsg;
use crate::models::DelayEvent;
use diesel::pg::PgConnection;
use log::debug;
use std::collections::HashMap;
use std::error::Error;
use time::Duration;
use time::OffsetDateTime;

pub fn update_caches(db1: &mut PgConnection, db2: &mut PgConnection) -> Result<(), Box<dyn Error>> {
    update_delay_events(db1, db2)?;
    Ok(())
}

pub fn update_delay_events(
    db1: &mut PgConnection,
    db2: &mut PgConnection,
) -> Result<(), Box<dyn Error>> {
    use crate::schema::delay_events;
    use crate::schema::fetched_json;
    use diesel::pg::PgRowByRowLoadingMode;
    use diesel::QueryDsl;
    // use diesel::query_dsl::methods::{FilterDsl, LimitDsl, OrderDsl, SelectDsl, ThenOrderDsl};
    use crate::client::client_msg_from_trip_overview;
    use diesel::{ExpressionMethods, RunQueryDsl};
    use indicatif::{ProgressBar, ProgressStyle};

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

    // This is going to grow over the entirety of the db, but it should never get larger than a few
    // MB anyway.
    // TODO An empty HashMap is only correct when we start at row 1. Otherwise we need to read the
    // last ClientMsg's for every trip_id from DB! Maybe it would be safe to assume, that a looking
    // at the last 48 hours would be enough?
    let mut trip_id_map = HashMap::new();

    for select_result in fetched_json_iter {
        let (new_row_id, fetched_at, json_body) = select_result?;

        if let Ok(trip_overview) = serde_json::from_str(&json_body) {
            let new_client_msg: ClientMsg =
                client_msg_from_trip_overview(trip_overview, fetched_at);

            let delay_events =
                delay_events_from_client_msg(&mut trip_id_map, new_row_id, new_client_msg);

            if !delay_events.is_empty() {
                diesel::insert_into(delay_events::table)
                    .values(&delay_events)
                    .execute(db2)?;
            }
        }

        progress_bar.inc(1);
    }

    progress_bar.finish();

    Ok(())
}

// stripped down version of ClientMsg
#[derive(Debug)]
struct DelayRecord {
    time: OffsetDateTime,
    previous_station: i64,
    next_station: i64,
    percentage_segment: f64,
    delay: i64,
}

/// Creates zero, one or two delay events from two rows (datapoints) from the fetched_json table.
/// One, if the two datapoints happened in the same track segment.
/// Two, if the train changed the track segment to an adjacent track segment.
/// Zero, if nothing of the above applies.
fn delay_events_from_client_msg(
    trip_id_map: &mut HashMap<String, (i64, DelayRecord)>,
    new_row_id: i64,
    new_client_msg: ClientMsg,
) -> Vec<DelayEvent> {
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
            // We only consider ClientMsg's that have both stations set.
            return vec![];
        }
    };

    let mut result = vec![];

    // We expect new_delay_record to be the starting point of a trip otherwise. In that case we'd
    // skip the creation of a delay event and create one when the trip_id occurs next.
    if let Some((old_row_id, old_delay_record)) = trip_id_map.get(&trip_id) {
        let old = old_delay_record;
        let new = &new_delay_record;

        // The duration in seconds inbetween the two data points.
        let duration = (new.time - old.time).whole_seconds();

        if old.previous_station == new.previous_station && old.next_station == new.next_station {
            // The trip didn't change the segment inbetween the two datapoints.
            let delay_event = DelayEvent {
                from_id: *old_row_id,
                to_id: new_row_id,
                trip_id: trip_id.clone(),
                time: old.time + ((new.time - old.time) / 2),
                duration: duration,
                previous_station: old.previous_station,
                next_station: old.next_station,
                percentage_segment: old.percentage_segment
                    + ((new.percentage_segment - old.percentage_segment) / 2.0),
                delay: (old.delay + new.delay) / 2,
            };

            result = vec![delay_event];
        } else if old.next_station == new.previous_station {
            // The trip passed a station inbetwwen the two datapoints, so we have to
            // create two delay events.

            // The ratio we assume between the two delay events. This is inaccurate and
            // will likely cause artifacts, as we are using percentage of distance as a
            // proxy for time. For the real value we'd need an actual timetable.
            let ratio = (1.0 - old.percentage_segment) / new.percentage_segment;

            // The timestamp inbetween the two delay events, e.g. an idealised point in
            // time where the train was in the station.
            let switch_time = old.time + Duration::seconds((duration as f64 * ratio) as i64);

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

            result = vec![delay_event1, delay_event2];
        } else {
            debug!(
                "Can't build a delay_event, as Between {} and {} more than one station was passed.",
                old_row_id, new_row_id
            );
            result = vec![];
        }
    };
    trip_id_map.insert(trip_id.clone(), (new_row_id, new_delay_record));
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use time::{Duration, OffsetDateTime};

    #[test]
    fn normal_delay_event() -> Result<(), Box<dyn Error>> {
        let mut trip_id_map = HashMap::new();

        let mut delay_events = delay_events_from_client_msg(
            &mut trip_id_map,
            0,
            ClientMsg {
                trip_id: "t1".to_string(),
                time: OffsetDateTime::UNIX_EPOCH,
                previous_station: Some(0),
                next_station: Some(1),
                percentage_segment: 0.5,
                delay: 0,
            },
        );

        assert_eq!(delay_events, vec![]);

        delay_events = delay_events_from_client_msg(
            &mut trip_id_map,
            1,
            ClientMsg {
                trip_id: "t1".to_string(),
                time: OffsetDateTime::UNIX_EPOCH + Duration::seconds(2),
                previous_station: Some(0),
                next_station: Some(1),
                percentage_segment: 0.7,
                delay: 60,
            },
        );

        assert_eq!(
            delay_events,
            vec![DelayEvent {
                from_id: 0,
                to_id: 1,
                trip_id: "t1".to_string(),
                time: OffsetDateTime::UNIX_EPOCH + Duration::seconds(1),
                duration: 2,
                previous_station: 0,
                next_station: 1,
                percentage_segment: 0.6,
                delay: 30
            }]
        );

        Ok(())
    }
}
