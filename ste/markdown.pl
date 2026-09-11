% Block structure, to GitHub Flavored Markdown 0.29-gfm (2019-04-06), which is
% a strict superset of CommonMark.
%
% Block kind decides which rules apply and which sentence limit holds, so
% getting the structure wrong is not a cosmetic matter: it moves the limit from
% 20 words to 25, applies section 5 to a paragraph, or hands prose to the
% checker as code. Every defect this file was written to remove came from
% guessing the structure a line was in from the line alone.
%
% ---- interface -----------------------------------------------------------
%
%   md_block(+Lines, -Block)   yields one block at a time, in document order.
%
%     Block = block(Kind, FirstLineNumber, Content)
%     Content = [l(LineNumber, Byte, Codes)]
%
% `Codes` is the CONTENT of the line, with the markers of its containers
% removed, and `Byte` is the 0-based byte offset in the original line at which
% that content begins. Content and offset travel together because a diagnostic
% points into the source: the host slices the line it read from disk, so a
% rewritten line would put the caret in the wrong place. This is also why the
% marker widths are measured here, where the container structure is known,
% instead of being guessed again from each line by the tokenizer.
%
% ---- kinds ---------------------------------------------------------------
%
%   descriptive  a paragraph. Rules 6.x, 25 words
%   procedural   an item of an ORDERED list, which is a step. Rules 5.x, 20
%   item         an item of a bullet list. Prose, so 25 words, but not a
%                paragraph, so rule 6.6 does not count its sentences
%   note         a block quote, at any depth. Rule 5.5
%   safety       a paragraph opening with the word WARNING or CAUTION
%   heading      an ATX or setext heading. One word by rule 8.6
%   table        a row of a GFM table. Its cells are labels, also one word
%   code         a fenced or an indented code block. Not checked
%
% An HTML comment `<!-- ste: procedural -->` forces the kind of the block that
% follows it, which is the escape for the cases below.
%
% ---- what is implemented -------------------------------------------------
%
% Leaf blocks: thematic breaks, ATX headings, setext headings, indented code
% blocks, fenced code blocks, paragraphs, blank lines, tables (the GFM
% extension), and link reference definitions. HTML blocks are recognised for
% comments and for a line that opens with a tag, which is what a document
% carries in practice.
%
% Container blocks: block quotes and list items, nested to any depth, with the
% laziness rule for paragraph continuation text. Task list items (the GFM
% extension) are list items whose checkbox is dropped.
%
% ---- what is not ---------------------------------------------------------
%
% Nothing here parses inlines. Emphasis, links, images, autolinks and raw HTML
% are the tokenizer's business, because their spans have to keep the byte
% offsets of the source; see ../ste/tokenize.pl.
%
% Tight and loose lists are not distinguished: it changes the rendering and not
% the text. The seven HTML block conditions are not each implemented. An
% ordered list that starts at a number other than 1 is a list all the same,
% since the start number changes the rendering only.

% ---- measurement ---------------------------------------------------------

% Leading whitespace of a line, in columns AND in bytes. Two counts because a
% tab is one byte but advances to the next four-column stop, and the structure
% is defined on columns while a span needs bytes.
line_indent(Cs, Cols, Bytes, Rest) :- indent_(Cs, 0, 0, Cols, Bytes, Rest).

indent_([C|Cs], C0, B0, Cols, Bytes, Rest) :-
    C =:= 0' ,
    !,
    C1 is C0 + 1, B1 is B0 + 1,
    indent_(Cs, C1, B1, Cols, Bytes, Rest).
indent_([C|Cs], C0, B0, Cols, Bytes, Rest) :-
    C =:= 0'\t,
    !,
    C1 is C0 + 4 - (C0 mod 4), B1 is B0 + 1,
    indent_(Cs, C1, B1, Cols, Bytes, Rest).
indent_(Cs, Cols, Bytes, Cols, Bytes, Cs).

