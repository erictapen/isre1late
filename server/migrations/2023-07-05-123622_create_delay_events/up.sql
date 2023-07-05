DROP TABLE IF EXISTS delay_events;

CREATE TABLE IF NOT EXISTS delay_events
          ( id BIGSERIAL NOT NULL PRIMARY KEY
          , from_id BIGSERIAL REFERENCES fetched_json(id)
          , to_id BIGSERIAL REFERENCES fetched_json(id)
          , trip_id TEXT NOT NULL
          , time TIMESTAMP WITH TIME ZONE NOT NULL
          , duration BIGINT NOT NULL
          , previous_station BIGINT NOT NULL
          , next_station BIGINT NOT NULL
          , percentage_segment DOUBLE PRECISION NOT NULL
          , delay BIGINT NOT NULL
          );

CREATE INDEX delay_events_time_index ON delay_events (time);



