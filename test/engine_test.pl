% What the engine finds, and what it must not.
%
% The test that matters is the false-positive guard. The standard's own STE
% examples are compliant by construction, so any error reported on them is a
% bug in the engine. They are fed straight to check/2 as codes rather than
% written to a file first, which also exercises the pure entry point.

:- ensure_loaded('../ste/load.pl').

% The example sentences are not part of the lexicon the binary embeds: no rule
% reads one. They are loaded here alone, for the guard below.
:- ensure_loaded('../dictionary/ste_examples.pl').

:- dynamic(failure/0).
:- dynamic(sensitivity/2).

% A suite that prints FAIL must also exit non-zero, or a CI step passes while
% the tests fail -- the same defect as a pipeline that masks its exit code.
t(Label, Goal) :-
    (   catch(Goal, E, ( print_message(error, E), fail ))
    ->  format("ok    ~w~n", [Label])
    ;   format("FAIL  ~w~n", [Label]),
        ( failure -> true ; assertz(failure) )
    ).

finish :- ( failure -> halt(1) ; halt(0) ).

errors_of(Codes, Errors) :-
    findall(D, ( check(Codes, diag(D)), D = diag(_, error, _, _, _) ), Errors).

file_errors(File, Errors) :-
    read_file_codes(File, Codes),
    errors_of(Codes, Errors).

% ---- the sensitivity floor ----------------------------------------------
%
% The corpus has two halves. The guard below holds the false-positive count at
% zero on the compliant half, and nothing held the true-positive count on the
% other, so a change could quietly halve what the gate stops and every test
% would still pass.
%
% A floor and not an equality: an improvement must not read as a failure. When
% the figure improves, raise the floor. It stood at 202 before the severity
% policy stopped excusing a position the grammar had committed to a verb.

sensitivity_floor(600).

non_ste_corpus(Ts) :- setof(T, W^P^ste_example(W, P, non_ste, T), Ts).

sensitivity_report :-
    non_ste_corpus(Ts),
    length(Ts, N),
    findall(1, ( member(T, Ts), atom_codes(T, Cs),
                 errors_of(Cs, Es), Es \== [] ), Hits),
    length(Hits, C),
    assertz(sensitivity(C, N)),
    Pct is 100 * C / N,
    format("      sensitivity: ~w of ~w non-compliant examples draw an error (~2f%)~n",
           [C, N, Pct]).

sensitivity_holds :-
    sensitivity(C, _),
    sensitivity_floor(Floor),
    C >= Floor.

engine_main :-
    % "insert" and "main" appear inside technical nouns ("push the insert
    % down", "the main landing gear doors"), which rule 1.6 permits; that is
    % what a glossary is for, so the guard supplies one.
    set_glossary([insert, main]),
    corpus_report,
    t('no errors on the standard''s own compliant STE', corpus_clean),
    sensitivity_report,
    t('the sensitivity floor holds',                    sensitivity_holds),
    t('sample.md reports 6 errors',       file_error_count('test/sample.md', 6)),
    t('expected.md reports 5 errors',     file_error_count('test/expected.md', 5)),
    t('clean.md reports none',            file_error_count('test/clean.md', 0)),
    t('sample.md fires 1.2, 5.4 and 8.1',
      fires('test/sample.md', ['1.2', '5.4', '8.1'])),
    t('expected.md fires 1.2, 3.2, 4.2, 6.3 and 8.1',
      fires('test/expected.md', ['1.2', '3.2', '4.2', '6.3', '8.1'])),
    t('the resolved reading convicts "Test" as a verb',
      finds('Test the system for leaks.', not_approved_as('Test', v))),
    t('and leaves "test" alone as a noun',
      \+ finds('Do the leak test of the system.', not_approved_as(_, _))),
    t('rule 2.1 sees a five-word noun',
      finds('Remove the horizontal cylinder pivot bearing housing.',
            multi_word_noun(5, 3, _))),
    t('every finding emitted is one the host knows', findings_known),
    finish.

corpus(Texts) :- setof(T, W^P^ste_example(W, P, ste, T), Texts).

corpus_report :-
    corpus(Ts),
    length(Ts, N),
    findall(E, ( member(T, Ts), atom_codes(T, Cs), errors_of(Cs, Es), member(E, Es) ), All),
    length(All, NE),
    format("      corpus: ~w of the standard's own STE examples, ~w error(s)~n", [N, NE]).

corpus_clean :-
    corpus(Ts),
    forall(member(T, Ts),
           ( atom_codes(T, Cs), errors_of(Cs, Es), Es == [] )).

file_error_count(File, N) :-
    file_errors(File, Es),
    length(Es, N).

fires(File, Rules) :-
    file_errors(File, Es),
    forall(member(R, Rules), memberchk(diag(R, error, _, _, _), Es)).

finds(Text, Finding) :-
    atom_codes(Text, Cs),
    check(Cs, diag(diag(_, _, _, Finding, _))), !.

% The host matches on the Finding functor, so a new one must be added on both
% sides. This asserts that nothing is emitted which is not on the list; the
% host reports the other direction at runtime, by refusing a term it does not
% know rather than dropping the diagnostic.
findings_known :-
    forall(( member(F, ['test/sample.md', 'test/expected.md']),
             read_file_codes(F, Cs),
             check(Cs, diag(diag(_, _, _, Finding, _))) ),
           ( functor(Finding, Name, Arity), known_finding(Name, Arity) )).

known_finding(sentence_too_long, 3).
known_finding(paragraph_too_long, 2).
known_finding(semicolon, 0).
known_finding(contraction, 1).
known_finding(not_approved_as, 2).
known_finding(never_approved, 1).
known_finding(undecidable_reading, 2).
known_finding(technical_noun_reading, 1).
known_finding(technical_noun_only, 2).
known_finding(not_in_dictionary, 1).
known_finding(unlisted_technical_noun, 1).
known_finding(forbidden_form, 2).
known_finding(verb_construction, 3).
known_finding(passive_voice, 2).
known_finding(multi_word_noun, 3).
known_finding(noun_used_as_verb, 1).
known_finding(condition_not_divided, 1).
known_finding(step_without_verb, 1).
known_finding(note_gives_instruction, 1).
