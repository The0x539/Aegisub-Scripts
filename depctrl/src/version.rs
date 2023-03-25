use std::{fmt::Display, str::FromStr};

use serde_with::{DeserializeFromStr, SerializeDisplay};
use thiserror::Error;

#[rustfmt::skip]
#[derive(Debug, Copy, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[derive(DeserializeFromStr, SerializeDisplay)]
pub struct Version {
    pub major: u8,
    pub minor: u8,
    pub patch: u8,
}

impl Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

impl Version {
    fn parse(s: &str) -> Option<Self> {
        let (major, rest) = s.split_once('.')?;
        let (minor, patch) = rest.split_once('.')?;
        Some(Self {
            major: major.parse().ok()?,
            minor: minor.parse().ok()?,
            patch: patch.parse().ok()?,
        })
    }
}

#[derive(Debug, Error)]
#[error("Could not parse `{0}` as version")]
pub struct VersionParseError(String);

impl FromStr for Version {
    type Err = VersionParseError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s).ok_or_else(|| VersionParseError(s.to_owned()))
    }
}
