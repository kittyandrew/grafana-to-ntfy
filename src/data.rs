use rocket::serde::json::Value;
use rocket::serde::Deserialize;


#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Match {
    pub metric: String,
    // TODO: Document type properly.
    pub tags: Value,
    pub value: i64,
}


#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Notification {
    // Note(andrew): 'message' field is not always present.
    pub message: Option<String>,
    pub state: String,
    pub title: String,
}

