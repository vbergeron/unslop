//! Prints what Scryer says while loading the engine, which the library API
//! otherwise swallows. `cargo run --example loadcheck`.
use scryer_prolog::MachineBuilder;

const SOURCES: &[(&str, &str)] = &[
    ("tokenize.pl", include_str!("../ste/tokenize.pl")),
    (
        "ste_dictionary.pl",
        include_str!("../dictionary/ste_dictionary.pl"),
    ),
    ("lexicon.pl", include_str!("../ste/lexicon.pl")),
    ("grammar.pl", include_str!("../ste/grammar.pl")),
    ("rules.pl", include_str!("../ste/rules.pl")),
    ("engine.pl", include_str!("../ste/engine.pl")),
];

fn main() {
    for (name, src) in SOURCES {
        let mut m = MachineBuilder::default().build();
        let out = m.test_load_string(src);
        let text = String::from_utf8_lossy(&out);
        if text.trim().is_empty() {
            println!("ok    {name}");
        } else {
            println!("---- {name} ----");
            for line in text.lines().take(8) {
                println!("  {line}");
            }
        }
    }
}
