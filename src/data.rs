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
    #[serde(alias = "dashboardId")]
    pub dashboard_id: u64,
    #[serde(alias = "evalMatches")]
    pub eval_matches: Vec<Match>,
    // Note(andrew): 'message' field is not always present.
    pub message: Option<String>,
    #[serde(alias = "orgId")]
    pub org_id: u64,
    #[serde(alias = "panelId")]
    pub panel_id: u64,
    #[serde(alias = "ruleId")]
    pub rule_id: u64,
    #[serde(alias = "ruleName")]
    pub rule_name: String,
    #[serde(alias = "ruleUrl")]
    pub rule_url: String,
    pub state: String,
    // TODO: Document type properly.
    pub tags: Value,
    pub title: String,
}

