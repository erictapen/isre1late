// @generated automatically by Diesel CLI.

diesel::table! {
    delays (id) {
        id -> Int8,
        trip_id -> Int8,
        observed_at -> Timestamptz,
        generated_at -> Timestamptz,
        latitude -> Nullable<Float8>,
        longitude -> Nullable<Float8>,
        delay -> Nullable<Int8>,
    }
}

diesel::table! {
    fetched_json (id) {
        id -> Int8,
        fetched_at -> Timestamptz,
        url -> Text,
        body -> Text,
    }
}

diesel::table! {
    trips (id) {
        id -> Int8,
        first_observed -> Timestamptz,
        text_id -> Text,
        origin -> Text,
        destination -> Text,
        planned_departure_from_origin -> Timestamptz,
    }
}

diesel::joinable!(delays -> trips (trip_id));

diesel::allow_tables_to_appear_in_same_query!(delays, fetched_json, trips,);
