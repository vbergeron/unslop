% Tokenizer and block segmentation for ASD-STE100 checking.
%
% Shaped after the Attempto Parsing Engine: a tokenizer front end that hands
% the grammar a clean token list, with source positions kept on every token so
% a diagnostic can point at a span.
%
% A token is  t(Kind, Value, pos(Line, Byte, Len))  where Kind is one of
%   w  a word: letters, with internal hyphens and apostrophes kept, so that
%      rule 8.7 (a hyphenated word counts as one word) falls out for free
%   n  a number, decimal point included
%   c  an inline code span, `like this`
%   u  a URL
%   q  a quoted run, "like this", one token by rule 8.6
%   p  a punctuation character, Value is the character as an atom
%
% A position is  pos(Line, Byte, Len)
%   Line  1-based line number
%   Byte  0-BASED byte offset within the line
%   Len   byte length of the token's source text, delimiters included
%
% Byte, not character column: the consumer slices the line in Rust, and the
% corpus really does contain multi-byte characters -- typographic quotes, a
% degree sign, a micro sign -- so a character column would put a caret in the
% wrong place on exactly those lines. A character column is recoverable from
% the byte offset and the line text, so it is not carried here. The offset is
% 0-based because slicing is its purpose; anything that prints a column for a
% person adds one.
%
% Blocks carry the kind that decides which rules apply and which sentence
% limit holds:
%   procedural   rules 5.x, 20 words   (an ordered list item)
%   descriptive  rules 6.x, 25 words   (a paragraph)
%   note         rule 5.5              (a blockquote)
%   safety       rules 7.x             (a WARNING or CAUTION line)
%   heading      counts as one word by rule 8.6, so it is not length-checked
%   table        a row of a markdown table: its cells are labels, which rule
%                8.6 also counts as one word each, so no length limit applies
%   code         skipped entirely
%
% An explicit marker overrides the guess:  <!-- ste: procedural -->

:- discontiguous(alpha/1).

apostrophe(39).
apostrophe(8217).          % the typographic apostrophe the PDF uses
backtick(96).
dquote(34).
dquote(8220).              % typographic quotes, opening
dquote(8221).              % and closing

% The closing delimiter for a run that opens with C.
closer(8220, 8221) :- !.
closer(C, C).

alpha(C) :- C >= 0'a, C =< 0'z.
alpha(C) :- C >= 0'A, C =< 0'Z.
digit(C) :- C >= 0'0, C =< 0'9.

