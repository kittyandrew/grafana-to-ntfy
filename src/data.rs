use rocket::serde::Deserialize;

#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Notification {
    // Note(andrew): 'message' field is not always present.
    pub message: Option<String>,
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
