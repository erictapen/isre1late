// SPDX-FileCopyrightText: 2023 2023 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use diesel::pg::PgConnection;
use diesel::prelude::*;
use indicatif::{ProgressBar, ProgressStyle};
use log::{error, info};

/// Our progress bar template.
pub fn progress_style() -> ProgressStyle {
    ProgressStyle::with_template("[{elapsed}/{eta}] {wide_bar} {per_sec} {human_pos}/{human_len}")
        .unwrap()
}

/// Validate our representation of HAFAS types.
pub fn validate_hafas_schema(db: &mut PgConnection) -> Result<(), Box<dyn std::error::Error>> {
    use crate::schema::fetched_json::dsl::fetched_json;
    use crate::SelectFetchedJson;
    use std::fmt;

    #[derive(Debug)]
    struct SomeErrorsEncountered;

    impl std::error::Error for SomeErrorsEncountered {}

    impl fmt::Display for SomeErrorsEncountered {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "Some errors encountered")
        }
    }

    info!("Validating HAFAS schema...");
    let start = time::OffsetDateTime::now_utc();

    let bodies_count: i64 = fetched_json.count().get_result(db)?;
    let progress_bar = ProgressBar::new(bodies_count as u64);
    progress_bar.set_style(progress_style());

    let error_count: u64 = {
        use std::sync::mpsc::channel;
        use threadpool::ThreadPool;

        const MAX_QUEUED_COUNT: usize = 1024 * 1024 * 16;

        let bodies_iter =
            fetched_json.load_iter::<SelectFetchedJson, diesel::pg::PgRowByRowLoadingMode>(db)?;

        let thread_count =
            std::thread::available_parallelism().map_or(1, std::num::NonZeroUsize::get);
        let pool = ThreadPool::new(thread_count);

        let (tx, rx) = channel();

        for fj_res in bodies_iter {
            if pool.queued_count() < MAX_QUEUED_COUNT {
                let tx = tx.clone();
                pool.execute(move || {
                    let SelectFetchedJson { id, body, .. } = match fj_res {
                        Ok(fj) => fj,
                        Err(e) => {
                            error!("{}", e);
                            return;
                        }
                    };
                    match crate::transport_rest_vbb_v6::deserialize(body.as_ref()) {
                        Ok(_) => {}
                        Err(err) => {
                            // error!("Couldn't deserialize: {}", body.unwrap());
                            error!("{}: {}: \"{}\"", id, err, body);
                            tx.send(1)
                                .expect("channel will be there waiting for the pool");
                        }
                    };
                });
            } else {
                std::thread::sleep(std::time::Duration::from_millis(200));
            }
            progress_bar.inc(1);
        }
        pool.join();

        drop(tx);
        rx.iter().sum()
    };

    progress_bar.finish();

    let duration = time::OffsetDateTime::now_utc() - start;

    if error_count > 0 {
        error!("Encountered {} errors in {duration:.3}", error_count);
        Err(Box::new(SomeErrorsEncountered))
    } else {
        info!("Encountered no errors in {duration:.3}");
        Ok(())
    }
}