wordchar(C) :- alpha(C).
wordchar(C) :- digit(C).
wordchar(0'_).
wordchar(0'-).
wordchar(C) :- apostrophe(C).

space(0' ).
space(0'\t).

% ---- case folding and byte widths, ISO only ------------------------------

lower(A, Lower) :- atom_codes(A, Cs), lower_codes(Cs, Ls), atom_codes(Lower, Ls).

lower_codes([], []).
lower_codes([C|Cs], [L|Ls]) :-
    (   C >= 0'A, C =< 0'Z -> L is C + 32 ; L = C ),
    lower_codes(Cs, Ls).

% How many bytes this code point takes in UTF-8.
utf8_len(C, 1) :- C < 128, !.
utf8_len(C, 2) :- C < 2048, !.
utf8_len(C, 3) :- C < 65536, !.
utf8_len(_, 4).

codes_bytes([], 0).
codes_bytes([C|Cs], N) :- utf8_len(C, K), codes_bytes(Cs, N0), N is N0 + K.

% ---- reading ------------------------------------------------------------

read_file_codes(File, Codes) :-
    open(File, read, S),
    read_codes(S, Codes),
    close(S).

read_codes(S, Codes) :-
    get_code(S, C),
    (   C =:= -1
    ->  Codes = []
    ;   Codes = [C|Rest],
        read_codes(S, Rest)
    ).

split_lines(Codes, Lines) :- split_lines_(Codes, [], Lines).

split_lines_([], Acc, [Line]) :- reverse(Acc, Line).
split_lines_([0'\n|Cs], Acc, [Line|Ls]) :-
    reverse(Acc, Line),
    split_lines_(Cs, [], Ls).
split_lines_([C|Cs], Acc, Ls) :-
    C =\= 0'\n,
    split_lines_(Cs, [C|Acc], Ls).

% ---- blocks -------------------------------------------------------------
%
% The block structure lives in markdown.pl, to GitHub Flavored Markdown
% 0.29-gfm. It used to live here, guessed from each line on its own, and every
% way that guess can be wrong showed up as a diagnostic: a bulleted list read
% as one paragraph of seven sentences, a step wrapped at a column that lost its
% second line, a decimal number opening a line that read as a step and had
% three of its characters eaten, a paragraph opening "Warnings" that took the
% safety limit.

% ---- tokenizing ---------------------------------------------------------

% block_tokens(+Block, -Tokens) over the content lines of a block.
%
% Every line arrives with the byte offset at which its content begins, worked
% out by the block parser, which is the only layer that knows the containers a
% line sits in. So there is no marker to strip here and no offset to guess: the
% tokens point into the source line, which is what the host slices.
block_tokens(block(_, _, Lines), Tokens) :- tokenize_lines(Lines, Tokens).

tokenize_lines([], []).
tokenize_lines([l(N, Byte, Cs)|Ls], Tokens) :-
    toks(Cs, N, Byte, Ts),
    tokenize_lines(Ls, Rest),
    append(Ts, Rest, Tokens).

% toks(+Codes, +Line, +Byte, -Tokens)
toks([], _, _, []).
toks([C|Cs], L, Byte, Tokens) :-
    (   space(C)
    ->  utf8_len(C, K), Byte1 is Byte + K,
        toks(Cs, L, Byte1, Tokens)
    ;   backtick(C)
    ->  delimited(c, C, Cs, L, Byte, Tokens)
    ;   dquote(C)
    ->  delimited(q, C, Cs, L, Byte, Tokens)
    ;   url_start([C|Cs])
    ->  upto_space([C|Cs], Content, Rest),
        emit(u, Content, Rest, L, Byte, Tokens)
    ;   alpha(C)
    ->  run([C|Cs], Content, Rest),
        emit(w, Content, Rest, L, Byte, Tokens)
    ;   digit(C)
    ->  number_run([C|Cs], Content, Rest),
        emit(n, Content, Rest, L, Byte, Tokens)
    ;   utf8_len(C, K), Byte1 is Byte + K,
        char_code(V, C),
        Tokens = [t(p, V, pos(L, Byte, K))|More],
        toks(Cs, L, Byte1, More)
    ).

% A delimited run: the value excludes the delimiters, the span includes them.
delimited(Kind, Open, Cs, L, Byte, [t(Kind, V, pos(L, Byte, Len))|More]) :-
    closer(Open, Close),
    span(Cs, Close, Content, Rest),
    atom_codes(V, Content),
    codes_bytes(Content, BLen),
    utf8_len(Open, KO), utf8_len(Close, KC),
    Len is BLen + KO + KC,
    Byte1 is Byte + Len,
    toks(Rest, L, Byte1, More).

emit(Kind, Content, Rest, L, Byte, [t(Kind, V, pos(L, Byte, Len))|More]) :-
    atom_codes(V, Content),
    codes_bytes(Content, Len),
    Byte1 is Byte + Len,
    toks(Rest, L, Byte1, More).

% A span runs to the closing delimiter, or to end of line if there is none.
span([], _, [], []).
span([C|Cs], D, Content, Rest) :-
    (   C =:= D
    ->  Content = [], Rest = Cs
    ;   Content = [C|More],
        span(Cs, D, More, Rest)
    ).

run([], [], []).
run([C|Cs], Content, Rest) :-
    (   wordchar(C)
    ->  Content = [C|More], run(Cs, More, Rest)
    ;   Content = [], Rest = [C|Cs]
    ).

number_run([], [], []).
number_run([C|Cs], Content, Rest) :-
    (   ( digit(C)
        ; C =:= 46, Cs = [D|_], digit(D)
        ; C =:= 0', , Cs = [D|_], digit(D) )
    ->  Content = [C|More], number_run(Cs, More, Rest)
    ;   Content = [], Rest = [C|Cs]
    ).

upto_space([], [], []).
upto_space([C|Cs], Content, Rest) :-
    (   space(C)
    ->  Content = [], Rest = [C|Cs]
    ;   Content = [C|More], upto_space(Cs, More, Rest)
    ).

% Spelled through atom_codes/2 rather than as "http://": a double-quoted
% literal is a string in SWI, a code list in ISO and a char list in Scryer, so
% the direct form failed here and shredded every URL into separate words.
url_start(Cs) :- atom_codes('http://', P), prefix_codes(P, Cs), !.
url_start(Cs) :- atom_codes('https://', P), prefix_codes(P, Cs), !.

prefix_codes([], _).
prefix_codes([C|Cs], [C|Rest]) :- prefix_codes(Cs, Rest).

% ---- spans --------------------------------------------------------------

pos_span(pos(L, B, Len), span(L, B, Len)).

% Widen from the start of the first token to the end of the last. Across
% lines the first token's own span is kept, since a span here is within a line.
pos_span(pos(L, B, _), pos(L, B2, Len2), span(L, B, Len)) :-
    !, Len is B2 + Len2 - B.
pos_span(P, _, Span) :- pos_span(P, Span).

% token_span(+Tokens, -Span) over a sentence or any run of tokens
token_span([T|Ts], Span) :-
    T = t(_, _, P0),
    last_token([T|Ts], t(_, _, P1)),
    pos_span(P0, P1, Span).

last_token([T], T) :- !.
last_token([_|Ts], T) :- last_token(Ts, T).

% ---- sentences ----------------------------------------------------------

% sentence_in(+Tokens, -Sentence) yields one sentence at a time, splitting on
% . ! ? and, per rule 8.4, on a colon, which in a vertical list has the same
% effect as a period.
sentence_in(Tokens, Sentence) :- sent_in(Tokens, [], Sentence).

sent_in([], Acc, Sentence) :-
    Acc = [_|_],
    reverse(Acc, Sentence).
sent_in([T|Ts], Acc, Sentence) :-
    (   sentence_end(T), \+ abbreviation_period(T, Ts)
    ->  reverse([T|Acc], S),
        (   Sentence = S
        ;   sent_in(Ts, [], Sentence)
        )
    ;   sent_in(Ts, [T|Acc], Sentence)
    ).

sentence_end(t(p, '.', _)).
sentence_end(t(p, '!', _)).
sentence_end(t(p, '?', _)).
sentence_end(t(p, ':', _)).

% A period that a numeral follows does not end a sentence. "No. 105", "Fig. 4"
% and "Ref. 12" are identifiers, and rule 8.6 counts each as one word. Splitting
% there left "SERVICE BULLETIN No." standing as a sentence of its own, whose
% only parse made SERVICE the verb of an imperative -- so the sentence convicted
% a technical noun that the rest of it would have resolved.
abbreviation_period(t(p, '.', _), [t(n, _, _)|_]).

% ---- word count, rules 8.4 thru 8.7 -------------------------------------

% count_words(+Tokens, -N)
%   8.5  text in parentheses counts as one word
%   8.6  a number, a number with its unit, an abbreviation, a quoted run and
%        a code span each count as one word
%   8.7  a hyphenated word counts as one word (the tokenizer keeps it whole)
count_words(Tokens, N) :- count_(Tokens, 0, N).

count_([], N, N).
count_([t(p, '(', _)|Ts], N0, N) :-
    !,
    N1 is N0 + 1,
    skip_parens(Ts, 1, Rest),
    count_(Rest, N1, N).
count_([t(p, _, _)|Ts], N0, N) :- !, count_(Ts, N0, N).
count_([t(n, _, _)|Ts], N0, N) :-
    !,
    N1 is N0 + 1,
    (   Ts = [t(w, U, _)|Rest], lower(U, Low), unit(Low)
    ->  count_(Rest, N1, N)            % 8.6, a number with its unit
    ;   count_(Ts, N1, N)
    ).
count_([t(_, _, _)|Ts], N0, N) :- N1 is N0 + 1, count_(Ts, N1, N).

skip_parens([], _, []).
skip_parens([t(p, '(', _)|Ts], D, Rest) :- !, D1 is D + 1, skip_parens(Ts, D1, Rest).
skip_parens([t(p, ')', _)|Ts], D, Rest) :-
    !,
    (   D =:= 1 -> Rest = Ts ; D1 is D - 1, skip_parens(Ts, D1, Rest) ).
skip_parens([_|Ts], D, Rest) :- skip_parens(Ts, D, Rest).

unit(U) :- member(U, [mm, cm, m, km, kg, g, mg, l, ml, kpa, psi, bar, deg, ft,
                      in, s, ms, min, h, hz, khz, mhz, ghz, v, kv, a, ma, w,
                      kw, n, nm, rpm, kb, mb, gb, tb, us, ns, knots, kt]).
