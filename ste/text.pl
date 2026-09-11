% The block generator for plain text, the counterpart to markdown.pl.
%
%   text_block(+Lines, -Block)  yields one block at a time, in document order,
%                               in the block(Kind, FirstLineNumber, Content)
%                               shape md_block/2 yields, so every layer above
%                               this one is unchanged.
%
% There is no grammar here, which is the point. A plain text file has no markup
% to interpret, so every line is prose exactly as written: `#` is a number
% sign and not a heading, `-` is a hyphen and not a bullet, and a backtick
% fence hides nothing. Anything markdown.pl would have read as structure is
% ordinary text to be checked.
%
% One division survives: a blank line. That is not markup but the way plain
% prose separates paragraphs, and the rules need it -- rule 6.6 counts the
% sentences in a paragraph, so a document held as a single block would report
% every file of more than six sentences.
%
% Every block is `descriptive`, prose whose vocabulary and whose length both
% count. Nothing in a text file can announce itself as a heading, a warning or
% a numbered step, so no other kind can arise here. An `ste:` marker is markup
% too, so it is text like the rest; markdown.pl is what honours it.

text_block(Lines, Block) :-
    number_text_lines(Lines, 1, Numbered),
    text_blocks(Numbered, Block).

% The byte offset is 0 for every line: there is no container marker to strip,
% so a token's offset is already the one in the source line.
number_text_lines([], _, []).
number_text_lines([L|Ls], N, [l(N, 0, L)|Rest]) :-
    N1 is N + 1,
    number_text_lines(Ls, N1, Rest).

% No clause for an empty list: nothing left yields no block, which is a failure
% and not an answer. That is md_block/2's contract and unit_diag/3 relies on it.
%
% md_blank/1 is the one predicate borrowed from markdown.pl, because "a line of
% nothing but whitespace" is not a markdown notion.
text_blocks([L|Ls], Block) :-
    (   L = l(_, _, Cs), md_blank(Cs)
    ->  text_blocks(Ls, Block)
    ;   text_para([L|Ls], Para, Rest),
        Para = [l(N, _, _)|_],
        (   Block = block(descriptive, N, Para)
        ;   text_blocks(Rest, Block)
        )
    ).

% text_para(+Lines, -Para, -Rest) takes the lines up to the next blank one.
text_para([], [], []).
text_para([l(N, B, Cs)|Ls], Para, Rest) :-
    (   md_blank(Cs)
    ->  Para = [], Rest = Ls
    ;   Para = [l(N, B, Cs)|More],
        text_para(Ls, More, Rest)
    ).
