-- SPDX-FileCopyrightText: 2023 2023 Kerstin Humm <mail@erictapen.name>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

CREATE TABLE IF NOT EXISTS delay_records
          ( id BIGSERIAL NOT NULL PRIMARY KEY
          , fetched_json_id BIGSERIAL NOT NULL UNIQUE REFERENCES fetched_json(id)
          , trip_id TEXT NOT NULL
          , time TIMESTAMP WITH TIME ZONE NOT NULL
          , previous_station BIGINT NOT NULL
          , next_station BIGINT NOT NULL
          , percentage_segment DOUBLE PRECISION NOT NULL
          , delay BIGINT NOT NULL
          );

CREATE INDEX delay_records_time_index ON delay_records (time);
CREATE INDEX delay_records_trip_id_index ON delay_records (trip_id);
CREATE INDEX delay_records_fetched_json_id_index ON delay_records (fetched_json_id);

