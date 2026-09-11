% The checks. Every one names the rule it enforces, so a diagnostic can be
% traced back to the standard.
%
% A diagnostic is
%
%   diag(Rule, Severity, Span, Finding, Suggestions)
%
%     Rule        an atom, '1.2', '5.4', ...
%     Severity    error | warning
%     Span        span(Line, Byte, Len), byte offsets within the line
%     Finding     one functor per class of finding, carrying its data
%     Suggestions a list, possibly empty
%
% Nothing here formats a message. The Finding functor IS the interface: the
% consumer matches on it and owns all the wording, which is what lets the same
% engine drive a terminal, JSON, SARIF or an editor.
%
% The one kind of prose that crosses the boundary is the standard's own:
% replace/1 and advice/1 carry text quoted verbatim out of ASD-STE100, never
% wording of ours.
%
% Severity follows the polarity argument for a gate: a check fires as an error
% only where the standard is closed and the evidence is positive. Anything
% resting on a heuristic, or on a reading the grammar could not settle, is a
% warning, so the gate stays usable.

% Rule 5.1 for procedures, rule 6.3 for descriptive text.
limit(procedural,  20).
limit(safety,      20).
limit(item,        25).
limit(descriptive, 25).
limit(note,        25).

% ---- sentence level ------------------------------------------------------

% sentence_diag(+BlockKind, +Sentence, +Resolved, -Diag) where Resolved is the
% part-of-speech assignment the grammar could commit to, possibly empty.
sentence_diag(Kind, S, _, D) :- too_long(Kind, S, D).
sentence_diag(_,    S, _, D) :- semicolon(S, D).
sentence_diag(_,    S, _, D) :- contraction(S, D).
sentence_diag(_,    S, R, D) :- vocabulary(S, R, D).
sentence_diag(_,    S, _, D) :- inflection(S, D).
sentence_diag(Kind, S, _, D) :- bad_verb_group(Kind, S, D).
sentence_diag(_,    S, R, D) :- multi_word_noun(S, R, D).
sentence_diag(_,    S, R, D) :- noun_as_verb(S, R, D).
sentence_diag(procedural, S, _, D) :- condition_comma(S, D).
sentence_diag(procedural, S, _, D) :- imperative_start(S, D).
sentence_diag(note, S, _, D) :- note_instruction(S, D).

% Rules 5.1 and 6.3, counted by the rules of section 8.
too_long(Kind, S, diag(Rule, error, Span, sentence_too_long(N, Max, Kind),
                       [split_sentence])) :-
    limit(Kind, Max),
    count_words(S, N),
    N > Max,
    token_span(S, Span),
    ( Kind == procedural -> Rule = '5.1' ; Rule = '6.3' ).

% Rule 8.1.
semicolon(S, diag('8.1', error, Span, semicolon, [two_sentences])) :-
    member(t(p, ';', P), S),
    pos_span(P, Span).

% Rule 4.2.
contraction(S, diag('4.2', error, Span, contraction(W), [expand(Expansion)])) :-
    member(t(w, W, P), S),
    lower(W, Low),
    contracted(Low, Expansion),
    pos_span(P, Span).

contracted(W, E) :-
    member(W-E, ['don\'t'-'do not', 'doesn\'t'-'does not', 'didn\'t'-'did not',
                 'can\'t'-'cannot', 'won\'t'-'will not', 'isn\'t'-'is not',
                 'aren\'t'-'are not', 'wasn\'t'-'was not', 'weren\'t'-'were not',
                 'it\'s'-'it is', 'you\'re'-'you are', 'they\'re'-'they are',
                 'we\'re'-'we are', 'i\'m'-'I am', 'let\'s'-'let us',
                 'hasn\'t'-'has not', 'haven\'t'-'have not', 'hadn\'t'-'had not',
                 'shouldn\'t'-'should not', 'wouldn\'t'-'would not',
                 'couldn\'t'-'could not', 'mustn\'t'-'must not']), !.

% ---- rules 1.1, 1.2 and 1.6 ---------------------------------------------

vocabulary(S, Resolved, D) :-
    \+ safety_label(S),
    indexed_words(S, Pairs),
    member(iw(I, t(w, W, P)), Pairs),
    lower(W, Low),
    \+ markup_word(Low),
    pos_span(P, Span),
    (   pos_at(Resolved, I, POS)
    ->  resolved_vocab(W, Low, POS, Span, D)
    ;   word_status(Low, Status),
        unresolved_vocab(W, Status, Span, D)
    ).

% The reading is settled, so rule 1.2 applies as written.
%
% The lookup goes through form_of/3 and not ste_form/3, which is the predicate
% word_status/2 uses on the unresolved path. With ste_form/3 here the two paths
% disagreed on every regular plural of a dictionary noun -- some 200 of them
% are not-approved -- and the disagreement fell on the side that lets text
% through: "portion" drew an error carrying PIECE (n), PART (n), while
% "portions" drew a rule 1.1 warning whose advice is to add the word to the
% glossary, which suppresses the finding for good.
resolved_vocab(_, Low, POS, _, _) :-
    form_of(Low, Base, POS), ste_word(Base, POS, approved, _), !, fail.
