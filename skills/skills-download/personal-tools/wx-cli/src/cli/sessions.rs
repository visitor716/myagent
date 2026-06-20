use anyhow::Result;
use crate::ipc::Request;
use super::transport;
use super::output::{resolve, print_value};

pub fn cmd_sessions(limit: usize, json: bool) -> Result<()> {
    let resp = transport::send(Request::Sessions { limit })?;
    let data = resp.data.get("sessions")
        .cloned()
        .unwrap_or(serde_json::Value::Array(vec![]));
    print_value(&data, &resolve(json))
}
