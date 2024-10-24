use core::fmt;
use rocket::serde::Deserialize;
use std::{collections::HashMap, str::FromStr};

// NOTE(weriomat): Alertmanager (v. 0.27) - Headers ignored: version, groupKey, truncatedAlerts, status, receiver, groupLabels, commonLabels, commonAnnotations, externalURL
// NOTE(weriomat): Grafana (v. 10.4) - Headers ignored: receiver, status, orgId, alerts, groupLabels, commonLabels, commonAnnotation, externalURL, version, groupKey, truncatedAlerts, (title, state, message) will be deprecated soon
#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Notification {
    // // Note(andrew): 'message' field is not always present.
    // pub message: Option<String>,
    // pub status: String,
    // // NOTE(weriomat): prometheus alertmanager does not supply a title, therefore we set an arbitrary title of 'alertmanager'
    // #[serde(default = "title")]
    // pub title: String,
    // // TODO: make this a hashmap as well
    // #[serde(alias = "tags", alias = "commonLabels")]
    // pub labels: Option<Labels>,
    pub alerts: Option<Vec<Alerts>>,
}

// NOTE(weriomat): Alertmanager (v. 0.27) - Alerts ignored: startsAt, endsAt, fingerprint
// NOTE(weriomat): Grafana (v. 10.4) - Alerts ignored: startsAt, endsAt, values, fingerprint, (dashboardURL, panelURL) will be deprecated soon, imageURL
#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub struct Alerts {
    pub status: Status,
    // NOTE(weriomat): Since we can have arbirary key-value pairs we need to use a Hashmap
    pub labels: Option<HashMap<String, String>>,
    pub annotations: Option<HashMap<String, String>>,
    #[serde(rename = "generatorURL")]
    // NOTE(weriomat): The generatorURL 'header' is present in both Grafana and Alertmanager
    // (Grafana) URL of the alert rule in the Grafana UI, (Alertmanager) identifies the entity that caused the alert
    pub generatorurl: String,
    #[serde(rename = "silenceURL")]
    // NOTE(weriomat): this value is only presend in grafana
    pub silenceurl: Option<String>,
}

impl Alerts {
    pub fn get_name(&self) -> String {
        match &self.labels {
            // NOTE(weriomat): When creating a rule in alertmanager you need to set 'alert' Attribute which is basically a name, which will get transformed to the label 'alertname'
            Some(labels) => match labels.get("alertname") {
                Some(name) => name.to_owned(),
                // NOTE(weriomat): No name was found, falling back to default name of "NO NAME"
                None => "NO NAME".to_string(),
            },
            None => "NO NAME".to_string(),
        }
    }

    // NOTE(weriomat): Add direct weblink to ntfy-message
    pub fn get_action_header(&self) -> String {
        let actions = match &self.silenceurl {
            Some(silence) => format!(
                "action=view, Generator, {}; action=view, Silence, {}",
                self.generatorurl, silence
            ),
            None => format!("action=view, Generator, {}", self.generatorurl),
        };

        match &self.annotations {
            // NOTE(weriomat): Grafana lets you attach a runbook directly to the alert
            Some(annotations) => match annotations.get("runbook_url") {
                Some(runbook) => format!("{}; action=view, Runbook, {}", actions, runbook),
                None => actions,
            },
            None => actions,
        }
    }

    // NOTE(weriomat): Alertmanager: These seem to be common labels, at least they are all set in a collection of [alert rules](https://samber.github.io/awesome-prometheus-alerts/rules.html)
    // NOTE(weriomat): Grafana: The UI lets you set both of those headers
    pub fn get_body(&self) -> String {
        match &self.annotations {
            Some(annotations) => {
                let mut body = match annotations.get("summary") {
                    Some(summary) => match annotations.get("description") {
                        Some(description) => {
                            format!("Summary: {}\nDescription: {}", summary, description)
                        }
                        None => format!("Summary: {}", summary),
                    },
                    None => "".to_string(),
                };

                // Iterate over other annotations, remove
                for (key, val) in annotations.iter() {
                    if key == "runbook_url" || key == "description" || key == "summary" {
                        continue;
                    }
                    body = format!("{}\n{}: {}", body, key, val);
                }
                body
            }
            None => "".to_string(),
        }
    }

    pub fn get_tags(&self) -> String {
        let mut tags = self.status.to_string();

        match &self.labels {
            Some(labels) => {
                for (key, val) in labels.iter() {
                    tags = format!("{}, {}:{}", tags, key, val);
                }
                tags
            }
            None => tags,
        }
    }

    pub fn get_priority(&self) -> String {
        match &self.labels {
            Some(labels) => match labels.get("priority") {
                Some(priority) => priority.to_string(),
                None => match labels.get("severity") {
                    Some(severity) => match Severity::from_str(&severity) {
                        Ok(s) => s.to_string(),
                        Err(_) => {
                            warn!("Severity label <{}> could not be matched into <info|warning|critical>", severity);
                            "default".to_string()
                        }
                    },
                    None => "default".to_string(),
                },
            },
            None => "default".to_string(),
        }
    }
}

// NOTE(weriomat): [samber](https://samber.github.io/awesome-prometheus-alerts) uses the severity label instead of priority, appently there only the following severities
pub enum Severity {
    info,
    warning,
    critical,
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Severity::info => write!(f, "low"),
            Severity::warning => write!(f, "high"),
            Severity::critical => write!(f, "max"),
        }
    }
}

impl FromStr for Severity {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "info" => Ok(Severity::info),
            "warning" => Ok(Self::warning),
            "critical" => Ok(Self::critical),
            _ => Err(()),
        }
    }
}

// NOTE(weriomat): A simple wrapper arround the well defined 'Status' header
#[derive(Deserialize, Debug)]
#[serde(crate = "rocket::serde")]
pub enum Status {
    firing,
    resolved,
}

// Mapping grafana 'status'^1 to the ntfy.sh emojis^23, so we have proper
// warning emoji on the alertings state and so on..
//   ^1 - https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/webhook-notifier/
//   ^2 - https://ntfy.sh/docs/publish/#tags-emojis
//   ^3 - https://ntfy.sh/docs/emojis
//
impl fmt::Display for Status {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Status::firing => write!(f, "warning"),
            Status::resolved => write!(f, "white_check_mark"),
        }
    }
}