resolved_vocab(W, Low, POS, Span, diag('1.2', Sev, Span, Finding, Sugg)) :-
    form_of(Low, Base, POS),
    ste_word(Base, POS, not_approved, _), !,
    alternatives(Base, POS, Sugg),
    (   unconditional(Base, _)
    ->  % On the standard's own list of frequent errors, minus its
        % part-of-speech-dependent entries: the replacement holds whatever the
        % reading, so resolving the reading cannot soften it.
        Sev = error, Finding = never_approved(W)
    ;   POS == n
    ->  % Rule 1.6 lets a word that is not approved stand when it is a
        % technical noun or part of one, and technical nouns are absent from
        % the dictionary by design. "THE DANGER AREA" and "A FAILURE OF THE
        % PUMP" are the standard's own STE, so a noun reading can only advise.
        Sev = warning, Finding = technical_noun_reading(W)
    ;   technical_advice(Base, POS)
    ->  Sev = warning, Finding = technical_noun_only(W, POS)
    ;   \+ approved_somewhere(Low), POS \== v
    ->  % No reading of this word is approved anywhere and the position is not a
        % verb, so rule 1.6 leaves the technical-noun escape open and a wrong
        % parse cannot be ruled out.
        Sev = warning, Finding = undecidable_reading(W, POS)
    ;   % Two cases land here, and rule 1.2 applies as written to both.
        %
        % The word IS approved, just not in this reading, and the grammar
        % settled the reading.
        %
        % Or no reading of the word is approved anywhere AND the grammar
        % committed the position to a verb. The escape that would otherwise
        % excuse it is the technical-NOUN escape of rule 1.6, which a verb
        % position cannot claim; the technical-VERB escape was already tested
        % one branch above, through technical_advice/2. Holding this case as a
        % warning cost 22 points of sensitivity, measured: see the Measured
        % section of ../README.md.
        Sev = error, Finding = not_approved_as(W, POS)
    ).
resolved_vocab(W, Low, n, Span,
               diag('1.1', warning, Span, unlisted_technical_noun(W),
                    [add_to_glossary])) :-
    \+ in_glossary(Low),
    \+ form_of(Low, _, _), !.

% No reading was settled, so only what holds for every reading can be said.
unresolved_vocab(W, replace(Base, POS, _), Span,
                 diag('1.2', error, Span, never_approved(W), Sugg)) :-
    unconditional(Base, _), !,
    alternatives(Base, POS, Sugg).
unresolved_vocab(W, replace(Base, POS, _), Span,
                 diag('1.2', warning, Span, undecidable_reading(W, POS), Sugg)) :-
    !, alternatives(Base, POS, Sugg).
unresolved_vocab(W, unknown, Span,
                 diag('1.1', warning, Span, not_in_dictionary(W),
                      [add_to_glossary])).

% The standard's own words: its approved alternatives, or the note it gives
% when the answer is advice rather than a word.
alternatives(Base, POS, Sugg) :-
    findall(A, ste_alternative_text(Base, POS, A), Raw),
    dedup(Raw, Alts),
    (   Alts = [_|_] -> Sugg = [replace(Alts)]
    ;   ste_note(Base, POS, Note) -> Sugg = [advice(Note)]
    ;   Sugg = []
    ).

% ---- rules 1.4, 3.1, 3.3 and 3.5 ----------------------------------------

% An inflection of an approved verb that the dictionary does not list among
% its forms. A warning on purpose: rule 3.5 permits an "-ing" form as a
% technical noun or a modifier ("descriptive writing") and rule 3.3 permits a
% past participle as an adjective ("the failed upload"), so the form alone is
% not positive evidence. The one case that IS positive -- an "-ing" form
% governed by a form of "be" -- is the progressive, which rule 3.2 reports.
inflection(S, diag(Rule, warning, Span, forbidden_form(W, Base), Sugg)) :-
    member(t(w, W, P), S),
    lower(W, Low),
    bad_inflection(Low, Base),
    pos_span(P, Span),
    findall(F, ( ste_form(F, Base, v), F \== Base ), Forms),
    (   ends_with(Low, ing)
    ->  Rule = '3.5', Sugg = [keep_as_modifier(Base)]
    ;   Rule = '1.4', Sugg = [use_form(Base, Forms)]
    ).

% ---- rules 3.2, 3.4 and 3.6 ---------------------------------------------

