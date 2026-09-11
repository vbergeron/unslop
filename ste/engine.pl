% The ASD-STE100 engine. This is the whole of what a host embeds.
%
% The host owns the CLI, the rendering and the wording.
%
% ---- loading -------------------------------------------------------------
%
% This file carries NO load directives, because a host that embeds the engine
% consults it from a string and has no filesystem to resolve them against.
% The load order is the host's responsibility:
%
%   markdown.pl  tokenize.pl  ../dictionary/ste_dictionary.pl  lexicon.pl
%   grammar.pl  rules.pl  engine.pl
%
% ste/load.pl does exactly that for SWI, for development and for the tests.
%
% ---- interface -----------------------------------------------------------
%
%   set_glossary(+Words)      once, at startup. Words is a list of atoms, the
%                             project's technical nouns and verbs (rule 1.8).
%
%   check(+Codes, -Answer)    the pure entry: Codes is a list of character
%                             codes. Used by the tests.
%
%   check_file(+Path, -Answer) reads the file itself, through ISO open/3 and
%                             get_code/2. This is the entry a host uses: a
%                             query is a string, so putting a whole document
%                             through one means encoding it as a list of
%                             integers, and a path costs nothing.
%
% Both are nondeterministic and yield, in document order:
%   diag(Diagnostic)   one solution per finding
%   done(ok)           ALWAYS the last solution
%
% A diagnostic is
%
%   diag(Rule, Severity, span(Line, Byte, Len), Finding, Suggestions)
%
% with Line 1-based, Byte a 0-based byte offset within the line, and Len a
% byte length. See rules.pl for the Finding and Suggestion functors.
%
% ---- why the terminator ---------------------------------------------------
%
% In Prolog a query with no solutions is indistinguishable from one that
% failed for a bad reason -- a tokenizer that gave up, a rule clause that
% failed on an unbound variable. For a gate, "no errors" is precisely the
% verdict that lets a document through, so it must never be reachable by
% accident. The second branch of check/2 succeeds whatever happens to the
% first, which makes the host's contract:
%
%   the last answer is always done(_); if the answers run out without it,
%   the engine is broken, which is not the same as a clean document.
%
% A clean document therefore yields exactly one answer, done(ok).
%
% ---- what is not materialised --------------------------------------------
%
% Blocks come from a generator and sentences from a generator, so nothing
% spans the document. Only two bounded things are collected: the sentence list
% of one block, for the rules that count sentences, and the diagnostics of one
% sentence, to sort them. Global position order still holds because the
% generators run in document order.
%
% Exceptions are deliberately not caught, so the host sees them.

check_file(Path, Answer) :-
    read_file_codes(Path, Codes),
    check(Codes, Answer).

check(Codes, Answer) :-
    (   unit_diag(Codes, D),
        Answer = diag(D)
    ;   Answer = done(ok)
    ).

% A unit is a block, for the rules that count sentences, then each sentence.
unit_diag(Codes, D) :-
    split_lines(Codes, Lines),
    md_block(Lines, Block),
    Block = block(Kind, _, _),
    checked_kind(Kind),
    block_tokens(Block, Tokens),
    (   findall(S, sentence_in(Tokens, S), Sentences),
        block_diag(Kind, Block, Sentences, D)
    ;   sentence_in(Tokens, Sentence),
        Sentence = [_|_],
        sentence_report(Kind, Sentence, Ds),
        member(D, Ds)
    ).

% Sorting inside the sentence is enough for global order, because sentences
% arrive in document order. Two identical diagnostics share a line and a byte
% offset, so they come from the same sentence: per-sentence dedup is the same
% as global dedup.
sentence_report(Kind, S, Sorted) :-
    (   resolve(S, Resolved, _) -> true ; Resolved = [] ),
    findall(D, sentence_diag(Kind, S, Resolved, D), Ds),
    sort_diags(Ds, Sorted).

sort_diags(Diags, Sorted) :-
    findall(K-D,
            ( member(D, Diags),
              D = diag(Rule, _, span(L, B, _), _, _),
              K = k(L, B, Rule) ),
            Keyed),
    keysort(Keyed, KSorted),
    unkey(KSorted, WithDups),
    dedup_diags(WithDups, Sorted).

unkey([], []).
unkey([_-D|Rest], [D|Ds]) :- unkey(Rest, Ds).

dedup_diags([], []).
dedup_diags([D|Ds], Out) :-
    (   memberchk(D, Ds) -> dedup_diags(Ds, Out) ; Out = [D|Rest], dedup_diags(Ds, Rest) ).

% A heading counts as one word by rule 8.6, so length rules do not apply to
% it, but its vocabulary still does.
checked_kind(procedural).
checked_kind(descriptive).
% An item of a bullet list: prose, so its vocabulary and its length count, but
% it is not a paragraph, so rule 6.6 does not count its sentences.
checked_kind(item).
checked_kind(note).
checked_kind(safety).
checked_kind(heading).
% A table row: the vocabulary of its cells still counts, the length does not,
% because a cell is a label and rule 8.6 counts a label as one word.
checked_kind(table).

% ---- glossary ------------------------------------------------------------
%
% Asserted once, at startup, not per query: the single call to assertz/1 stays
% out of the hot path, which matters because a dynamic database is the least
% exercised part of a young implementation.

% \+ (Cond, \+ Action) rather than forall/2, which is not ISO. The asserts
% survive the negation: backtracking does not undo a database change.
set_glossary(Words) :-
    \+ ( member(W0, Words), lower(W0, W), \+ assert_glossary(W) ).

assert_glossary(W) :- ( glossary(W) -> true ; assertz(glossary(W)) ).
