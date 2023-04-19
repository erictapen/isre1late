-- Your SQL goes here

CREATE TABLE IF NOT EXISTS delays
          ( id BIGSERIAL PRIMARY KEY
          , trip_id BIGSERIAl REFERENCES trips(id)
          , observed_at TIMESTAMP WITH TIME ZONE NOT NULL
          , generated_at TIMESTAMP WITH TIME ZONE NOT NULL
          , latitude DOUBLE PRECISION
          , longitude DOUBLE PRECISION
          , delay BIGINT
          )
