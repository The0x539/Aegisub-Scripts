use super::*;

use miette::{Diagnostic, IntoDiagnostic, NamedSource, Result, SourceOffset, SourceSpan, WrapErr};
use pretty_assertions::assert_eq;
use thiserror::Error;

macro_rules! gen_tests {
    ($($author:ident @ $path:literal)*) => {
        $(
            #[test]
            fn $author() -> Result<()> {
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

fn test_roundtrip(url: &str) -> Result<()> {
    setup();

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

#[derive(Debug, Error, Diagnostic)]
#[error("Failed to deserialize JSON")]
struct DeserializeError {
    #[source_code]
    json: NamedSource<String>,
    #[label("here")]
    at: SourceSpan,
    source: serde_json::Error,
}

impl DeserializeError {
    fn new(source: serde_json::Error, json: &str, name: &str) -> Self {
        let source_offset = SourceOffset::from_location(json, source.line(), source.column());

        let mut at = source_offset.into();
        if source.is_data() {
            if let Some(span) = span_from_offset(json, source_offset.offset()) {
                at = span;
            }
        }

        let json = NamedSource::new(name, json.to_owned()).with_language("JSON");
        Self { json, at, source }
    }
}

fn span_from_offset(json: &str, offset: usize) -> Option<SourceSpan> {
    let root: json_spanned_value::spanned::Value = json_spanned_value::from_str(json).ok()?;

    let mut stack = vec![&root];
    let mut ranges = vec![];

    // depth-first search for all values whose span includes `offset`
    while let Some(val) = stack.pop() {
        if !val.range().contains(&offset) {
            continue;
        }

        ranges.push(val.range());

        if let Some(arr) = val.as_array() {
            stack.extend(arr);
        } else if let Some(obj) = val.as_object() {
            for key in obj.keys() {
                if key.range().contains(&offset) {
                    return Some(key.range().into());
                }
            }
            stack.extend(obj.values());
        }
    }

    // return the last found value, i.e., the deepest and smallest span
    ranges.last().map(|r| r.clone().into())
}
