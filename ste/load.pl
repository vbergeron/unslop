% Loads the engine under SWI-Prolog, for development and for the tests.
%
% The engine itself carries no load directives: a host embeds it by consulting
% each file from a string, in this order, because there is no filesystem to
% resolve a directive against. Keeping the order in one place here means the
% host and the tests cannot drift apart.

:- ensure_loaded('markdown.pl').
:- ensure_loaded('tokenize.pl').
:- ensure_loaded('../dictionary/ste_dictionary.pl').
:- ensure_loaded('lexicon.pl').
:- ensure_loaded('grammar.pl').
:- ensure_loaded('rules.pl').
:- ensure_loaded('engine.pl').
