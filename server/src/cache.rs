use crate::cli_utils::progress_style;
use crate::models::{DelayEvent, DelayRecord, DelayRecordWithID};
use bytefmt;
use diesel::pg::PgConnection;
use indicatif::ProgressBar;
use log::{debug, info};
use memuse::DynamicUsage;
use num_format::{Locale, ToFormattedString};
use std::collections::HashMap;
use std::error::Error;
use time::Duration;
use time::OffsetDateTime;

/// Cache state that we don't save in db but generate on each startup.
/// Nothing too expensive should get in here, in order to preserve fast startup times.
pub struct CacheState {
    pub trip_id_map: HashMap<String, (i64, DelayRecord)>,
}

/// Update all the cache tables. This is everytime on startup, but would only do actual work in the
/// case of a manual cache deletion or when a new kind of cache got added.
/// The return object CacheState is then used by the crawler.
pub fn update_caches(
    db1: &mut PgConnection,
    mut db2: PgConnection,
) -> Result<CacheState, Box<dyn Error>> {
    update_delay_records(db1, &mut db2)?;
    let trip_id_map = update_delay_events(db1, db2)?;
    let usage: u64 = trip_id_map.dynamic_usage().try_into().unwrap();
    info!(
        "Built trip_id_map containing {} trip_id's, allocating about {} of memory.",
        trip_id_map.len().to_formatted_string(&Locale::en),
        bytefmt::format(usage)
    );
    Ok(CacheState {
        trip_id_map: trip_id_map,
    })
}

pub fn update_delay_records(
    db1: &mut PgConnection,
    db2: &mut PgConnection,
) -> Result<(), Box<dyn Error>> {
    use crate::models::delay_record_from_trip_overview;
    use crate::schema::delay_records;
    use crate::schema::fetched_json;
    use diesel::pg::PgRowByRowLoadingMode;
    use diesel::QueryDsl;
    use diesel::{ExpressionMethods, RunQueryDsl};
    use std::sync::mpsc::channel;
    use threadpool::ThreadPool;

    let bodies_count: i64 = fetched_json::dsl::fetched_json.count().get_result(db1)?;

    let latest_fetched_json_id: i64 = *delay_records::dsl::delay_records
        .select(delay_records::fetched_json_id)
        .order(delay_records::fetched_json_id.desc())
        .limit(1)
        .load::<i64>(db1)?
        .first()
        .unwrap_or(&0);

    let todo = u64::try_from(bodies_count - latest_fetched_json_id).unwrap_or(0);

    if todo <= 0 {
        return Ok(());
    }

    info!(
        "Generating DelayRecord's from {} json blobs for delay_records table.",
        todo.to_formatted_string(&Locale::en)
    );

    let progress_bar = ProgressBar::new(todo);
    progress_bar.set_style(progress_style());

    let fetched_json_iter = fetched_json::dsl::fetched_json
        .select((
            fetched_json::id,
            fetched_json::fetched_at,
            fetched_json::body,
        ))
        .filter(fetched_json::id.gt(latest_fetched_json_id))
        .then_order_by(fetched_json::id.asc())
        .load_iter::<(i64, OffsetDateTime, String), PgRowByRowLoadingMode>(db1)?;

    const MAX_QUEUED_COUNT: usize = 1024 * 1024 * 16;

    let thread_count = std::thread::available_parallelism().map_or(1, std::num::NonZeroUsize::get);
    let pool = ThreadPool::new(thread_count);

    let (tx, rx) = channel();

    for select_result in fetched_json_iter {
        if pool.queued_count() < MAX_QUEUED_COUNT {
            let (row_id, fetched_at, json_body) = select_result?;
            let tx = tx.clone();
            pool.execute(move || {
                if let Ok(trip_overview) = serde_json::from_str(&json_body) {
                    if let Some(dr) =
                        delay_record_from_trip_overview(trip_overview, row_id, fetched_at)
                    {
                        tx.send(dr).expect("Can't send DelayRecord through channel");
                    }
                }
            });
        } else {
            std::thread::sleep(std::time::Duration::from_millis(200));
        }
        progress_bar.inc(1);
    }
    pool.join();

    progress_bar.finish();

    drop(tx);

    let delay_records = rx.iter().collect::<Vec<DelayRecord>>();

    info!(
        "Inserting {} DelayRecord's into delay_records table.",
        &delay_records.len().to_formatted_string(&Locale::en)
    );

    let progress_bar = ProgressBar::new(delay_records.len() as u64);
    progress_bar.set_style(progress_style());

    // PostgreSQL doesn't allow more than 65535 parameters per statement
    let chunk_size = 1024;
    for dr_chunk in delay_records.chunks(chunk_size) {
        diesel::insert_into(delay_records::table)
            .values(dr_chunk)
            .execute(db2)?;
        progress_bar.inc(chunk_size as u64);
    }

    progress_bar.finish();

    Ok(())
}

