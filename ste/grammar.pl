% A DCG over the closed STE lexicon, to resolve a part of speech in context.
%
% This is the reason for choosing Prolog. Instead of asking a statistical
% tagger "what is `test` here", the lexicon offers every reading a word has and
% the parse decides which one survives. "Test the system" has no parse in which
% `test` is a noun, so `test` is a verb there, and rule 1.2 can say so --
% deterministically, with no newswire bias and no model.
%
% Two properties keep it honest as a gate:
%
%   * A word is committed only when EVERY parse agrees on it. Where the parses
%     disagree the word stays unresolved and the POS-dependent rules keep
%     quiet. Unanimity is the decidability criterion.
%   * Failure to parse is not a violation. STE is 53 editorial rules laid over
%     ordinary English, not a language defined by a grammar, so real STE text
%     will contain shapes this grammar does not cover. No parse means no POS
%     claim, and the lexicon-only warnings still apply.
%
% Ambiguity is held down structurally rather than by cutting: a clause takes at
% most one bare noun phrase, so the noun-phrase boundaries that blow up a naive
% grammar cannot chain. Sentences are at most 25 words by rule 6.3, which
% bounds the rest.

% ---- lexical candidates --------------------------------------------------

% cand(+Word, -POS) enumerates the readings a word can have here. Status is
% ignored: the grammar decides the reading, and the rules then judge whether
% that reading is approved.
cand(W, POS) :- \+ pseudo(W), form_of(W, _, POS).

% A technical noun, absent from the dictionary by design (rule 1.6). The
% exclusions matter: without them a comma, a numeral and every adverb acquire a
% noun reading and get absorbed into noun phrases, which reported "DO STEP 2
% THREE TIMES" and "A SOFT, DRY CLOTH" as four-word nouns.
cand(W, n) :-
    \+ pseudo(W),
    \+ closed_class(W),
    \+ form_of(W, _, n),
    \+ approved_as(W, adv),      % an adverb is never a technical noun
    \+ approved_as(W, v).        % a verb the standard approves is not one either

cand(W, adj) :-
    \+ pseudo(W),
    \+ closed_class(W),
    \+ ste_form(W, _, adj),
    modifier_form(W).            % participle as adjective (3.3), -ing (3.5)

% Stand-ins the tokenizer puts in place of a number, a code span or a comma.
% Only opaque//1 and comma//0 may consume them.
pseudo(',').
pseudo(numeral).
pseudo(code_span).

approved_as(W, POS) :- ste_form(W, Base, POS), ste_word(Base, POS, approved, _).

% A function word never doubles as a technical noun, so it gets no noun
% reading; that keeps "the" and "of" out of noun phrases as heads.
closed_class(W) :-
    ste_form(W, _, POS),
    memberchk(POS, [art, prep, conj, pron]), !.

modifier_form(W) :- ends_with(W, ing), !.
modifier_form(W) :- ends_with(W, ed), !.
modifier_form(W) :- ends_with(W, en), !.

% ---- items ---------------------------------------------------------------

% items(+Sentence, -Items) keeps the words and the commas, indexed. The comma
% matters: rule 5.4 divides a condition from its command with one.
items(Tokens, Items) :- items_(Tokens, 1, Items).

items_([], _, []).
items_([t(w, W, _)|Ts], I, [i(I, Low)|Is]) :-
    !, lower(W, Low), I1 is I + 1, items_(Ts, I1, Is).
items_([t(p, ',', _)|Ts], I, [i(I, ',')|Is]) :-
    !, I1 is I + 1, items_(Ts, I1, Is).
items_([t(c, _, _)|Ts], I, [i(I, code_span)|Is]) :-
    !, I1 is I + 1, items_(Ts, I1, Is).
items_([t(n, _, _)|Ts], I, [i(I, numeral)|Is]) :-
    !, I1 is I + 1, items_(Ts, I1, Is).
items_([_|Ts], I, Is) :- items_(Ts, I, Is).

