use super::*;

use miette::{Diagnostic, IntoDiagnostic, NamedSource, Result, WrapErr};
use pretty_assertions::assert_eq;
use thiserror::Error;

#[derive(Debug, Error, Diagnostic)]
#[error("Failed to deserialize JSON")]
struct DeserializeError {
    #[source_code]
    json: NamedSource<String>,
    #[label("here")]
    at: usize,
    source: serde_json::Error,
}

impl DeserializeError {
    fn new(src: serde_json::Error, json: &str, name: &str) -> Self {
        Self {
            json: NamedSource::new(name, json.to_owned()).with_language("JSON"),
            at: get_offset(json, &src),
            source: src,
        }
    }
}

fn get_offset(json: &str, err: &serde_json::Error) -> usize {
    let mut line_offset = 0;
    for line in json.split_inclusive('\n').take(err.line() - 1) {
        line_offset += line.len();
    }
    line_offset + err.column().saturating_sub(1)
}

fn test_roundtrip(url: &str) -> Result<()> {
    let json = ureq::get(url)
        .send(std::io::empty())
        .into_diagnostic()
        .wrap_err("HTTP request failed")?
        .into_string()
        .into_diagnostic()
        .wrap_err("Failed to read HTTP response")?;

    let json = json.trim().trim_start_matches('\u{FEFF}');

    let de_err = |e| DeserializeError::new(e, &json, url);

    let val: serde_json::Value = serde_json::from_str(&json).map_err(de_err)?;
    let feed: Feed = serde_json::from_str(&json).map_err(de_err)?;

    let roundtrip = serde_json::to_value(feed).into_diagnostic()?;

    assert_eq!(val, roundtrip, "Round trip serialization did not match!");
    Ok(())
}

fn setup() {
    let _ = miette::set_hook(Box::new(|_| {
        Box::new(
            miette::MietteHandlerOpts::new()
                .context_lines(4)
                .rgb_colors(miette::RgbColors::Preferred)
                .build(),
        )
    }));
}

macro_rules! gen_tests {
    ($($author:ident @ $path:literal)*) => {
        $(
            #[test]
            fn $author() -> Result<()> {
                setup();

                let url = concat!(
                    "https://raw.githubusercontent.com/",
                    $path,
                    "/DependencyControl.json",
                );
                test_roundtrip(url)
            }
        )*
    };
}

gen_tests! {
    petzku     @ "petzku/Aegisub-Scripts/master"
    arch1t3cht @ "TypesettingTools/arch1t3cht-Aegisub-Scripts/main"
    phoscity   @ "PhosCity/Aegisub-Scripts/main"
    zeref      @ "TypesettingTools/zeref-Aegisub-Scripts/main"
    myaa       @ "TypesettingTools/Myaamori-Aegisub-Scripts/master"
    unanimated @ "TypesettingTools/unanimated-Aegisub-Scripts/master"
    lyger      @ "TypesettingTools/lyger-Aegisub-Scripts/master"
    line0      @ "TypesettingTools/line0-Aegisub-Scripts/master"
    coffeeflux @ "TypesettingTools/CoffeeFlux-Aegisub-Scripts/master"
}
