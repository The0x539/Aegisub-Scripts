use std::{fmt::Display, str::FromStr};

use hex::FromHex;
use serde_with::{DeserializeFromStr, SerializeDisplay};

#[derive(Debug, Copy, Clone, Hash, PartialEq, Eq, DeserializeFromStr, SerializeDisplay)]
pub struct Sha1(pub [u8; 20], #[cfg(test)] bool);

impl Display for Sha1 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        #[cfg(test)]
        let is_upper = self.1;
        #[cfg(not(test))]
        let is_upper = true;

        let s = if is_upper {
            hex::encode_upper(&self.0)
        } else {
            hex::encode(&self.0)
        };
        f.write_str(&s)
    }
}

impl FromStr for Sha1 {
    type Err = hex::FromHexError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Self(
            FromHex::from_hex(s)?,
            #[cfg(test)]
            s.contains(|c: char| c.is_ascii_uppercase()),
        ))
    }
}
