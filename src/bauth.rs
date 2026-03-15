use base64::Engine;
use rocket::http::Status;
use rocket::request::{FromRequest, Outcome, Request};

#[derive(Debug)]
pub struct BAuth {
    pub user: String,
    pub pass: String,
}

#[derive(Debug)]
pub enum BAuthError {
    Invalid,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for BAuth {
    type Error = BAuthError;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        let Some(data) = req.headers().get_one("Authorization") else {
            return Outcome::Forward(Status::Unauthorized);
        };
        // @NOTE: Non-Basic auth schemes are not supported — forward rather than error,
        //  since the header is well-formed, just not applicable to this guard.
        let Some(raw) = data.strip_prefix("Basic ") else {
            return Outcome::Forward(Status::Unauthorized);
        };
        let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(raw) else {
            return Outcome::Error((Status::BadRequest, BAuthError::Invalid));
        };
        let Ok(credentials) = String::from_utf8(decoded) else {
            return Outcome::Error((Status::BadRequest, BAuthError::Invalid));
        };
        let Some((u, p)) = credentials.split_once(":") else {
            return Outcome::Error((Status::BadRequest, BAuthError::Invalid));
        };
        Outcome::Success(BAuth {
            user: u.to_string(),
            pass: p.to_string(),
        })
    }
}
