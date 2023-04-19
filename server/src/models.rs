use crate::schema::*;
use diesel::prelude::*;
use time::OffsetDateTime;

#[derive(Queryable, Insertable)]
#[diesel(table_name = fetched_json)]
pub struct SelectFetchedJson {
    pub id: i64,
    pub fetched_at: OffsetDateTime,
    pub url: String,
    pub body: String,
}

#[derive(Queryable, Insertable)]
#[diesel(table_name = fetched_json)]
pub struct FetchedJson {
    pub fetched_at: OffsetDateTime,
    pub url: String,
    pub body: String,
}

#[derive(Queryable, Selectable, Insertable, Debug, PartialEq)]
#[diesel(table_name = trips)]
pub struct Trip {
    pub first_observed: OffsetDateTime,
    pub text_id: String,
    pub origin: String,
    pub destination: String,
    pub planned_departure_from_origin: OffsetDateTime,
}

#[derive(Queryable, Identifiable, Selectable, Debug, PartialEq)]
#[diesel(table_name = trips)]
pub struct SelectTrip {
    pub id: i64,
    pub first_observed: OffsetDateTime,
    pub text_id: String,
    pub origin: String,
    pub destination: String,
    pub planned_departure_from_origin: OffsetDateTime,
}

#[derive(Queryable, Selectable, Insertable, Associations, Debug, PartialEq)]
#[diesel(belongs_to(Trip))]
#[diesel(table_name = delays)]
pub struct Delay {
    pub trip_id: i64,
    pub observed_at: OffsetDateTime,
    pub generated_at: OffsetDateTime,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub delay: Option<i64>,
}
