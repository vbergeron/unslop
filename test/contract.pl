% The embedding contract, tested against the engine alone -- exactly what a
% host loads. The wording now lives in the Rust host, so what is checked here
% is the shape of the answers, not their prose.
%
% One predicate per check, deliberately. Writing them as goals inside a single
% clause shares the variables between them: the first check bound the answer
% list, and every later check silently compared against that binding instead
% of its own file. Several of them passed vacuously.

:- ensure_loaded('../ste/load.pl').

files(['test/clean.md', 'test/sample.md', 'test/expected.md']).

answers(File, As) :-
    read_file_codes(File, Codes),
    findall(A, check(Codes, A), As).

:- dynamic(failure/0).

% A suite that prints FAIL must also exit non-zero, or a CI step passes while
% the tests fail -- the same defect as a pipeline that masks its exit code.
t(Label, Goal) :-
    (   catch(Goal, E, ( print_message(error, E), fail ))
    ->  format("ok    ~w~n", [Label])
    ;   format("FAIL  ~w~n", [Label]),
        ( failure -> true ; assertz(failure) )
    ).

finish :- ( failure -> halt(1) ; halt(0) ).

contract_main :-
    t('a clean document yields exactly one answer', clean_is_single),
    t('the last answer is always done(ok)',         terminated),
    t('exactly one terminator per run',             one_terminator),
    t('every earlier answer is a diag/1',           only_diags_before),
    t('every diagnostic has the documented shape',  shaped),
    t('diagnostics arrive in document order',       ordered_output),
    t('spans are byte offsets inside their line',   spans_fit),
    finish.

clean_is_single :-
    answers('test/clean.md', As),
    As == [done(ok)].

terminated :-
    files(Fs),
    forall(member(F, Fs),
           ( answers(F, As), append(_, [done(ok)], As) )).

one_terminator :-
    files(Fs),
    forall(member(F, Fs),
           ( answers(F, As),
             findall(x, member(done(_), As), Ds),
             length(Ds, 1) )).

only_diags_before :-
    files(Fs),
    forall(member(F, Fs),
           ( answers(F, As),
             append(Pre, [done(ok)], As),
             forall(member(A, Pre), A = diag(_)) )).

shaped :-
    files(Fs),
    forall(( member(F, Fs), answers(F, As), member(diag(D), As) ),
           ( D = diag(Rule, Sev, span(L, B, Len), Finding, Sugg),
             atom(Rule),
             memberchk(Sev, [error, warning]),
             integer(L), L >= 1,
             integer(B), B >= 0,
             integer(Len), Len >= 0,
             nonvar(Finding),
             is_list(Sugg) )).

ordered_output :-
    files(Fs),
    forall(member(F, Fs),
           ( answers(F, As),
             findall(L-B, member(diag(diag(_, _, span(L, B, _), _, _)), As), Ps),
             ordered(Ps) )).

ordered([]).
ordered([_]) :- !.
ordered([A, B|R]) :- A @=< B, ordered([B|R]).

spans_fit :-
    files(Fs),
    forall(( member(F, Fs), answers(F, As),
             member(diag(diag(_, _, span(L, B, Len), _, _)), As), Len > 0 ),
           ( line_bytes(F, L, NB), B + Len =< NB )).

line_bytes(File, N, NB) :-
    read_file_codes(File, Cs),
    split_lines(Cs, Ls),
    nth1_(N, Ls, Line),
    codes_bytes(Line, NB).
