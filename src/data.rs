use rocket::serde::{Deserialize, Deserializer};

#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Notification {
    // NOTE(andrew): 'message' field is not always present.
    pub message: Option<String>,
    #[serde(deserialize_with = "deserialize_status", flatten)]
    pub status: String,
    // NOTE(weriomat): prometheus alertmanager does not supply a title, therefore we set an arbitrary title of 'alertmanager'
    #[serde(default = "title")]
    pub title: String,
    #[serde(alias = "tags", alias = "commonLabels")]
    pub labels: Option<Labels>,
}

/// Default implementation of the Title, used for alertmanager
fn title() -> String {
    "Alertmanager".to_owned()
}

#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct StatusOptions<'a> {
    state: Option<&'a str>, // Is getting deprecated.
    status: Option<&'a str>,
}

fn deserialize_status<'d, D: Deserializer<'d>>(d: D) -> Result<String, D::Error> {
    let StatusOptions { state, status } = StatusOptions::deserialize(d)?;
    // 'Unknown' should never happen unless everything broke.
    Ok(state
        .or(status)
        .map(Into::into)
        .unwrap_or("unknown".to_string()))
}

#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Labels {
    pub priority: Option<String>,
}

impl Notification {
    pub fn get_priority(&self) -> String {
        self.labels
            .as_ref()
            .and_then(|labels| labels.priority.as_ref())
            .cloned()
            .unwrap_or_else(|| "default".to_string())
    }
}
