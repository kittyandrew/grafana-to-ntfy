use reqwest::Client;
use rocket::http::Status;
use rocket::serde::json::{json, Json, Value};
use rocket::{get, launch, post, routes, State};
use sha2::{Digest, Sha256};
use std::env::var;
use std::sync::LazyLock;
use std::time::Duration;
use subtle::ConstantTimeEq;

mod bauth;
mod data;

static NTFY_URL: LazyLock<String> = LazyLock::new(|| var("NTFY_URL").unwrap_or_default());
static NTFY_BAUTH_USER: LazyLock<String> = LazyLock::new(|| var("NTFY_BAUTH_USER").unwrap_or_default());
static NTFY_BAUTH_PASS: LazyLock<String> = LazyLock::new(|| var("NTFY_BAUTH_PASS").unwrap_or_default());
static BAUTH_USER: LazyLock<String> = LazyLock::new(|| var("BAUTH_USER").unwrap_or_default());
static BAUTH_PASS: LazyLock<String> = LazyLock::new(|| var("BAUTH_PASS").unwrap_or_default());
// @NOTE: Pre-hashed credentials for constant-time comparison. Avoids re-hashing the static
//  server-side credentials on every request — only the incoming request credentials are hashed.
static BAUTH_USER_HASH: LazyLock<sha2::digest::Output<Sha256>> = LazyLock::new(|| Sha256::digest(BAUTH_USER.as_bytes()));
static BAUTH_PASS_HASH: LazyLock<sha2::digest::Output<Sha256>> = LazyLock::new(|| Sha256::digest(BAUTH_PASS.as_bytes()));
static MARKDOWN: LazyLock<String> = LazyLock::new(|| var("MARKDOWN").unwrap_or_default());

#[get("/health")]
fn health() -> Result<Value, Status> {
    if NTFY_URL.is_empty() {
        return Err(Status::ServiceUnavailable);
    }
    Ok(json!({"status": "ok"}))
}

#[post("/", format = "application/json", data = "<data>")]
async fn handle_alert(
    data: Json<data::Notification>,
    bauth: Option<bauth::BAuth>,
    client: &State<Client>,
) -> Result<Value, Status> {
    if NTFY_URL.is_empty() {
        return Err(Status::ServiceUnavailable);
    }

    // @NOTE: Auth is enforced if either credential is set (not both). This means partial
    //  config (e.g., only BAUTH_PASS) still requires auth — the missing credential matches
    //  against an empty string. The startup warning (below) catches this misconfiguration.
    let auth_configured = !BAUTH_USER.is_empty() || !BAUTH_PASS.is_empty();
    if auth_configured {
        let Some(ref b) = bauth else {
            return Err(Status::Unauthorized);
        };
        // @NOTE: Hash credentials to fixed-length values before constant-time comparison.
        //  Prevents leaking credential length (ct_eq short-circuits on length mismatch).
        //  Bitwise & (not &&) ensures both comparisons always execute, preventing timing
        //  leaks of which credential failed.
        let user_ok: bool = Sha256::digest(b.user.as_bytes()).ct_eq(&BAUTH_USER_HASH).into();
        let pass_ok: bool = Sha256::digest(b.pass.as_bytes()).ct_eq(&BAUTH_PASS_HASH).into();
        if !(user_ok & pass_ok) {
            return Err(Status::Unauthorized);
        }
    }

    // Mapping grafana 'status'^1 (or 'state'^2) to the ntfy.sh emojis^34, so we have proper
    // warning emoji on the alertings state and so on..
    //   ^1 - https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/webhook-notifier/
    //   ^2 - https://grafana.com/docs/grafana/latest/alerting/old-alerting/notifications/#webhook
    //   ^3 - https://ntfy.sh/docs/publish/#tags-emojis
    //   ^4 - https://ntfy.sh/docs/emojis
    //
    let tags_header = match data.status.as_str() {
        "alerting" | "firing" => format!("warning, {}", &data.status),
        "ok" | "resolved" => format!("white_check_mark, {}", &data.status),
        _ => data.status.to_string(),
    };

    let req_client = client.post(NTFY_URL.as_str());
    let req_client = if NTFY_BAUTH_USER.is_empty() && NTFY_BAUTH_PASS.is_empty() {
        req_client
    } else {
        req_client.basic_auth(NTFY_BAUTH_USER.as_str(), Some(NTFY_BAUTH_PASS.as_str()))
    };

    let mut req = req_client
        .body(data.message.clone().unwrap_or_default())
        .header("X-Tags", &tags_header)
        .header("X-Title", &data.title)
        .header("X-Priority", data.get_priority());
    if !MARKDOWN.is_empty() {
        req = req.header("X-Markdown", MARKDOWN.as_str());
    }
    let result = req.send().await;

    match result {
        Ok(resp) if resp.status().is_success() => Ok(json!({"status": "ok"})),
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            eprintln!("ntfy responded with status {status}: {body}");
            Err(Status::BadGateway)
        }
        Err(e) => {
            eprintln!("Failed to POST to NTFY_URL: {e}");
            Err(Status::BadGateway)
        }
    }
}

#[launch]
fn rocket() -> _ {
    dotenvy::dotenv().ok();

    // @WARNING: Missing NTFY_URL means the server can't forward alerts. It stays running but
    //  reports unhealthy (503 on /health) so container orchestrators can detect the problem.
    if NTFY_URL.is_empty() {
        eprintln!("Warning: NTFY_URL is not set — server will start but report unhealthy (503) and reject all alerts");
    }

    // @WARNING: Partial auth configuration is likely a mistake — warn loudly at startup.
    if BAUTH_USER.is_empty() != BAUTH_PASS.is_empty() {
        eprintln!("Warning: only one of BAUTH_USER/BAUTH_PASS is set — auth will be enforced but may be misconfigured");
    }
    if NTFY_BAUTH_USER.is_empty() != NTFY_BAUTH_PASS.is_empty() {
        eprintln!(
            "Warning: only one of NTFY_BAUTH_USER/NTFY_BAUTH_PASS is set — auth will be sent to ntfy but may be misconfigured"
        );
    }

    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("failed to build reqwest client");
    rocket::build().mount("/", routes![handle_alert, health]).manage(client)
}