% index_token(+Sentence, +Index, -Token) to get a position back for a report
index_token(Tokens, Index, Token) :-
    items(Tokens, Items),
    nth_item(Items, Index, i(Index, _)),
    word_tokens_only(Tokens, Ws),
    nth1_(Index, Ws, Token).

nth_item(Items, Index, Item) :- memberchk(Item, Items), Item = i(Index, _).

word_tokens_only([], []).
word_tokens_only([T|Ts], [T|Ws]) :-
    ( T = t(w, _, _) ; T = t(p, ',', _) ; T = t(c, _, _) ;
      T = t(n, _, _) ), !,
    word_tokens_only(Ts, Ws).
word_tokens_only([_|Ts], Ws) :- word_tokens_only(Ts, Ws).

nth1_(1, [X|_], X) :- !.
nth1_(N, [_|Xs], X) :- N > 1, N1 is N - 1, nth1_(N1, Xs, X).

% ---- terminals -----------------------------------------------------------

% A multi-word entry is matched before a single word, so "make sure" is one
% verb and not a verb followed by an adjective.
% The cut commits a multi-word entry once it matches. Without it "make sure"
% parses both as one verb and as a verb plus an adjective, and the two readings
% disagree, so unanimity throws away a word the lexicon knew all along.
tw(POS, [I1-POS, I2-POS]) -->
    [i(I1, W1), i(I2, W2)],
    { ste_tokens([W1, W2], _, POS) },
    !.
tw(POS, [I-POS]) -->
    [i(I, W)],
    { cand(W, POS) }.

comma --> [i(_, ',')].

% numerals and code spans stand in for a noun phrase
opaque([]) --> [i(_, numeral)].
opaque([]) --> [i(_, code_span)].

% "No. 105" is an identifier and not two words to resolve. The period is not an
% item, so the pair arrives as `no` and a numeral. Without this production
% "SERVICE BULLETIN No. 105 CHANGES THE BOLTS ..." had no parse in which
% SERVICE is a noun, and the only parse left made it the verb.
opaque([]) --> [i(_, no), i(_, numeral)].

% ---- clauses -------------------------------------------------------------

sent(As) --> clause_(A1), sent_tail(A2), { append(A1, A2, As) }.

% Only a coordinator joins two clauses here. Accepting any conjunction let
% "AS SHOWN IN FIGURE 4" attach as a coordinated clause, which kept AS
% unresolvable: subordination is already covered by condition//1 and by the
% "that ..." modifier.
sent_tail([]) --> [].
sent_tail(As) --> coord(A1), clause_(A2), { append(A1, A2, As) }.
sent_tail(As) --> comma, coord(A1), clause_(A2), { append(A1, A2, As) }.

coord([I-conj]) --> [i(I, W)], { memberchk(W, [and, or, but, then]) }.

% Rule 5.4: a condition comes first and a comma divides it from the command.
clause_(As) --> condition(A1), comma, clause_(A2), { append(A1, A2, As) }.

% A sentence may open with an adverbial: "BEFORE EACH CYCLE, CLEAN THE
% INDICATOR", "AFTER THE TEST, RECORD THE VALUES". Without this production a
% prepositional phrase can only sit inside a predicate, and the only parse left
% for that sentence reads EACH as a pronoun subject and CYCLE as its verb.
clause_(As) --> pp(A1), comma, clause_(A2), { append(A1, A2, As) }.
clause_(As) --> tw(adv, A1), comma, clause_(A2), { append(A1, A2, As) }.

clause_(As) --> imperative(As).
clause_(As) --> declarative(As).

condition(As) --> tw(conj, A1), declarative(A2), { append(A1, A2, As) }.
condition(As) --> tw(conj, A1), imperative(A2), { append(A1, A2, As) }.

imperative(As)  --> verb_group(A1), predicate(A2), { append(A1, A2, As) }.
declarative(As) --> subject(A1), verb_group(A2), predicate(A3),
                    { append(A1, A2, AB), append(AB, A3, As) }.

