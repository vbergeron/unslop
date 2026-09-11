% The block structure, against test/blocks.md.
%
% This is the suite the corpus cannot be: every example the standard prints is
% one sentence on one line, so no multi-line block is ever built and a bare
% imperative is guessed descriptive. Every block-level defect the engine has
% had escaped the corpus guard and was found by running the gate over a real
% document. This fixture is the answer to that.
%
% Written to GitHub Flavored Markdown 0.29-gfm (2019-04-06). Each case names
% the construction it holds down.

:- ensure_loaded('../ste/load.pl').

:- dynamic(failure/0).

t(Label, Goal) :-
    (   catch(Goal, E, ( print_message(error, E), fail ))
    ->  format("ok    ~w~n", [Label])
    ;   format("FAIL  ~w~n", [Label]),
        ( failure -> true ; assertz(failure) )
    ).

finish :- ( failure -> halt(1) ; halt(0) ).

fixture(Blocks) :-
    read_file_codes('test/blocks.md', Cs),
    split_lines(Cs, Lines),
    findall(block(K, N, C), md_block(Lines, block(K, N, C)), Blocks).

% The kind and the first line of every block, in document order.
kinds(Pairs) :-
    fixture(Bs),
    findall(K-N, member(block(K, N, _), Bs), Pairs).

block_at(Line, Block) :-
    fixture(Bs),
    member(Block, Bs),
    Block = block(_, Line, _), !.

markdown_main :-
    t('the block stream is what the spec says it is', stream_is),
    t('a heading is one line and does not take the prose under it',
      block_at(1, block(heading, 1, [l(1, 2, _)]))),
    t('a paragraph keeps both of its lines',
      two_lines(3)),
    t('a setext underline turns its paragraph into a heading',
      block_at(6, block(heading, 6, _))),
    t('each bullet is a block of its own, so rule 6.6 cannot count them',
      block_at(10, block(item, 10, _))),
    t('a step wrapped at a column keeps its second line',
      two_lines(12)),
    t('a block quote takes its lazy continuation line',
      two_lines(16)),
    t('a backtick fence hides its content',   no_block_between(19, 21)),
    t('a tilde fence hides its content',      no_block_between(23, 25)),
    t('an indented code block hides its content', no_block_between(27, 27)),
    t('a thematic break yields no block',     no_block_between(29, 29)),
    t('a table needs its delimiter row',      table_rows_only),
    t('a pipe in prose is not a table',
      block_at(35, block(descriptive, 35, _))),
    t('a decimal number opening a line is not a step',
      block_at(37, block(descriptive, 37, _))),
    t('"Warnings" is not the safety keyword',
      block_at(39, block(descriptive, 39, _))),
    t('"WARNING:" is',
      block_at(41, block(safety, 41, _))),
    t('an ste marker forces the kind of the block after it',
      block_at(44, block(procedural, 44, _))),
    t('a task list checkbox is markup and not a word',
      block_at(46, block(item, 46, [l(46, 6, _)]))),
    t('a nested item keeps the byte offset of its source line',
      block_at(48, block(item, 48, [l(48, 4, _)]))),
    t('a link reference definition yields no block', no_block_between(50, 50)),
    t('an ordinary comment yields no block',        no_block_between(52, 52)),
    finish.

% The whole stream at once, so a change anywhere shows up here and not only in
% the case that covers it.
stream_is :-
    kinds(Pairs),
    % `table` is a prefix operator in SWI, for the tabling directive, so
    % `table-31` reads as table(-31) and the comparison fails against a pair
    % that is right. The parentheses are not decoration. It is the same trap
    % ../ste/README.md records for `dynamic` and `discontiguous`.
    Pairs == [heading-1, descriptive-3, heading-6, item-9, item-10,
              procedural-12, procedural-14, note-16, (table)-31, (table)-33,
              descriptive-35, descriptive-37, descriptive-39, safety-41,
              procedural-44, item-46, item-47, item-48].

two_lines(Line) :-
    block_at(Line, block(_, _, Content)),
    length(Content, 2).

no_block_between(From, To) :-
    fixture(Bs),
    \+ ( member(block(_, N, _), Bs), N >= From, N =< To ).

% Only the header row and the body row, never the delimiter row.
table_rows_only :-
    fixture(Bs),
    findall(N, member(block(table, N, _), Bs), Ns),
    Ns == [31, 33].
