# Test fixtures

`ste_dictionary.pl` here is **not** derived from ASD-STE100. It is a small,
hand-written stand-in that follows the fact schema `dictionary/README.md`
documents (`ste_word/4`, `ste_form/3`, `ste_alternative_text/3`, ...), just
enough of it to let `src/engine.rs`'s Rust tests build a whole engine --
`ste/markdown.pl` through `ste/engine.pl` -- without a licensed copy of the
standard.

It exists because of a defect that copy would otherwise hide: `Engine::new`
consults all eight engine files as one string, through
`scryer_prolog::Machine::consult_module_string`, which returns `()` and gives
the host no way to know whether the load actually completed. A directive
Scryer's loader cannot apply inside that string -- this project hit a bare
`:- discontiguous/1`, which the real dictionary carries -- silently truncates
everything after it, `ste/engine.pl` included, with nothing printed and
nothing returned. The only symptom is `existence_error` the next time
anything queries `check/3` or `check_file/2`, on whichever file happens to be
checked first, which reads as a problem with that file rather than with the
engine.

The fixture lets `engine.rs`'s tests assert two things without ASD's content:
that a well-formed load produces a working engine, and that a load Scryer
cannot finish is reported as a load failure at construction, not as a
mysterious existence_error later. See `Engine::verify_loaded` in
`src/engine.rs`.