% Two coordinated noun phrases as the subject: "IF FUEL AND WATER MIX, ...".
% Without it that sentence had no parse in which FUEL is a noun, so the only
% parse left read it as the verb of an imperative.
%
% Coordination is allowed in the SUBJECT only, never in the object. That keeps
% the one-bare-noun-phrase restriction on the predicate intact, which is the
% property that stops noun-phrase boundaries from chaining and the parse count
% from exploding.
subject(As) --> np(A1), coord(A2), np(A3), { append(A1, A2, AB), append(AB, A3, As) }.
subject(As) --> np(As).

% ---- verb group, the forms rule 3.2 permits ------------------------------

% Infinitive, imperative, simple present, simple past, simple future. The
% progressive, the perfect and auxiliary chains are outside this grammar, and
% rules.pl reports the forms it cannot parse.
verb_group(As) --> adverbs(A1), verb_core(A2), adverbs(A3),
                   { append(A1, A2, AB), append(AB, A3, As) }.

verb_core(As) --> modal(A1), adverbs(A2), tw(v, A3),
                  { append(A1, A2, AB), append(AB, A3, As) }.
verb_core(As) --> tw(v, As).

modal(As) --> [i(I, W)], { memberchk(W, [must, can, will, do, does, did]), As = [I-v] }.

adverbs([]) --> [].
adverbs(As) --> tw(adv, A1), adverbs(A2), { append(A1, A2, As) }.

% ---- predicate -----------------------------------------------------------

% At most one bare noun phrase, then only marked modifiers. That single
% restriction is what stops noun-phrase boundaries from chaining and the parse
% count from exploding.
predicate(As) --> object(A1), modifiers(A2), { append(A1, A2, As) }.

object([]) --> [].
object(As) --> np(As).
object(As) --> tw(adj, As).             % copula complement: "is clean"
object(As) --> opaque(As).

modifiers([]) --> [].
modifiers(As) --> modifier(A1), modifiers(A2), { append(A1, A2, As) }.

modifier(As) --> idiom(As), !.
modifier(As) --> pp(As).
modifier(As) --> tw(adv, As).
modifier(As) --> tw(conj, A1), sent(A2), { append(A1, A2, As) }.   % "that ..."
modifier(As) --> comma, pp(As).
modifier(As) --> to_infinitive(As).
modifier(As) --> tw(conj, A1), np(A2), { append(A1, A2, As) }.     % "and the pump"

% Fixed phrases the standard uses in its own STE examples. Word by word the
% lexicon convicts "as follows": AS as a conjunction is not approved and
% FOLLOWS is a form of FOLLOW, which rule 1.2 replaces with OBEY. Listing the
% phrase adds a competing parse, and unanimity then declines to convict --
% which is the mechanism doing its job rather than an exception to it.
idiom([I1-prep, I2-adv]) --> [i(I1, as), i(I2, follows)].
idiom([I1-adv, I2-adv])  --> [i(I1, at), i(I2, first)].

% "AS SHOWN IN FIGURE 4", "AS REQUIRED", "AS SPECIFIED": a reduced clause in
% which AS is the preposition, which is the reading the standard approves. With
% no noun phrase after it, the only other parse makes AS a conjunction, and
% "as (conj)" is not approved -- so the sentence convicted itself.
idiom([I1-prep, I2-adj]) --> [i(I1, as), i(I2, W)], { participle(W) }.

to_infinitive(As) -->
    [i(I, to)], verb_group(A1), predicate(A2),
    { append([I-prep|A1], A2, As) }.

pp(As) --> tw(prep, A1), np(A2), { append(A1, A2, As) }.
pp(As) --> tw(prep, A1), opaque(A2), { append(A1, A2, As) }.

% ---- noun phrase ---------------------------------------------------------

