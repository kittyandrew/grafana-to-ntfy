#[macro_use] extern crate rocket;
extern crate base64;

use rocket::{State, http::Status, serde::json::{json, Json, Value}};
use lazy_static::lazy_static;
use reqwest::Client;
use std::env::var;
use dotenv;

mod bauth;
mod data;


lazy_static! {
    static ref NTFY_URL: String = var("NTFY_URL").unwrap();
    static ref BAUTH_USER: String = var("BAUTH_USER").unwrap_or(String::new());
    static ref BAUTH_PASS: String = var("BAUTH_PASS").unwrap_or(String::new());
}


#[get("/health")]
fn health() -> Value {
    // TODO: proper healthcheck.
    return json!({"status": 200})
}


#[post("/", format = "application/json", data = "<data>")]
async fn index(data: Json<data::Notification>, bauth: bauth::BAuth, client: &State<Client>) -> Result<Value, Status> {
    if (bauth.user != *BAUTH_USER) | (bauth.pass != *BAUTH_PASS) {
        return Err(Status::Unauthorized)
    }

    // Mapping grafana 'state' statuses^1 to the ntfy.sh emojis^23, so we have proper
    // warning emoji on the alertings state and so on..  @Incomplete
    //   ^1 - https://grafana.com/docs/grafana/latest/alerting/old-alerting/notifications/#webhook
    //   ^2 - https://ntfy.sh/docs/publish/#tags-emojis
    //   ^3 - https://ntfy.sh/docs/emojis
    //
    let tags_header = match data.state.as_str() {
        "alerting" => format!("{}, {}", "warning", &data.state),
        "ok" => format!("{}, {}", "white_check_mark", &data.state),
        // TODO: There are more 'state' values to map.
        _ => data.state.to_string(),
    };

    let result = client.post(NTFY_URL.clone())
        .body(data.message.clone().unwrap_or_default())
        .header("X-Tags", &tags_header)
        .header("X-Title", &data.title)
        .send()
        .await;

    // TODO: logging
    match result {
        Ok(_) => return Ok(json!({"status": 200})),
        Err(_) => return Err(Status::BadRequest)
    }
}


#[launch]
fn rocket() -> _ {
    dotenv::dotenv().ok();
    rocket::build().mount("/", routes![index, health]).manage(Client::new())
}

