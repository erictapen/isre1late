// @generated automatically by Diesel CLI.

diesel::table! {
    fetched_json (id) {
        id -> Int8,
        fetched_at -> Timestamptz,
        url -> Text,
        body -> Text,
    }
}
