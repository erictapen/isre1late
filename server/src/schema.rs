// @generated automatically by Diesel CLI.

diesel::table! {
    delay_events (id) {
        id -> Int8,
        trip_id -> Text,
        time -> Timestamptz,
        previous_station -> Int8,
        next_station -> Int8,
        percentage_segment_from -> Float8,
        percentage_segment_to -> Float8,
        delay -> Int8,
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

diesel::allow_tables_to_appear_in_same_query!(delay_events, fetched_json,);
