% Lookup layer over the generated dictionary facts.
%
% Without a part-of-speech tagger the checker must not guess which reading of
% an ambiguous word is meant, so the polarity here is deliberately permissive:
% a word passes if it is approved under ANY reading, and is reported only when
% every reading of it is forbidden. That yields no false positives from part-of
% speech ambiguity, at the cost of missing rule 1.2 violations such as "test"
% used as a verb. Those need the grammar, not the lexicon.

:- dynamic(glossary/1).

% ---- forms ---------------------------------------------------------------

% ste_form/3 holds the forms of verbs and adjectives, which are the ones rule
% 1.4 restricts. It holds no noun plurals, because the standard does not
% restrict them -- so `error` was approved and `errors` came back unknown, and
% ordinary technical prose filled with plural nouns produced a warning for
% almost every one of them.
%
% A regular plural of a word the dictionary lists as a noun reads as that noun.
% The test is deliberately narrow: the base must already be a noun entry, so a
% verb form cannot be reinterpreted this way.
form_of(Word, Base, POS) :- ste_form(Word, Base, POS).
form_of(Word, Base, n) :-
    \+ ste_form(Word, _, _),
    noun_plural(Word, Base),
    ste_word(Base, n, _, _).

% A glossary holds singular technical nouns, so the same plural rule applies
% to it. Without this, listing "rule" left "rules" reported.
in_glossary(Word) :- glossary(Word), !.
in_glossary(Word) :- noun_plural(Word, Base), glossary(Base), !.

noun_plural(Word, Base) :- drop_suffix(Word, ies, S), atom_concat(S, y, Base).
noun_plural(Word, Base) :- drop_suffix(Word, es, Base).
noun_plural(Word, Base) :- drop_suffix(Word, s, Base).

% A reading is a (base entry, part of speech) that the surface form belongs to.
approved_reading(Word, Base, POS) :-
    form_of(Word, Base, POS),
    ste_word(Base, POS, approved, _).

forbidden_reading(Word, Base, POS) :-
    form_of(Word, Base, POS),
    ste_word(Base, POS, not_approved, _).

% word_status(+LowercaseWord, -Status)
%   ok(approved(Base, POS))     approved under at least one reading
%   ok(glossary)                a project technical noun or verb, rule 1.8
%   replace(Base, POS, Alts)    every reading is forbidden, rules 1.1 and 1.6
%   unknown                     not in the dictionary and not in the glossary
word_status(Word, ok(approved(Base, POS))) :-
    approved_reading(Word, Base, POS), !.
word_status(Word, ok(glossary)) :-
    in_glossary(Word), !.
word_status(Word, replace(Base, POS, Alts)) :-
    forbidden_reading(Word, Base, POS), !,
    findall(A, ste_alternative_text(Base, POS, A), Raw),
    dedup(Raw, Alts).
word_status(_, unknown).

% The standard's advice for many words is "not as this part of speech, use the
% technical noun instead": cover (v) -> COVER (TN), fuel (v) -> FUEL (TN). Such
% a word is perfectly legal in its technical-noun reading, and technical nouns
% are by design absent from the dictionary, so no lookup can tell the readings
% apart. Deciding it needs the grammar; until then it cannot be a hard error.
technical_advice(Base, POS) :- ste_alternative(Base, POS, _, tn), !.
technical_advice(Base, POS) :- ste_alternative(Base, POS, _, tv), !.

% Rule 1.6 goes further: a word that is not approved may still appear when it
% is a technical noun or part of one, and technical nouns are absent from the
% dictionary by design. So "FUEL" in "the fuel pump" is legal even though
% "fuel (v)" is forbidden, and no lookup can tell the two apart.
%
% That leaves exactly one decidable subset: the standard's own list of the most
% frequent errors, minus the entries whose replacement is the same word in
% another part of speech (check (v) -> CHECK (n)) or a technical noun
% (cover (v) -> COVER (TN)). For what remains the replacement holds whatever
% the part of speech, because the word itself is simply not STE.
unconditional(Word, Replacement) :-
    ste_recurring_error(Word, _, Replacement),
    lower(Replacement, R),
    \+ sub_atom(R, _, _, _, '(tn)'),
    \+ sub_atom(R, _, _, _, '(tv)'),
    \+ same_word(Word, R).

same_word(Word, Replacement) :-
    ( sub_atom(Replacement, Before, _, _, ' (') -> true ; atom_length(Replacement, Before) ),
    sub_atom(Replacement, 0, Before, _, Head),
    Head == Word.

% Is any reading of this word approved at all? If none is, rule 1.6 leaves the
% technical-noun escape open and no part of speech can convict it.
approved_somewhere(Word) :- form_of(Word, Base, POS), ste_word(Base, POS, approved, _), !.

% Words the standard separates by sense alone, which no lookup can settle.
sense_dependent(Word) :- form_of(Word, Base, POS), ste_ambiguous(Base, POS).

% An approved verb whose inflection is not one of the permitted forms
% (rules 1.4 and 3.1). The closed lexicon is what makes this safe: the stem
% must already be an approved verb before the form is called wrong.
bad_inflection(Word, Base) :-
    \+ ste_form(Word, _, _),
    stem_of(Word, Base),
    ste_word(Base, v, approved, _).

stem_of(Word, Base) :-
    ( drop_suffix(Word, ing, Stem) ; drop_suffix(Word, ed, Stem) ),
    ( Base = Stem ; atom_concat(Stem, e, Base) ),
    ste_form(Base, Base, v).

drop_suffix(Word, Suffix, Stem) :-
    atom_length(Suffix, SL),
    atom_length(Word, WL),
    Keep is WL - SL,
    Keep > 2,
    sub_atom(Word, Keep, SL, 0, Suffix),
    sub_atom(Word, 0, Keep, _, Stem).

dedup([], []).
dedup([X|Xs], Out) :-
    (   memberchk(X, Xs) -> dedup(Xs, Out) ; Out = [X|Rest], dedup(Xs, Rest) ).

% ---- verb classes used by the grammar -----------------------------------

be_form(W)   :- memberchk(W, [am, is, are, was, were, be, been, being]).
have_form(W) :- memberchk(W, [have, has, had]).

ends_with(Word, Suffix) :-
    atom_length(Suffix, SL),
    atom_length(Word, WL),
    WL > SL,
    sub_atom(Word, _, SL, 0, Suffix).

ing_form(W) :-
    atom_length(W, L), L > 4,
    ends_with(W, ing),
    drop_suffix(W, ing, S),
    verb_stem(S).

% A past participle: an irregular form the dictionary lists, or an -ed/-en
% surface form whose stem is a verb the dictionary knows. The stem test is what
% stops "red" from parsing as a participle and "is missing" as the progressive:
% rule 3.5 permits an "-ing" word as a modifier, so the construction is only
% positive evidence when a real verb underlies it.
participle(W) :- ste_form(W, Base, v), W \== Base, !.
participle(W) :- ( drop_suffix(W, ed, S) ; drop_suffix(W, en, S) ), verb_stem(S), !.

verb_stem(S) :- ste_word(S, v, _, _), !.
verb_stem(S) :- atom_concat(S, e, B), ste_word(B, v, _, _), !.
verb_stem(S) :- atom_concat(S, y, B), ste_word(B, v, _, _), !.
