% The measurements the README reports, against the standard's own examples.
%
% This is not a test: nothing here passes or fails. It prints the figures in
% the Measured section of ../README.md so that a reader can re-derive them
% instead of taking them on trust. Run it whenever the engine changes.
%
%   swipl -q -g measure_main -t halt test/measure.pl
%
% Like the rest of test/, it reads the extracted examples, so it runs only on
% a machine that holds a copy of the standard.
%
% The corpus has two halves and the suite guards only one of them:
%
%   ste       compliant by construction. An error on one is a false positive,
%             which test/engine_test.pl holds at zero.
%   non_ste   the sentences the standard itself prints as wrong. An error on
%             one is a true positive, and nothing holds it anywhere.
%
% Both halves are deduplicated with setof/3, because the same sentence is
% printed under more than one headword.

:- ensure_loaded('../ste/load.pl').
:- ensure_loaded('../dictionary/ste_examples.pl').

% The glossary the false-positive guard uses, for the same reason: the standard
% puts these two inside technical nouns under rule 1.6.
glossary_words([insert, main]).

compliant(Ts)     :- setof(T, W^P^ste_example(W, P, ste, T), Ts).
non_compliant(Ts) :- setof(T, W^P^ste_example(W, P, non_ste, T), Ts).

diags_of(Text, Ds) :-
    atom_codes(Text, Cs),
    findall(D, check(Cs, diag(D)), Ds).

errors_of(Text, Es) :-
    diags_of(Text, Ds),
    findall(E, ( member(E, Ds), E = diag(_, error, _, _, _) ), Es).

measure_main :-
    glossary_words(Ws),
    set_glossary(Ws),
    precision,
    nl, warning_noise,
    nl, sensitivity,
    nl, per_headword,
    nl, throughput.

% ---- precision -----------------------------------------------------------

precision :-
    compliant(Ts),
    length(Ts, N),
    findall(E, ( member(T, Ts), errors_of(T, Es), member(E, Es) ), All),
    length(All, NE),
    format("PRECISION~n"),
    format("  compliant sentences        ~w~n", [N]),
    format("  errors reported            ~w   (must be 0)~n", [NE]),
    ( All == [] -> true
    ; format("  the false positives:~n"),
      ( member(diag(R, _, _, F, _), All),
        format("    rule ~w  ~w~n", [R, F]),
        fail
      ; true )
    ).

% ---- warning noise on compliant text -------------------------------------

warning_noise :-
    compliant(Ts),
    length(Ts, N),
    findall(R, ( member(T, Ts), diags_of(T, Ds),
                 member(diag(R, warning, _, _, _), Ds) ), Rs),
    length(Rs, NW),
    findall(1, ( member(T, Ts), diags_of(T, Ds),
                 \+ member(diag(_, warning, _, _, _), Ds) ), Clean),
    length(Clean, NC),
    Per is NW / N,
    Pct is 100 * NC / N,
    format("WARNING NOISE, on the same compliant sentences~n"),
    format("  warnings                   ~w   (~2f to a sentence)~n", [NW, Per]),
    format("  sentences with none        ~w   (~2f%)~n", [NC, Pct]),
    msort(Rs, Sorted),
    tally(Sorted, Counts),
    format("  by rule                    ", []),
    ( member(Rule-K, Counts), format("~w:~w  ", [Rule, K]), fail ; nl ).

% ---- sensitivity ---------------------------------------------------------

sensitivity :-
    non_compliant(Ts),
    length(Ts, N),
    findall(1, ( member(T, Ts), errors_of(T, Es), Es \== [] ), WithError),
    length(WithError, NE),
    findall(1, ( member(T, Ts), diags_of(T, Ds), Ds \== [] ), WithAny),
    length(WithAny, NA),
    PE is 100 * NE / N,
    PA is 100 * NA / N,
    format("SENSITIVITY, on the sentences the standard prints as wrong~n"),
    format("  non-compliant sentences    ~w~n", [N]),
    format("  draw an error              ~w   (~2f%)  <- what the gate stops~n", [NE, PE]),
    format("  draw any diagnostic        ~w   (~2f%)~n", [NA, PA]).

