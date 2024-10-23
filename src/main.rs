#[macro_use]
extern crate rocket;

use dotenv;
use lazy_static::lazy_static;
use reqwest::Client;
use rocket::http::Status;
use rocket::serde::json::{json, Json, Value};
use rocket::State;
use std::env::var;

mod bauth;
mod data;

lazy_static! {
    static ref NTFY_URL: String = var("NTFY_URL").unwrap();
    static ref NTFY_BAUTH_USER: String = var("NTFY_BAUTH_USER").unwrap_or(String::new());
    static ref NTFY_BAUTH_PASS: String = var("NTFY_BAUTH_PASS").unwrap_or(String::new());
    static ref BAUTH_USER: String = var("BAUTH_USER").unwrap_or(String::new());
    static ref BAUTH_PASS: String = var("BAUTH_PASS").unwrap_or(String::new());
}

#[get("/health")]
fn health() -> Value {
    // TODO: proper healthcheck.
    return json!({"status": 200});
}

#[post("/", format = "application/json", data = "<data>")]
async fn index(data: Json<data::Notification>, bauth: bauth::BAuth, client: &State<Client>) -> Result<Value, Status> {
    if (bauth.user != *BAUTH_USER) | (bauth.pass != *BAUTH_PASS) {
        return Err(Status::Unauthorized);
    }

    // Mapping grafana 'status'^1 to the ntfy.sh emojis^23, so we have proper
    // warning emoji on the alertings state and so on..
    //   ^1 - https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/webhook-notifier/
    //   ^2 - https://ntfy.sh/docs/publish/#tags-emojis
    //   ^3 - https://ntfy.sh/docs/emojis
    //
    let tags_header = match data.status.as_str() {
        "firing" => format!("{}, {}", "warning", &data.status),
        "resolved" => format!("{}, {}", "white_check_mark", &data.status),
        _ => data.status.to_string(),
    };

    let req_client = client.post(NTFY_URL.clone());
    let req_client = match NTFY_BAUTH_PASS.clone().is_empty() {
        true => req_client,
        false => req_client.basic_auth(NTFY_BAUTH_USER.clone(), Some(NTFY_BAUTH_PASS.clone())),
    };

    let result = req_client
        .body(data.message.clone().unwrap_or_default())
        .header("X-Tags", &tags_header)
        .header("X-Title", &data.title)
        .header("X-Priority", &data.get_priority())
        .send()
        .await;

    // TODO: logging
    match result {
        Ok(_) => return Ok(json!({"status": 200})),
        Err(_) => return Err(Status::BadRequest),
    }
}

#[launch]
fn rocket() -> _ {
    dotenv::dotenv().ok();
    rocket::build().mount("/", routes![index, health]).manage(Client::new())
}