% Over adjacent words. This is what the closed lexicon buys: the permitted
% verb forms are enumerated by the standard, so a construction outside them is
% a positive finding, not a guess.
bad_verb_group(Kind, S, D) :-
    words_of(S, Ws),
    append(_, [w(A, P1), w(B, P2)|_], Ws),
    group_kind(A, B, Rule, What),
    pos_span(P1, P2, Span),
    group_diag(Kind, Rule, What, A, B, Span, D).

group_kind(A, B, '3.2', progressive) :- be_form(A), ing_form(B), !.
group_kind(A, B, '3.6', passive)     :- be_form(A), participle(B), !.
group_kind(A, B, '3.2', perfect)     :- have_form(A), participle(B), !.

% Rule 3.6 permits the passive in descriptive text when the agent is unknown,
% so it can only be a warning there. In a procedure it is forbidden outright.
group_diag(Kind, '3.6', passive, A, B, Span,
           diag('3.6', Sev, Span, passive_voice(A, B), [active_voice])) :-
    !, ( Kind == procedural -> Sev = error ; Sev = warning ).
group_diag(_, Rule, What, A, B, Span,
           diag(Rule, error, Span, verb_construction(What, A, B), [simple_tense])).

% ---- rule 2.1 ------------------------------------------------------------

% A multi-word noun of more than three words. The span comes from the grammar,
% which built the noun phrase, rather than from a run of parts of speech
% reconstructed afterwards -- that reconstruction crossed phrase boundaries.
%
% A warning, not an error: the rule is closed at three words but the
% constituent boundary is not. "MOBILE GROUND POWER UNIT" may be a four-word
% noun or an adjective before a three-word one, and the parse cannot settle it.
multi_word_noun(S, Resolved, diag('2.1', warning, Span,
                                  multi_word_noun(Len, 3, W), [shorten_noun])) :-
    span_at(Resolved, Start, Len),
    Len > 3,
    indexed_words(S, Pairs),
    memberchk(iw(Start, t(w, W, P)), Pairs),
    pos_span(P, Span).

% ---- rule 1.7 ------------------------------------------------------------

noun_as_verb(S, Resolved, diag('1.7', error, Span, noun_used_as_verb(W),
                               [use_approved_verb])) :-
    indexed_words(S, Pairs),
    member(iw(I, t(w, W, P)), Pairs),
    lower(W, Low),
    pos_at(Resolved, I, v),
    \+ ste_form(Low, _, v),
    ste_form(Low, Base, n),
    ste_word(Base, n, approved, _),
    pos_span(P, Span).

% ---- rules 5.3, 5.4 and 5.5 ---------------------------------------------

% Rule 5.4: a condition must be divided from the command by a comma.
condition_comma(S, diag('5.4', error, Span, condition_not_divided(W),
                        [add_comma])) :-
    S = [t(w, W, P)|_],
    lower(W, Low),
    memberchk(Low, [if, when]),
    \+ member(t(p, ',', _), S),
    pos_span(P, Span).

% Rule 5.3: an instruction is written in the imperative. A step may instead
% open with a condition (rule 5.4), so both shapes are accepted.
imperative_start(S, diag('5.3', warning, Span, step_without_verb(W),
                         [start_with_imperative])) :-
    S = [t(w, W, P)|_],
    lower(W, Low),
    \+ memberchk(Low, [if, when]),
    \+ ste_form(Low, _, v),          % no verb reading at all, approved or not
    pos_span(P, Span).

% Rule 5.5: a note gives information, not instructions.
note_instruction(S, diag('5.5', warning, Span, note_gives_instruction(W),
                         [move_to_step])) :-
    S = [t(w, W, P)|_],
    lower(W, Low),
    imperative_verb(Low),
    pos_span(P, Span).

imperative_verb(W) :- ste_word(W, v, approved, _), ste_form(W, W, v).

% ---- block level ---------------------------------------------------------

% Rule 6.6. The span is the head of the paragraph: the finding is about the
% paragraph, which has no single offset to point at.
block_diag(descriptive, block(_, Line, _), Sentences,
           diag('6.6', error, span(Line, 0, 0), paragraph_too_long(N, 6),
                [split_paragraph])) :-
    length(Sentences, N),
    N > 6.

% ---- helpers -------------------------------------------------------------

% Markup that survived tokenizing: emphasis and link syntax leave stray words.
markup_word(W) :- atom_length(W, 1), \+ memberchk(W, [a, i]).

% "WARNING:" and "CAUTION:" name the block, they are not part of its prose.
% Rule 8.4 makes the colon end a sentence, so the label stands alone.
safety_label([t(w, W, _)|Rest]) :-
    lower(W, Low),
    memberchk(Low, [warning, caution, danger, notice]),
    ( Rest == [] -> true ; Rest = [t(p, ':', _)|_] ).

words_of([], []).
words_of([t(w, W, P)|Ts], [w(Low, P)|Ws]) :- !, lower(W, Low), words_of(Ts, Ws).
words_of([_|Ts], Ws) :- words_of(Ts, Ws).