% Drop up to N columns of leading whitespace, reporting the bytes dropped. Used
% to remove the content indent of a list item from its continuation lines.
drop_columns(Cs, N, Bytes, Rest) :- drop_cols_(Cs, N, 0, 0, Bytes, Rest).

drop_cols_(Cs, N, Cols, Bytes, Bytes, Cs) :- Cols >= N, !.
drop_cols_([C|Cs], N, C0, B0, Bytes, Rest) :-
    C =:= 0' ,
    !,
    C1 is C0 + 1, B1 is B0 + 1,
    drop_cols_(Cs, N, C1, B1, Bytes, Rest).
drop_cols_([C|Cs], N, C0, B0, Bytes, Rest) :-
    C =:= 0'\t,
    !,
    C1 is C0 + 4 - (C0 mod 4), B1 is B0 + 1,
    drop_cols_(Cs, N, C1, B1, Bytes, Rest).
drop_cols_(Cs, _, _, Bytes, Bytes, Cs).

md_blank(Cs) :- \+ ( member(C, Cs), \+ md_space(C) ).

md_space(0' ).
md_space(0'\t).

md_digit(C) :- C >= 0'0, C =< 0'9.

% ---- leaf block openers --------------------------------------------------

% A thematic break: 0-3 columns of indent, then three or more matching -, _ or
% *, with nothing but spaces and tabs among and after them.
thematic_break(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [C|_],
    break_char(C),
    break_run(Rest, C, 0, N),
    N >= 3.

break_char(0'-).
break_char(0'_).
break_char(0'*).

break_run([], _, N, N).
break_run([C|Cs], C, N0, N) :- !, N1 is N0 + 1, break_run(Cs, C, N1, N).
break_run([C|Cs], Ch, N0, N) :- md_space(C), !, break_run(Cs, Ch, N0, N).
break_run(_, _, _, -1).

% An ATX heading: 0-3 columns of indent, one to six #, then a space or the end
% of the line. The content offset is carried so a span points at the text and
% not at the marker.
atx_heading(Cs, Content, Byte) :-
    line_indent(Cs, Cols, B0, Rest),
    Cols =< 3,
    hash_run(Rest, 0, N, After),
    N >= 1, N =< 6,
    ( After == [] -> Content = [], Byte is B0 + N
    ; After = [C|_], md_space(C),
      line_indent(After, _, B1, Content0),
      Byte is B0 + N + B1,
      atx_close(Content0, Content)
    ).

hash_run([C|Cs], N0, N, After) :- C =:= 0'#, !, N1 is N0 + 1, hash_run(Cs, N1, N, After).
hash_run(Cs, N, N, Cs).

% An optional closing sequence of # preceded by a space. Dropped from the
% content, but its bytes are behind the text so no offset moves.
% Anchored at the end of the line, by reading it backwards: matching forwards
% finds the shortest content first, which strips the heading instead of its
% closing sequence.
atx_close(Cs, Content) :-
    (   reverse(Cs, Rs),
        skip_spaces(Rs, Rs1),
        hash_run(Rs1, 0, N, Rs2),
        N >= 1,
        Rs2 = [S|Rs3],
        md_space(S)
    ->  reverse(Rs3, Content)
    ;   Content = Cs
    ).

% A setext heading underline: = or - only, 0-3 columns of indent, any trailing
% spaces. It cannot open a block, only close a paragraph, so it is tested while
% a paragraph is being collected.
setext_underline(Cs, Level) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [C|_],
    ( C =:= 0'= -> Level = 1 ; C =:= 0'-, Level = 2 ),
    break_run(Rest, C, 0, N),
    N >= 1.

% A code fence: three or more backticks or tildes, 0-3 columns of indent. The
% info string of a backtick fence may hold no backtick.
fence_open(Cs, Char, Len, Indent) :-
    line_indent(Cs, Indent, _, Rest),
    Indent =< 3,
    Rest = [Char|_],
    ( Char =:= 0'` -> true ; Char =:= 0'~ ),
    fence_run(Rest, Char, 0, Len, Info),
    Len >= 3,
    ( Char =:= 0'` -> \+ member(0'`, Info) ; true ).

fence_run([C|Cs], C, N0, N, Info) :- !, N1 is N0 + 1, fence_run(Cs, C, N1, N, Info).
fence_run(Cs, _, N, N, Cs).

% A closing fence: the same character, at least as long, nothing after it but
% spaces.
fence_close(Cs, Char, OpenLen) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [Char|_],
    fence_run(Rest, Char, 0, Len, After),
    Len >= OpenLen,
    md_blank(After).

% An indented code block: four or more columns. It cannot interrupt a
% paragraph, which is why the caller tests it only where a block may open.
indented_code(Cs) :-
    \+ md_blank(Cs),
    line_indent(Cs, Cols, _, _),
    Cols >= 4.

% A block quote marker: 0-3 columns of indent, a >, and one optional space.
block_quote(Cs, Content, Byte) :-
    line_indent(Cs, Cols, B0, Rest),
    Cols =< 3,
    Rest = [C|After],
    C =:= 0'>,
    (   After = [S|Rest1], md_space(S)
    ->  Byte is B0 + 2, Content = Rest1
    ;   Byte is B0 + 1, Content = After
    ).

% A bullet list item: -, + or *, then one to four spaces of content indent.
% More than four means the content is an indented code block, and the content
% column is then the marker plus one.
bullet_item(Cs, Kind, Content, Byte, Column) :-
    line_indent(Cs, Cols, B0, Rest),
    Cols =< 3,
    Rest = [C|After],
    bullet_char(C),
    item_content(After, Cols, B0, 1, Content, Byte, Column),
    Kind = item.

bullet_char(0'-).
bullet_char(0'+).
bullet_char(0'*).

% An ordered list item: one to nine digits, then . or ), then the same content
% indent rule. The digit limit is the spec's, and it is also what stops a
% decimal number opening a line from reading as a step.
ordered_item(Cs, Kind, Content, Byte, Column) :-
    line_indent(Cs, Cols, B0, Rest),
    Cols =< 3,
    digit_run(Rest, 0, N, After0),
    N >= 1, N =< 9,
    After0 = [D|After],
    ( D =:= 0'. -> true ; D =:= 0') ),
    W is N + 1,
    item_content(After, Cols, B0, W, Content, Byte, Column),
    Kind = procedural.

digit_run([C|Cs], N0, N, After) :- md_digit(C), !, N1 is N0 + 1, digit_run(Cs, N1, N, After).
digit_run(Cs, N, N, Cs).

% The content of an item, and the column its continuation lines must reach.
% An item whose first line is blank takes a content column of the marker plus
% one, as does an item followed by more than four spaces.
item_content(After, Indent, B0, MarkerWidth, Content, Byte, Column) :-
    (   md_blank(After)
    ->  Column is Indent + MarkerWidth + 1,
        Byte is B0 + MarkerWidth,
        Content = []
    ;   line_indent(After, Spaces, SB, Rest),
        Spaces >= 1,
        (   Spaces =< 4
        ->  Column is Indent + MarkerWidth + Spaces,
            Byte is B0 + MarkerWidth + SB,
            Content = Rest
        ;   Column is Indent + MarkerWidth + 1,
            drop_columns(After, 1, DB, Content),
            Byte is B0 + MarkerWidth + DB
        )
    ).

% A task list item, the GFM extension: the checkbox is markup, not a word.
task_marker(Cs, Content, Byte) :-
    Cs = [0'[, S, 0']|After],
    ( S =:= 0'  -> true ; S =:= 0'x ; S =:= 0'X ),
    line_indent(After, _, B, Content),
    Byte is 3 + B.

% A link reference definition, which defines a label and prints nothing.
% Recognised only in its whole-line form, which is how a document writes it.
link_definition(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [0'[|After],
    append(Label, [Close, Colon|Tail], After),
    Close =:= 0'],
    Colon =:= 0':,
    Label = [_|_],
    \+ member(0'], Label),
    \+ md_blank(Tail).

% An HTML block. The two shapes a document carries: a comment, and a line that
% opens with a tag. The seven conditions of the spec are not each implemented.
html_comment_open(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    prefix_of([0'<, 0'!, 0'-, 0'-], Rest).

html_comment_close(Cs) :- append(_, [0'-, 0'-, 0'>|_], Cs).

html_block_open(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [0'<|After],
    ( After = [0'/|Name] -> true ; Name = After ),
    Name = [C|_],
    md_alpha(C).

md_alpha(C) :- C >= 0'a, C =< 0'z.
md_alpha(C) :- C >= 0'A, C =< 0'Z.

prefix_of([], _).
prefix_of([C|Cs], [C|Rest]) :- prefix_of(Cs, Rest).

% The kind marker, which overrides the guess for the block that follows.
kind_marker(Cs, Kind) :-
    atom_codes(A, Cs),
    sub_atom(A, B, _, _, 'ste:'),
    Skip is B + 4,
    sub_atom(A, Skip, _, 0, Tail),
    named_kind(Tail, Kind).

named_kind(Tail, Kind) :-
    member(Kind, [procedural, descriptive, item, note, safety, table]),
    sub_atom(Tail, _, _, _, Kind), !.

% ---- tables, the GFM extension -------------------------------------------

% A row of a table, in the form a document writes it.
table_row(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    Rest = [0'||_].

% The delimiter row, whose cells hold only hyphens with an optional leading or
% trailing colon. A header row is a table only when this row follows it, which
% is what stops any line carrying a pipe from being read as a table.
table_delimiter(Cs) :-
    line_indent(Cs, Cols, _, Rest),
    Cols =< 3,
    delimiter_cells(Rest, 0, N),
    N >= 1.

delimiter_cells([], N, N).
delimiter_cells([0'||Cs], N, Out) :- !, delimiter_cells(Cs, N, Out).
delimiter_cells([C|Cs], N0, Out) :-
    md_space(C), !,
    delimiter_cells(Cs, N0, Out).
delimiter_cells(Cs, N0, Out) :-
    delimiter_cell(Cs, Rest),
    N1 is N0 + 1,
    delimiter_cells(Rest, N1, Out).

delimiter_cell(Cs, Rest) :-
    (   Cs = [0':|Cs1] -> true ; Cs1 = Cs ),
    hyphen_run(Cs1, 0, N, Cs2),
    N >= 1,
    ( Cs2 = [0':|Cs3] -> true ; Cs3 = Cs2 ),
    skip_spaces(Cs3, Rest0),
    ( Rest0 = [0'||Rest] -> true ; Rest0 == [] , Rest = [] ).

hyphen_run([0'-|Cs], N0, N, Rest) :- !, N1 is N0 + 1, hyphen_run(Cs, N1, N, Rest).
hyphen_run(Cs, N, N, Cs).

skip_spaces([C|Cs], Rest) :- md_space(C), !, skip_spaces(Cs, Rest).
skip_spaces(Cs, Cs).

% ---- what may interrupt a paragraph --------------------------------------

% The spec's list, and the reason a paragraph cannot simply run to the next
% blank line. An indented code block is NOT here: it cannot interrupt a
% paragraph, so an indented line inside one is continuation text.
interrupts_paragraph(Cs) :- md_blank(Cs), !.
interrupts_paragraph(Cs) :- thematic_break(Cs), !.
interrupts_paragraph(Cs) :- atx_heading(Cs, _, _), !.
interrupts_paragraph(Cs) :- fence_open(Cs, _, _, _), !.
interrupts_paragraph(Cs) :- block_quote(Cs, _, _), !.
interrupts_paragraph(Cs) :- html_comment_open(Cs), !.
interrupts_paragraph(Cs) :- html_block_open(Cs), !.
interrupts_paragraph(Cs) :- bullet_item(Cs, _, C, _, _), \+ md_blank(C), !.
interrupts_paragraph(Cs) :- ordered_item(Cs, _, C, _, _), \+ md_blank(C), !.

% Any block opener at all, which is what ends the lazy continuation of a
% container.
opens_block(Cs) :- interrupts_paragraph(Cs), !.
opens_block(Cs) :- table_row(Cs), !.
opens_block(Cs) :- indented_code(Cs), !.

% ---- the generator -------------------------------------------------------

% md_block(+Lines, -Block) over the raw lines of a document, in order.
md_block(Lines, Block) :-
    number_md_lines(Lines, 1, Numbered),
    md_blocks(Numbered, none, descriptive, Block).

% No clause for an empty list: a document with nothing left in it yields no
% block, which is a failure and not an answer.

number_md_lines([], _, []).
number_md_lines([L|Ls], N, [l(N, 0, L)|Rest]) :-
    N1 is N + 1,
    number_md_lines(Ls, N1, Rest).

% md_blocks(+Lines, +Forced, +Container, -Block)
%
% Forced is the kind an `ste:` marker asked for, or `none`. Container is the
% kind a surrounding block quote or list item imposes on a paragraph, which is
% how a note keeps its kind at any depth.
md_blocks([l(N, B, Cs)|Rest], Forced, Container, Block) :-
    (   md_blank(Cs)
    ->  md_blocks(Rest, Forced, Container, Block)

    ;   html_comment_open(Cs)
    ->  comment_lines([l(N, B, Cs)|Rest], Text, After),
        (   kind_marker(Text, Kind)
        ->  md_blocks(After, Kind, Container, Block)
        ;   md_blocks(After, Forced, Container, Block)
        )

    ;   thematic_break(Cs)
    ->  md_blocks(Rest, Forced, Container, Block)

    ;   link_definition(Cs)
    ->  md_blocks(Rest, Forced, Container, Block)

    ;   fence_open(Cs, Char, Len, _)
    ->  skip_fence(Rest, Char, Len, After),
        md_blocks(After, Forced, Container, Block)

    ;   atx_heading(Cs, Content, Byte)
    ->  Byte1 is B + Byte,
        emit(block(heading, N, [l(N, Byte1, Content)]), Rest, Forced, Container, Block)

    ;   html_block_open(Cs)
    ->  skip_html(Rest, After),
        md_blocks(After, Forced, Container, Block)

    ;   block_quote(Cs, Content, Byte)
    ->  Byte1 is B + Byte,
        quote_lines(Rest, [l(N, Byte1, Content)], Inner, After),
        (   md_blocks(Inner, none, note, Block)
        ;   md_blocks(After, Forced, Container, Block)
        )

    ;   list_item(Cs, Kind, Content, Byte, Column)
    ->  Byte1 is B + Byte,
        item_lines(Rest, Column, [l(N, Byte1, Content)], Inner, After),
        (   md_blocks(Inner, Forced, Kind, Block)
        ;   md_blocks(After, none, Container, Block)
        )

    ;   indented_code(Cs)
    ->  skip_indented(Rest, After),
        md_blocks(After, Forced, Container, Block)

    ;   table_start([l(N, B, Cs)|Rest], Rows, After)
    ->  (   member(Row, Rows),
            Row = l(RowLine, _, _),
            Block = block(table, RowLine, [Row])
        ;   md_blocks(After, Forced, Container, Block)
        )

    ;   paragraph([l(N, B, Cs)|Rest], Lines, Ending, After),
        (   Ending = setext(_)
        ->  emit(block(heading, N, Lines), After, Forced, Container, Block)
        ;   paragraph_kind(Lines, Container, Kind),
            emit(block(Kind, N, Lines), After, Forced, Container, Block)
        )
    ).

% A block, then the rest. The forced kind applies to this block only.
emit(block(Kind0, N, Lines), Rest, Forced, Container, Block) :-
    ( Forced == none -> Kind = Kind0 ; Kind = Forced ),
    (   Block = block(Kind, N, Lines)
    ;   md_blocks(Rest, none, Container, Block)
    ).

list_item(Cs, Kind, Content, Byte, Column) :-
    (   ordered_item(Cs, Kind, Content0, Byte0, Column)
    ->  true
    ;   bullet_item(Cs, Kind, Content0, Byte0, Column)
    ),
    % A task list checkbox is markup. Dropping it here keeps rule 5.3 honest:
    % the step opens with its verb and not with a bracket.
    (   task_marker(Content0, Content, TB)
    ->  Byte is Byte0 + TB
    ;   Content = Content0, Byte = Byte0
    ).

% A paragraph inside a block quote is a note. A paragraph that opens with the
% word WARNING or CAUTION is a safety block; the keyword has to end at a word
% boundary, or a paragraph opening "Warnings are hidden" takes the safety
% limit.
paragraph_kind(_, note, note) :- !.
paragraph_kind([l(_, _, Cs)|_], _, safety) :-
    line_indent(Cs, _, _, Rest),
    atom_codes(A, Rest),
    md_lower(A, D),
    ( safety_keyword(D, warning) ; safety_keyword(D, caution) ), !.
paragraph_kind(_, item, item) :- !.
paragraph_kind(_, procedural, procedural) :- !.
paragraph_kind(_, _, descriptive).

safety_keyword(Line, Word) :-
    atom_length(Word, N),
    sub_atom(Line, 0, N, After, Word),
    (   After =:= 0
    ->  true
    ;   sub_atom(Line, N, 1, _, Next),
        atom_codes(Next, [Code]),
        \+ md_alpha(Code)
    ).

md_lower(A, Lower) :- atom_codes(A, Cs), md_lower_codes(Cs, Ls), atom_codes(Lower, Ls).

md_lower_codes([], []).
md_lower_codes([C|Cs], [L|Ls]) :-
    ( C >= 0'A, C =< 0'Z -> L is C + 32 ; L = C ),
    md_lower_codes(Cs, Ls).

% ---- collecting ----------------------------------------------------------

% A paragraph runs to a blank line, to a line that may interrupt it, or to a
% setext underline, which turns what was collected into a heading.
paragraph([l(N, B, Cs)|Rest], [l(N, B, Cs)|Lines], Ending, After) :-
    paragraph_rest(Rest, Lines, Ending, After).

paragraph_rest([], [], end, []).
paragraph_rest([l(N, B, Cs)|Rest], Lines, Ending, After) :-
    (   setext_underline(Cs, Level)
    ->  Lines = [], Ending = setext(Level), After = Rest
    ;   interrupts_paragraph(Cs)
    ->  Lines = [], Ending = end, After = [l(N, B, Cs)|Rest]
    ;   Lines = [l(N, B, Cs)|More],
        paragraph_rest(Rest, More, Ending, After)
    ).

% The lines of a block quote: every line carrying a marker, plus the lazy
% continuation lines, which are the lines that would be paragraph continuation
% text. A blank line ends it.
quote_lines([], Acc, Acc, []).
quote_lines([l(N, B, Cs)|Rest], Acc, Inner, After) :-
    (   block_quote(Cs, Content, Byte)
    ->  Byte1 is B + Byte,
        append(Acc, [l(N, Byte1, Content)], Acc1),
        quote_lines(Rest, Acc1, Inner, After)
    ;   md_blank(Cs)
    ->  Inner = Acc, After = Rest
    ;   opens_block(Cs)
    ->  Inner = Acc, After = [l(N, B, Cs)|Rest]
    ;   append(Acc, [l(N, B, Cs)], Acc1),          % lazy continuation
        quote_lines(Rest, Acc1, Inner, After)
    ).

% The lines of a list item: the lines indented to its content column, the blank
% lines inside it, and the lazy continuation lines. This is what keeps a step
% wrapped at a column whole, and its word count with it.
item_lines([], _, Acc, Acc, []).
item_lines([l(N, B, Cs)|Rest], Column, Acc, Inner, After) :-
    (   md_blank(Cs)
    ->  (   item_continues(Rest, Column)
        ->  append(Acc, [l(N, B, Cs)], Acc1),
            item_lines(Rest, Column, Acc1, Inner, After)
        ;   Inner = Acc, After = Rest
        )
    ;   line_indent(Cs, Cols, _, _), Cols >= Column
    ->  drop_columns(Cs, Column, DB, Content),
        Byte1 is B + DB,
        append(Acc, [l(N, Byte1, Content)], Acc1),
        item_lines(Rest, Column, Acc1, Inner, After)
    ;   opens_block(Cs)
    ->  Inner = Acc, After = [l(N, B, Cs)|Rest]
    ;   append(Acc, [l(N, B, Cs)], Acc1),          % lazy continuation
        item_lines(Rest, Column, Acc1, Inner, After)
    ).

% Does the item go on after a blank line? Only if the next non-blank line is
% indented to the content column.
item_continues([], _) :- !, fail.
item_continues([l(_, _, Cs)|Rest], Column) :-
    (   md_blank(Cs)
    ->  item_continues(Rest, Column)
    ;   line_indent(Cs, Cols, _, _),
        Cols >= Column
    ).

% A fenced code block runs to its closing fence, or to the end of the
% document, and nothing inside it is checked.
skip_fence([], _, _, []).
skip_fence([l(_, _, Cs)|Rest], Char, Len, After) :-
    ( fence_close(Cs, Char, Len) -> After = Rest ; skip_fence(Rest, Char, Len, After) ).

% An indented code block runs while the lines are indented or blank.
skip_indented([], []).
skip_indented([l(N, B, Cs)|Rest], After) :-
    (   md_blank(Cs)
    ->  ( indented_after_blank(Rest) -> skip_indented(Rest, After)
        ; After = Rest )
    ;   indented_code(Cs)
    ->  skip_indented(Rest, After)
    ;   After = [l(N, B, Cs)|Rest]
    ).

indented_after_blank([]) :- !, fail.
indented_after_blank([l(_, _, Cs)|Rest]) :-
    ( md_blank(Cs) -> indented_after_blank(Rest) ; indented_code(Cs) ).

% An HTML block runs to a blank line.
skip_html([], []).
skip_html([l(_, _, Cs)|Rest], After) :-
    ( md_blank(Cs) -> After = Rest ; skip_html(Rest, After) ).

% A comment runs to its close, and its text is joined so the kind marker can be
% read out of it.
comment_lines([], [], []).
comment_lines([l(_, _, Cs)|Rest], Text, After) :-
    (   html_comment_close(Cs)
    ->  Text = Cs, After = Rest
    ;   comment_lines(Rest, More, After),
        append(Cs, More, Text)
    ).

% A table is a header row, a delimiter row, then the rows that follow. Without
% the delimiter row it is not a table, which is what stops a line of prose
% carrying a pipe from becoming one.
table_start([l(N, B, Cs), l(_, _, Cs2)|Rest], [l(N, B, Cs)|Rows], After) :-
    table_row(Cs),
    table_delimiter(Cs2),
    table_rows(Rest, Rows, After).

table_rows([], [], []).
table_rows([l(N, B, Cs)|Rest], Rows, After) :-
    (   table_row(Cs)
    ->  Rows = [l(N, B, Cs)|More],
        table_rows(Rest, More, After)
    ;   Rows = [], After = [l(N, B, Cs)|Rest]
    ).
