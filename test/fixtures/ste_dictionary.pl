% Synthetic test fixture -- NOT extracted from ASD-STE100. See README.md in
% this directory for why it exists. It supplies the schema
% `dictionary/README.md` documents, populated with invented words, just
% enough for src/engine.rs's Rust tests to load and run the real engine
% files (ste/markdown.pl through ste/engine.pl).

ste_form(a, a, art).
ste_word(a, art, approved, 1).
ste_form(the, the, art).
ste_word(the, art, approved, 1).

ste_form(hello, hello, n).
ste_word(hello, n, approved, 1).
ste_form(there, there, adv).
ste_word(there, adv, approved, 1).

ste_form(record, record, v).
ste_word(record, v, approved, 1).
ste_form(note, note, v).
ste_word(note, v, not_approved, 1).
ste_alternative_text(note, v, 'RECORD (v)').

% Placeholders so a lookup against these predicates fails cleanly rather than
% raising existence_error, matching what the real dictionary guarantees.
ste_ambiguous(placeholder, n) :- fail.
ste_note(placeholder, n, none) :- fail.
ste_alternative(placeholder, n, none, none) :- fail.
ste_tokens([placeholder], placeholder, n) :- fail.
ste_recurring_error(placeholder, n, none) :- fail.