pub fn update_delay_events(
    db1: &mut PgConnection,
    mut db2: PgConnection,
) -> Result<HashMap<String, (i64, DelayRecord)>, Box<dyn Error>> {
    use crate::schema::delay_events;
    use crate::schema::delay_records;
    use diesel::QueryDsl;
    use diesel::{ExpressionMethods, RunQueryDsl};

    let delay_records_count: i64 = delay_records::dsl::delay_records.count().get_result(db1)?;

    let latest_to_id: i64 = *delay_events::dsl::delay_events
        .select(delay_events::to_id)
        .order(delay_events::id.desc())
        .limit(1)
        .load::<i64>(db1)?
        .first()
        .unwrap_or(&0);

    let todo = u64::try_from(delay_records_count - latest_to_id).unwrap_or(0);

    if todo > 0 {
        info!("Updating {} entries in delay_events table.", todo);
    }

    info!(
        "Building trip_id_map from {} delay records.",
        delay_records_count.to_formatted_string(&Locale::en)
    );

    let progress_bar = ProgressBar::new(u64::try_from(delay_records_count).unwrap_or(0));
    progress_bar.set_style(progress_style());

    let delay_records_iter = delay_records::dsl::delay_records
        .then_order_by(delay_records::fetched_json_id.asc())
        .load::<DelayRecordWithID>(db1)?;

    // TODO This is going to grow over the entirety of the db, and is already taking a huge portion of
    // the RAM!
    //
    // For now we are reading all the delay records to build this HashMap. Maybe it would be safe
    // to assume, that looking at the last 48 hours would be enough?
    let mut trip_id_map: HashMap<String, (i64, DelayRecord)> = HashMap::new();

    let mut chunk = Vec::new();
    for new_delay_record_with_id in delay_records_iter {
        let new_delay_record = DelayRecord::from(new_delay_record_with_id);

        let des = delay_events_from_delay_record(&mut trip_id_map, &new_delay_record);

        // We only write to db if the delay event isn't there yet.
        if latest_to_id <= new_delay_record.fetched_json_id {
            for de in des {
                chunk.push(de);
            }
            if chunk.len() > 1024 {
                diesel::insert_into(delay_events::table)
                    .values(&chunk)
                    .execute(&mut db2)?;
                chunk = Vec::new();
            }
        }

        progress_bar.inc(1);
    }

    diesel::insert_into(delay_events::table)
        .values(&chunk)
        .execute(&mut db2)
        .unwrap();

    progress_bar.finish();

    Ok(trip_id_map)
}

/// Creates zero, one or two delay events from two rows (datapoints) from the fetched_json table.
/// One, if the two datapoints happened in the same track segment.
/// Two, if the train changed the track segment to an adjacent track segment.
/// Zero, if nothing of the above applies.
pub fn delay_events_from_delay_record(
    trip_id_map: &mut HashMap<String, (i64, DelayRecord)>,
    new_delay_record: &DelayRecord,
) -> Vec<DelayEvent> {
    let trip_id = new_delay_record.trip_id.clone();

    let new_row_id: i64 = new_delay_record.fetched_json_id;

    let mut result = vec![];

    // We expect new_delay_record to be the starting point of a trip otherwise. In that case we'd
    // skip the creation of a delay event and create one when the trip_id occurs next.
    if let Some((old_row_id, old_delay_record)) = trip_id_map.get(&trip_id) {
        let old = old_delay_record;
        let new = &new_delay_record;

        // The duration in seconds inbetween the two data points.
        let duration = (new.time - old.time).whole_seconds();

        if old.previous_station == new.previous_station && old.next_station == new.next_station {
            // The trip didn't change the segment inbetween the two datapoints

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
            let ratio = {
                let mut v = (1.0 - old.percentage_segment)
                    * (1.0 / (1.0 - old.percentage_segment + new.percentage_segment));
                if v.is_nan() {
                    // In this case (e.g. if the train is in a station for the entire duration) we
                    // just divide the event 50/50.
                    v = 0.5;
                }
                v
            };
            assert!(
                ratio >= 0.0 && ratio <= 1.0,
                "{:?} --- {:?}: {}",
                old,
                new,
                ratio
            );

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
    trip_id_map.insert(trip_id.clone(), (new_row_id, new_delay_record.clone()));
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

        let mut delay_events = delay_events_from_delay_record(
            &mut trip_id_map,
            &DelayRecord {
                fetched_json_id: 0,
                trip_id: "t1".to_string(),
                time: OffsetDateTime::UNIX_EPOCH,
                previous_station: 0,
                next_station: 1,
                percentage_segment: 0.5,
                delay: 0,
            },
        );

        assert_eq!(delay_events, vec![]);

        delay_events = delay_events_from_delay_record(
            &mut trip_id_map,
            &DelayRecord {
                fetched_json_id: 1,
                trip_id: "t1".to_string(),
                time: OffsetDateTime::UNIX_EPOCH + Duration::seconds(2),
                previous_station: 0,
                next_station: 1,
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