% An alphanumeric identifier may follow the head: "PART 2", "STEP 3",
% "FIGURE 4". Without this "REFER TO PART 2" has only one parse, the one that
% reads TO as an infinitive marker and PART as a verb.
np(As) --> np_core(As), opaque(_).
np(As) --> np_core(As).

np_core(As) --> determiner(A1), nominal(A2, _), { append(A1, A2, As) }.
np_core(As) --> nominal(As, _).
np_core([I-pron]) --> [i(I, W)], { bare_pronoun(W) }.
% "EACH OF THE BOLTS": a quantifier stands for a noun phrase only with "of".
np_core(As) --> [i(I, W)], { quantifier(W) }, pp(A2), { As = [I-pron|A2] }.

bare_pronoun(W) :- memberchk(W, [you, it, they, them, we, us, he, she, him,
                                 her, i, me, who, which, this, these, that,
                                 those, there]).

quantifier(W) :- memberchk(W, [each, both, all, some, any, one, none, either,
                               neither, other, others]).

% 2. "AS SHOWN" commits: with a bare participle after it, AS is the
%    preposition, and leaving the conjunction reading alive only makes the
%    position unresolvable.

determiner(As) --> tw(art, As).
determiner(As) --> [i(I, W)], { memberchk(W, [this, these, its, their, your,
                                              our, his, her, my, each, all,
                                              any, no, some, both, one, every,
                                              other, another]),
                                 As = [I-adj] }.

% Rule 2.1 caps a multi-word noun at three words. The grammar accepts up to
% six so that rules.pl can report the overrun instead of failing to parse.
nominal(As, Len) -->
    mods(Ms, N), tw(n, A),
    { append(Ms, A, Ps), Len is N + 1,
      Ps = [Start-_|_],
      As = [mwn(Start, Len)|Ps] }.

mods([], 0) --> [].
mods(As, N) --> mod(A1), mods(A2, N0), { append(A1, A2, As), N is N0 + 1, N =< 5 }.

mod(As) --> tw(adj, As).
mod(As) --> tw(n, As).

% ---- resolution ----------------------------------------------------------

% resolve(+Sentence, -Resolved, -Status)
%   Status = resolved(NParses) when the sentence parses
%          = unparsed         when it does not, and no POS is claimed
% Resolved holds only the positions every parse agrees on.
resolve(Tokens, Resolved, Status) :-
    items(Tokens, Items),
    Items = [_|_],
    findall(As, phrase(sent(As), Items), Parses),
    (   Parses == []
    ->  Resolved = [], Status = unparsed
    ;   length(Parses, N),
        unanimous(Parses, Resolved),
        Status = resolved(N)
    ).

% Holds for any item the parse contributes: a position assignment I-POS or a
% multi-word noun span mwn(Start, Length). A span is reported only when every
% parse drew the same one.
unanimous([P|Ps], Resolved) :-
    % \+ (Cond, \+ Action) rather than forall/2: forall is not ISO, and
    % Scryer does not have it. Inlining costs a line and removes a dependency.
    findall(X,
            ( member(X, P),
              \+ ( member(Q, Ps), \+ memberchk(X, Q) ) ),
            Agreed),
    sort(Agreed, Resolved).

% pos_at(+Resolved, +Index, -POS)
pos_at(Resolved, Index, POS) :- memberchk(Index-POS, Resolved).

% span_at(+Resolved, -Start, -Length) for a multi-word noun the parse built
span_at(Resolved, Start, Len) :- member(mwn(Start, Len), Resolved).

% indexed_words(+Sentence, -Pairs) with indices matching those in Resolved,
% so a diagnostic can go from a resolved position back to a line and column.
indexed_words(Tokens, Pairs) :-
    word_tokens_only(Tokens, Ws),
    number_from(Ws, 1, Pairs).

number_from([], _, []).
number_from([T|Ts], I, [iw(I, T)|Ps]) :- I1 is I + 1, number_from(Ts, I1, Ps).
