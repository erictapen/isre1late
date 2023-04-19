-- Your SQL goes here

CREATE TABLE IF NOT EXISTS fetched_json
          ( id BIGSERIAL NOT NULL PRIMARY KEY
          , fetched_at TIMESTAMP WITH TIME ZONE NOT NULL
          , url TEXT NOT NULL
          , body TEXT NOT NULL
          )