% ---- per (headword, sentence) -------------------------------------------

% The standard names the word each non-compliant sentence is wrong about. This
% asks what the engine says about THAT word, rather than about the sentence,
% which is the stricter question: a diagnostic elsewhere in the sentence does
% not tell the writer what the standard objects to.
per_headword :-
    findall(W-T, ste_example(W, _, non_ste, T), P0),
    sort(P0, Pairs),
    length(Pairs, N),
    findall(S, ( member(W-T, Pairs), headword_severity(W, T, S) ), Ss),
    msort(Ss, Sorted),
    tally(Sorted, Counts),
    format("THE HEADWORD ITSELF, over (headword, sentence) pairs~n"),
    format("  pairs                      ~w~n", [N]),
    ( member(K-V, Counts),
      format("  ~w~t~27|~w~n", [K, V]),
      fail
    ; true ).

% error if any diagnostic on that word is one, warning if there is one at all,
% and missed when nothing lands on the word the standard named.
headword_severity(W, T, Sev) :-
    diags_of(T, Ds),
    findall(S, ( member(diag(_, S, _, F, _), Ds),
                 F =.. [_|Args],
                 member(A, Args),
                 atom(A),
                 surface_of(A, W) ), Ss),
    (   memberchk(error, Ss) -> Sev = error
    ;   Ss = [_|_]           -> Sev = warning
    ;                           Sev = missed
    ).

% A diagnostic carries the surface word, the corpus names the headword, and the
% two differ by inflection: "abates" against ABATE. A multi-word headword is
% matched on any of its words, since a diagnostic names one word at a time.
surface_of(A, W) :- lower(A, L), lower(W, LW), L == LW, !.
surface_of(A, W) :- lower(A, L), form_of(L, B, _), lower(W, LW), B == LW, !.
surface_of(A, W) :-
    lower(W, LW),
    atom_codes(LW, Cs),
    memberchk(0' , Cs),
    space_split(LW, Parts),
    lower(A, L),
    memberchk(L, Parts), !.

space_split(A, Parts) :- atom_codes(A, Cs), split_at_space(Cs, [], Parts).

split_at_space([], Acc, [W]) :- reverse(Acc, R), atom_codes(W, R).
split_at_space([0' |Cs], Acc, [W|Ws]) :-
    !, reverse(Acc, R), atom_codes(W, R), split_at_space(Cs, [], Ws).
split_at_space([C|Cs], Acc, Ws) :- split_at_space(Cs, [C|Acc], Ws).

% ---- throughput ----------------------------------------------------------

% Under SWI, which is the number the README compares the embedded machine
% against. The Scryer side is timed through the binary; see
% scripts/bench_throughput.sh.
throughput :-
    format("THROUGHPUT, this engine under SWI~n"),
    ( timed_file('USAGE.md') -> true ; true ),
    compliant(Ts),
    length(Ts, N),
    statistics(walltime, [T0|_]),
    findall(1, ( member(T, Ts), diags_of(T, _) ), _),
    statistics(walltime, [T1|_]),
    DT is T1 - T0,
    format("  ~w corpus sentences~t~27|~w ms~n", [N, DT]).

timed_file(File) :-
    read_file_codes(File, Cs),
    statistics(walltime, [T0|_]),
    findall(1, check(Cs, _), _),
    statistics(walltime, [T1|_]),
    DT is T1 - T0,
    format("  ~w~t~27|~w ms~n", [File, DT]).

% ---- helpers -------------------------------------------------------------

tally([], []).
tally([X|Xs], [X-N|Rest]) :-
    same_run(X, Xs, K, Tail),
    N is K + 1,
    tally(Tail, Rest).

same_run(X, [X|Xs], N, Tail) :- !, same_run(X, Xs, N0, Tail), N is N0 + 1.
same_run(_, Xs, 0, Xs).
