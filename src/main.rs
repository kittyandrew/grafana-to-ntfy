#[macro_use]
extern crate rocket;

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
    static ref NTFY_BAUTH_USER: String = var("NTFY_BAUTH_USER").unwrap_or_default();
    static ref NTFY_BAUTH_PASS: String = var("NTFY_BAUTH_PASS").unwrap_or_default();
    static ref BAUTH_USER: String = var("BAUTH_USER").unwrap_or_default();
    static ref BAUTH_PASS: String = var("BAUTH_PASS").unwrap_or_default();
    // NOTE(weriomat): Feature Flag for ['X-Action' Header](https://docs.ntfy.sh/publish/#action-buttons)
    static ref NTFY_ACTION_BUTTONS: String = var("NTFY_ACTION_BUTTONS").unwrap_or(String::from("true"));
}

#[get("/health")]
fn health() -> Value {
    // TODO: proper healthcheck.
    json!({"status": 200})
}

#[post("/", format = "application/json", data = "<data>")]
async fn index(
    data: Json<data::Notification>,
    bauth: bauth::BAuth,
    client: &State<Client>,
) -> Result<Value, Status> {
    if (bauth.user != *BAUTH_USER) | (bauth.pass != *BAUTH_PASS) {
        return Err(Status::Unauthorized);
    }

    // NOTE(weriomat): we send a message per alert not per "webhook sent"
    // NOTE(weriomat): this behaviour is consistent between alertmanager and grafana
    match &data.alerts {
        Some(al) => {
            for i in al {
                let req_client = client.post(NTFY_URL.clone());
                let req_client = match NTFY_BAUTH_PASS.clone().is_empty() {
                    true => req_client,
                    false => req_client
                        .basic_auth(NTFY_BAUTH_USER.clone(), Some(NTFY_BAUTH_PASS.clone())),
                };

                let actions = match NTFY_ACTION_BUTTONS.trim().parse() {
                    Ok(b) => match b {
                        true => i.get_action_header(),
                        false => "".to_string(),
                    },
                    Err(_) => "".to_string(),
                };

                match req_client
                    .body(i.get_body())
                    .header("X-Tags", i.get_tags())
                    .header("X-Title", i.get_name())
                    .header("X-Priority", i.get_priority())
                    .header("X-Actions", actions)
                    .send()
                    .await
                {
                    Ok(_) => {}
                    Err(_) => {
                        warn!("Could not send an ntfy alert");
                        return Err(Status::BadRequest);
                    }
                };
            }
            Ok(json!({"status":200}))
        }
        None => {
            warn!("Could not deserialze alerts");
            Err(Status::InternalServerError)
        }
    }
}

#[launch]
fn rocket() -> _ {
    dotenv::dotenv().ok();
    rocket::build()
        .mount("/", routes![index, health])
        .manage(Client::new())
}
