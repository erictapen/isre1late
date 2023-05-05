-- Your SQL goes here

CREATE TABLE IF NOT EXISTS trips
          ( id BIGSERIAL PRIMARY KEY
          , first_observed TIMESTAMP WITH TIME ZONE NOT NULL
          , text_id TEXT UNIQUE NOT NULL
          , origin TEXT NOT NULL
          , destination TEXT NOT NULL
          , planned_departure_from_origin TIMESTAMP WITH TIME ZONE NOT NULL
          )
