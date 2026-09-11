//! The lexicon has to exist before the crate can compile: src/engine.rs pulls
//! it in with include_str!. This turns the confusing rustc error that would
//! otherwise appear into the instructions a rights-holder needs.

use std::path::Path;

const LEXICON: &str = "dictionary/ste_dictionary.pl";

fn main() {
    println!("cargo:rerun-if-changed={LEXICON}");
    println!("cargo:rerun-if-changed=ste");

    if Path::new(LEXICON).exists() {
        return;
    }

    // Deliberately a panic and not a cargo:warning: a build that silently
    // produced a binary without a lexicon would be a gate that passes
    // everything, which is worse than no binary at all.
    panic!(
        "\n\n  {LEXICON} is missing, so there is nothing to check against.\n\n\
         This repository does not carry ASD-STE100 or anything extracted from\n\
         it. To build:\n\n\
         \x20   1. Request your copy of Issue 9 from the form at\n\
         \x20      https://www.asd-ste100.org/STE_downloads.html\n\
         \x20   2. Save it as ASD-STE100_ISSUE9.pdf in the repository root\n\
         \x20   3. python3 scripts/extract_dictionary.py\n\n\
         See the Getting the standard section of README.md for why it works\n\
         this way.\n"
    );
}
