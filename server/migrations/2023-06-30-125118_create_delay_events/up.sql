CREATE TABLE IF NOT EXISTS delay_events
          ( id BIGSERIAL NOT NULL PRIMARY KEY
          , trip_id TEXT NOT NULL
          , time TIMESTAMP WITH TIME ZONE NOT NULL
          , previous_station BIGINT NOT NULL
          , next_station BIGINT NOT NULL
          , percentage_segment_from DOUBLE PRECISION NOT NULL
          , percentage_segment_to DOUBLE PRECISION NOT NULL
          , delay BIGINT NOT NULL
          );

CREATE INDEX delay_events_time_index ON delay_events (time);
