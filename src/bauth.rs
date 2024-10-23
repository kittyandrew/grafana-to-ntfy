use rocket::http::Status;
use rocket::request::{FromRequest, Outcome, Request};

#[derive(Debug)]
pub struct BAuth {
    pub user: String,
    pub pass: String,
}

// TODO: make this a proper error?
#[derive(Debug)]
pub enum BAuthError {
    Missing,
    Invalid,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for BAuth {
    type Error = BAuthError;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Authorization") {
            Some(data) => match data.strip_prefix("Basic ") {
                Some(raw) => match base64::decode(raw) {
                    Ok(v) => match String::from_utf8(v)
                        .unwrap_or(String::new())
                        .split_once(":")
                    {
                        Some((u, p)) => Outcome::Success(BAuth {
                            user: u.to_string(),
                            pass: p.to_string(),
                        }),
                        None => Outcome::Error((Status::BadRequest, BAuthError::Invalid)),
                    },
                    Err(_) => Outcome::Error((Status::BadRequest, BAuthError::Invalid)),
                },
                None => Outcome::Error((Status::BadRequest, BAuthError::Invalid)),
            },
            None => Outcome::Error((Status::BadRequest, BAuthError::Missing)),
        }
    }
}
