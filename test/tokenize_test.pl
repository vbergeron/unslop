% The tokenizer, in isolation from the grammar and the lexicon: toks/4 and
% sentence_in/2 depend on neither, so every case here holds regardless of
% which lexicon is loaded, unlike engine_test.pl's false-positive guard.
%
% An inline markdown link used to convict its own syntax. Two defects
% combined to do it, and both get a suite here:
%
%   * `[text](target)` reached the tokenizer as bare characters, so the
%     target's own punctuation -- most often the period of a file extension
%     -- read as the end of a sentence.
%   * a period glued to the next character with no space, as in "BUILD.md",
%     ended a sentence anywhere it appeared, link or no link, which is why
%     README.md:106 ("BUILD.md and USAGE.md are written in...") convicted
%     itself with no markdown involved at all.

:- ensure_loaded('../ste/load.pl').

:- dynamic(failure/0).

t(Label, Goal) :-
    (   catch(Goal, E, ( print_message(error, E), fail ))
    ->  format("ok    ~w~n", [Label])
    ;   format("FAIL  ~w~n", [Label]),
        ( failure -> true ; assertz(failure) )
    ).

finish :- ( failure -> halt(1) ; halt(0) ).

toks_of(Text, Toks) :- atom_codes(Text, Cs), toks(Cs, 1, 0, Toks).

tokenize_main :-
    t('link text tokenizes as ordinary words',
      link_text_is_words),
    t('a link target is one opaque token, kind u',
      link_target_is_opaque),
    t('the byte offset after a link is exact',
      byte_offset_survives_link),
    t('a link target keeps one balanced parenthetical of its own',
      wiki_style_target),
    t('an empty link text yields no word token',
      empty_link_text),
    t('a stray bracket with no target falls back to punctuation',
      stray_bracket_is_punctuation),
    t('a bracket that never closes falls back to punctuation',
      unterminated_bracket_is_punctuation),
    t('a bracket followed by a space, not a paren, is not a link',
      bracketed_word_with_no_target),
    t('a period glued to the next word does not end a sentence',
      glued_period_does_not_split),
    t('a period followed by a space still ends a sentence',
      spaced_period_still_splits),
    t('"No. 105" still does not split, unaffected by the glued case',
      abbreviation_before_number_unaffected),
    t('the exact bug report is one sentence, not three',
      link_repro_is_one_sentence),
    finish.

% ---- the link itself ------------------------------------------------------

link_text_is_words :-
    toks_of('[the guide](docs/guide.md)', Toks),
    Toks = [t(w, the, _), t(w, guide, _), t(u, _, _)].

link_target_is_opaque :-
    toks_of('[the guide](docs/guide.md)', Toks),
    last(Toks, t(u, 'docs/guide.md', pos(1, _, _))).

% "See [the guide](docs/guide.md) for steps." -- "for" must sit exactly where
% the source puts it, or a diagnostic after the link points at the wrong
% column. Byte 31 is the 'f' of "for", counted in the source string by hand.
byte_offset_survives_link :-
    toks_of('See [the guide](docs/guide.md) for steps.', Toks),
    memberchk(t(w, for, pos(1, 31, 3)), Toks).

wiki_style_target :-
    toks_of('[this](https://en.wikipedia.org/wiki/Foo_(bar))', Toks),
    memberchk(t(u, 'https://en.wikipedia.org/wiki/Foo_(bar)', _), Toks).

empty_link_text :-
    toks_of('[](icon.png)', Toks),
    Toks = [t(u, 'icon.png', _)].

% ---- what must still fall back --------------------------------------------

stray_bracket_is_punctuation :-
    toks_of('note [1] here', Toks),
    memberchk(t(p, '[', _), Toks),
    memberchk(t(p, ']', _), Toks).

unterminated_bracket_is_punctuation :-
    toks_of('a [bracket that never closes', Toks),
    memberchk(t(p, '[', _), Toks),
    \+ memberchk(t(u, _, _), Toks).

bracketed_word_with_no_target :-
    toks_of('a [citation] with no target', Toks),
    memberchk(t(p, '[', _), Toks),
    memberchk(t(p, ']', _), Toks),
    \+ memberchk(t(u, _, _), Toks).

% ---- sentence boundaries ----------------------------------------------------

sentences_of(Text, Sentences) :-
    toks_of(Text, Toks),
    findall(S, sentence_in(Toks, S), Sentences).

glued_period_does_not_split :-
    sentences_of('BUILD.md covers it.', Sentences),
    length(Sentences, 1).

spaced_period_still_splits :-
    sentences_of('Do this. Then do that.', Sentences),
    length(Sentences, 2).

abbreviation_before_number_unaffected :-
    sentences_of('See No. 105 for the part.', Sentences),
    length(Sentences, 1).

% The whole reported input is one sentence up to the colon (rule 8.4), not
% three fragments split at "BUILD.", "md]", and "BUILD." again -- which is
% what let an ordinary word stand alone and be read as the sentence's verb.
link_repro_is_one_sentence :-
    sentences_of(
        '[BUILD.md](BUILD.md) covers it: obtaining the standard.',
        Sentences),
    length(Sentences, 2).       % up to the colon, then the trailing clause
