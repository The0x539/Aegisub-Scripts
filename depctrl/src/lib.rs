use std::borrow::Cow;

use chrono::naive::NaiveDate as Date;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

#[cfg(test)]
mod tests;

pub mod sha1;
pub mod version;

use sha1::Sha1;
use version::Version;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Feed<'a> {
    pub dependency_control_feed_format_version: Version,
    pub name: &'a str,
    pub description: &'a str,
    pub base_url: &'a str,
    pub file_base_url: &'a str,
    pub url: &'a str,
    pub maintainer: &'a str,
    #[serde(default, skip_serializing_if = "IndexMap::is_empty")]
    pub known_feeds: IndexMap<&'a str, &'a str>,
    pub macros: IndexMap<&'a str, Package<'a>>,
    #[serde(default, skip_serializing_if = "IndexMap::is_empty")]
    pub modules: IndexMap<&'a str, Package<'a>>,
}

#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Package<'a> {
    pub file_base_url: Option<&'a str>,
    pub url: &'a str,
    pub author: &'a str,
    pub name: &'a str,
    pub description: Cow<'a, str>,
    pub channels: IndexMap<&'a str, ReleaseChannel<'a>>,
    pub changelog: Option<IndexMap<Version, Vec<Cow<'a, str>>>>,
}

#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ReleaseChannel<'a> {
    pub version: Version,
    pub released: Date,
    pub default: bool,
    pub platforms: Option<Vec<&'a str>>,
    pub files: Vec<PackageFile<'a>>,
    pub required_modules: Option<Vec<Dependency<'a>>>,
    pub file_base_url: Option<&'a str>,
}

#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct PackageFile<'a> {
    pub name: &'a str,
    pub url: Option<&'a str>,
    pub platform: Option<&'a str>,
    pub delete: Option<bool>,
    pub sha1: Option<Sha1>,
}

#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Dependency<'a> {
    pub module_name: &'a str,
    pub name: Option<&'a str>,
    pub url: Option<&'a str>,
    pub version: Option<Version>,
    pub feed: Option<&'a str>,
    pub optional: Option<bool>,
}
