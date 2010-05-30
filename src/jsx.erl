%% The MIT License

%% Copyright (c) 2010 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx).
-author("alisdairsullivan@yahoo.ca").

-export([decoder/0, decoder/1, decoder/2]).


%% option flags

-define(comments_true(X), {true, _} = X).
-define(escaped_unicode_to_ascii(X), {_, ascii} = X).
-define(escaped_unicode_to_codepoint(X), {_, codepoint} = X).

%% whitespace
-define(space, 16#20).
-define(tab, 16#09).
-define(cr, 16#0D).
-define(newline, 16#0A).

%% object delimiters
-define(start_object, 16#7B).
-define(end_object, 16#7D).

%% array delimiters
-define(start_array, 16#5B).
-define(end_array, 16#5D).

%% kv seperator
-define(comma, 16#2C).
-define(quote, 16#22).
-define(colon, 16#3A).

%% string escape sequences
-define(escape, 16#5C).
-define(rsolidus, 16#5C).
-define(solidus, 16#2F).
-define(formfeed, 16#0C).
-define(backspace, 16#08).
-define(unicode, 16#75).

%% math
-define(zero, 16#30).
-define(decimalpoint, 16#2E).
-define(negative, 16#2D).
-define(positive, 16#2B).

%% comments
-define(star, 16#2a).

-define(is_hex(Symbol),
    (Symbol >= $a andalso Symbol =< $z); (Symbol >= $A andalso Symbol =< $Z); 
        (Symbol >= $0 andalso Symbol =< $9)
).

-define(is_nonzero(Symbol),
    Symbol >= $1 andalso Symbol =< $9
).

-define(is_noncontrol(Symbol),
    Symbol >= ?space
).

-define(is_whitespace(Symbol),
    Symbol =:= ?space; Symbol =:= ?tab; Symbol =:= ?cr; Symbol =:= ?newline
).


decoder() ->
    decoder([]).

decoder(Opts) ->
    F = fun(end_of_stream, State) -> lists:reverse(State) ;(Event, State) -> [Event] ++ State  end,
    decoder({F, []}, Opts).

decoder({F, _} = Callbacks, OptsList) when is_list(OptsList), is_function(F) ->
    Opts = parse_opts(OptsList),
    decoder(Callbacks, Opts);
decoder({{Mod, Fun}, State}, OptsList) when is_list(OptsList), is_atom(Mod), is_atom(Fun) ->
    Opts = parse_opts(OptsList),
    decoder({fun(E, S) -> Mod:Fun(E, S) end, State}, Opts);
decoder(Callbacks, Opts) ->
    fun(Stream) -> try start(Stream, [], Callbacks, Opts) catch error:function_clause -> {error, badjson} end end.

    
parse_opts(Opts) ->
    parse_opts(Opts, {false, codepoint}).

parse_opts([], Opts) ->
    Opts;    
parse_opts([{comments, Value}|Rest], {_Comments, EscapedUnicode}) ->
    true = lists:member(Value, [true, false]),
    parse_opts(Rest, {Value, EscapedUnicode});
parse_opts([{escaped_unicode, Value}|Rest], {Comments, _EscapedUnicode}) ->
    true = lists:member(Value, [ascii, codepoint, none]),
    parse_opts(Rest, {Comments, Value});
parse_opts([_UnknownOpt|Rest], Opts) ->
    parse_opts(Rest, Opts).
    
    
%% this code is mostly autogenerated and mostly ugly. apologies. for more insight on
%%   Callbacks or Opts, see the comments accompanying decoder/2 (in jsx.erl). Stack 
%%   is a stack of flags used to track depth and to keep track of whether we are 
%%   returning from a value or a key inside objects. all pops, peeks and pushes are 
%%   inlined. the code that handles naked values and comments is not optimized by the 
%%   compiler for efficient matching, but you shouldn't be using naked values or comments 
%%   anyways, they are horrible and contrary to the spec.

start(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) -> 
    start(Rest, Stack, Callbacks, Opts);
start(<<?start_object, Rest/binary>>, Stack, Callbacks, Opts) ->
    object(Rest, [key|Stack], fold(start_object, Callbacks), Opts);
start(<<?start_array, Rest/binary>>, Stack, Callbacks, Opts) ->
    array(Rest, [array|Stack], fold(start_array, Callbacks), Opts);
start(<<?quote, Rest/binary>>, Stack, Callbacks, Opts) ->
    string(Rest, Stack, Callbacks, Opts, []);
start(<<$t, Rest/binary>>, Stack, Callbacks, Opts) ->
    tr(Rest, Stack, Callbacks, Opts);
start(<<$f, Rest/binary>>, Stack, Callbacks, Opts) ->
    fa(Rest, Stack, Callbacks, Opts);
start(<<$n, Rest/binary>>, Stack, Callbacks, Opts) ->
    nu(Rest, Stack, Callbacks, Opts);
start(<<?negative, Rest/binary>>, Stack, Callbacks, Opts) ->
    negative(Rest, Stack, Callbacks, Opts, "-");
start(<<?zero, Rest/binary>>, Stack, Callbacks, Opts) ->
    zero(Rest, Stack, Callbacks, Opts, "0");
start(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_nonzero(S) ->
    integer(Rest, Stack, Callbacks, Opts, [S]);
start(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> start(Resume, Stack, Callbacks, Opts) end);
start(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> start(Stream, Stack, Callbacks, Opts) end}.


maybe_done(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) ->
    maybe_done(Rest, Stack, Callbacks, Opts);
maybe_done(<<?end_object, Rest/binary>>, [object|Stack], Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold(end_object, Callbacks), Opts);
maybe_done(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold(end_array, Callbacks), Opts);
maybe_done(<<?comma, Rest/binary>>, [object|Stack], Callbacks, Opts) ->
    key(Rest, [key|Stack], Callbacks, Opts);
maybe_done(<<?comma, Rest/binary>>, [array|_] = Stack, Callbacks, Opts) ->
    value(Rest, Stack, Callbacks, Opts);
maybe_done(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> maybe_done(Resume, Stack, Callbacks, Opts) end);
maybe_done(<<>>, [], Callbacks, Opts) ->
    {fold(end_of_stream, Callbacks), fun(Stream) -> maybe_done(Stream, [], Callbacks, Opts) end};
maybe_done(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> maybe_done(Stream, Stack, Callbacks, Opts) end}.


object(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) ->
    object(Rest, Stack, Callbacks, Opts);
object(<<?quote, Rest/binary>>, Stack, Callbacks, Opts) ->
    string(Rest, Stack, Callbacks, Opts, []);
object(<<?end_object, Rest/binary>>, [key|Stack], Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold(end_object, Callbacks), Opts);
object(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> object(Resume, Stack, Callbacks, Opts) end);
object(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> object(Stream, Stack, Callbacks, Opts) end}.


array(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) -> 
    array(Rest, Stack, Callbacks, Opts);       
array(<<?quote, Rest/binary>>, Stack, Callbacks, Opts) ->
    string(Rest, Stack, Callbacks, Opts, []);
array(<<$t, Rest/binary>>, Stack, Callbacks, Opts) ->
    tr(Rest, Stack, Callbacks, Opts);
array(<<$f, Rest/binary>>, Stack, Callbacks, Opts) ->
    fa(Rest, Stack, Callbacks, Opts);
array(<<$n, Rest/binary>>, Stack, Callbacks, Opts) ->
    nu(Rest, Stack, Callbacks, Opts);
array(<<?negative, Rest/binary>>, Stack, Callbacks, Opts) ->
    negative(Rest, Stack, Callbacks, Opts, "-");
array(<<?zero, Rest/binary>>, Stack, Callbacks, Opts) ->
    zero(Rest, Stack, Callbacks, Opts, "0");
array(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_nonzero(S) ->
    integer(Rest, Stack, Callbacks, Opts, [S]);
array(<<?start_object, Rest/binary>>, Stack, Callbacks, Opts) ->
    object(Rest, [key|Stack], fold(start_object, Callbacks), Opts);
array(<<?start_array, Rest/binary>>, Stack, Callbacks, Opts) ->
    array(Rest, [array|Stack], fold(start_array, Callbacks), Opts);
array(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold(end_array, Callbacks), Opts);
array(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> array(Resume, Stack, Callbacks, Opts) end);
array(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> array(Stream, Stack, Callbacks, Opts) end}.  


value(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) -> 
    value(Rest, Stack, Callbacks, Opts);
value(<<?quote, Rest/binary>>, Stack, Callbacks, Opts) ->
    string(Rest, Stack, Callbacks, Opts, []);
value(<<$t, Rest/binary>>, Stack, Callbacks, Opts) ->
    tr(Rest, Stack, Callbacks, Opts);
value(<<$f, Rest/binary>>, Stack, Callbacks, Opts) ->
    fa(Rest, Stack, Callbacks, Opts);
value(<<$n, Rest/binary>>, Stack, Callbacks, Opts) ->
    nu(Rest, Stack, Callbacks, Opts);
value(<<?negative, Rest/binary>>, Stack, Callbacks, Opts) ->
    negative(Rest, Stack, Callbacks, Opts, "-");
value(<<?zero, Rest/binary>>, Stack, Callbacks, Opts) ->
    zero(Rest, Stack, Callbacks, Opts, "0");
value(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_nonzero(S) ->
    integer(Rest, Stack, Callbacks, Opts, [S]);
value(<<?start_object, Rest/binary>>, Stack, Callbacks, Opts) ->
    object(Rest, [key|Stack], fold(start_object, Callbacks), Opts);
value(<<?start_array, Rest/binary>>, Stack, Callbacks, Opts) ->
    array(Rest, [array|Stack], fold(start_array, Callbacks), Opts);
value(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> value(Resume, Stack, Callbacks, Opts) end);
value(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> value(Stream, Stack, Callbacks, Opts) end}.


colon(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) ->
    colon(Rest, Stack, Callbacks, Opts);
colon(<<?colon, Rest/binary>>, [key|Stack], Callbacks, Opts) ->
    value(Rest, [object|Stack], Callbacks, Opts);
colon(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> colon(Resume, Stack, Callbacks, Opts) end);
colon(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> colon(Stream, Stack, Callbacks, Opts) end}.


key(<<S, Rest/binary>>, Stack, Callbacks, Opts) when ?is_whitespace(S) ->
    key(Rest, Stack, Callbacks, Opts);        
key(<<?quote, Rest/binary>>, Stack, Callbacks, Opts) ->
    string(Rest, Stack, Callbacks, Opts, []);
key(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts)) ->
    maybe_comment(Rest, fun(Resume) -> key(Resume, Stack, Callbacks, Opts) end);
key(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> key(Stream, Stack, Callbacks, Opts) end}.


%% string has an additional parameter, an accumulator (Acc) used to hold the intermediate
%%   representation of the string being parsed. using a list of integers representing
%%   unicode codepoints is faster than constructing binaries, many of which will be
%%   converted back to lists by the user anyways.

string(<<?quote, Rest/binary>>, [key|_] = Stack, Callbacks, Opts, Acc) ->
    colon(Rest, Stack, fold({key, lists:reverse(Acc)}, Callbacks), Opts);
string(<<?quote, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold({string, lists:reverse(Acc)}, Callbacks), Opts);
string(<<?rsolidus, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    escape(Rest, Stack, Callbacks, Opts, Acc);   
string(<<S/utf8, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_noncontrol(S) ->
    string(Rest, Stack, Callbacks, Opts, [S] ++ Acc);        
string(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> string(Stream, Stack, Callbacks, Opts, Acc) end}.


%% only thing to note here is the additional accumulator passed to escaped_unicode used
%%   to hold the codepoint sequence. unescessary, but nicer than using the string 
%%   accumulator. 

escape(<<$b, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    string(Rest, Stack, Callbacks, Opts, "\b" ++ Acc);
escape(<<$f, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    string(Rest, Stack, Callbacks, Opts, "\f" ++ Acc);
escape(<<$n, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    string(Rest, Stack, Callbacks, Opts, "\n" ++ Acc);
escape(<<$r, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    string(Rest, Stack, Callbacks, Opts, "\r" ++ Acc);
escape(<<$t, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    string(Rest, Stack, Callbacks, Opts, "\t" ++ Acc);
escape(<<$u, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    escaped_unicode(Rest, Stack, Callbacks, Opts, Acc, []);      
escape(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) 
        when S =:= ?quote; S =:= ?solidus; S =:= ?rsolidus ->
    string(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
escape(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> escape(Stream, Stack, Callbacks, Opts, Acc) end}.


%% this code is ugly and unfortunate, but so is json's handling of escaped unicode
%%   codepoint sequences. if the ascii option is present, the sequence is converted
%%   to a codepoint and inserted into the string if it represents an ascii value. if 
%%   the codepoint option is present the sequence is converted and inserted as long
%%   as it represents a valid 16 bit integer value (this is where json's spec gets
%%   insane). any other option and the sequence is converted back to an erlang string
%%   and appended to the string in place.

escaped_unicode(<<D, Rest/binary>>, 
        Stack, 
        Callbacks, 
        ?escaped_unicode_to_ascii(Opts), 
        String, 
        [C, B, A]) 
            when ?is_hex(D) ->
    case erlang:list_to_integer([A, B, C, D], 16) of
        X when X < 127 ->
            string(Rest, Stack, Callbacks, Opts, [X] ++ String)
        ; _ ->
            string(Rest, Stack, Callbacks, Opts, [D, C, B, A, $u, ?rsolidus] ++ String)
    end;
escaped_unicode(<<D, Rest/binary>>, 
        Stack, 
        Callbacks, 
        ?escaped_unicode_to_codepoint(Opts), 
        String, 
        [C, B, A]) 
            when ?is_hex(D) ->
    string(Rest, Stack, Callbacks, Opts, [erlang:list_to_integer([A, B, C, D], 16)] ++ String);
escaped_unicode(<<D, Rest/binary>>, Stack, Callbacks, Opts, String, [C, B, A]) when ?is_hex(D) ->
    string(Rest, Stack, Callbacks, Opts, [D, C, B, A, $u, ?rsolidus] ++ String);
escaped_unicode(<<S, Rest/binary>>, Stack, Callbacks, Opts, String, Acc) when ?is_hex(S) ->
    escaped_unicode(Rest, Stack, Callbacks, Opts, String, [S] ++ Acc);
escaped_unicode(<<>>, Stack, Callbacks, Opts, String, Acc) ->
    {incomplete, fun(Stream) -> escaped_unicode(Stream, Stack, Callbacks, Opts, String, Acc) end}.


%% like strings, numbers are collected in an intermediate accumulator before
%%   being emitted to the callback handler. no processing of numbers is done in
%%   process, it's left for the user, though there are convenience functions to
%%   convert them into erlang floats/integers in jsx_utils.erl.

%% TODO: actually write that jsx_utils.erl module mentioned above...

negative(<<$0, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    zero(Rest, Stack, Callbacks, Opts, "0" ++ Acc);
negative(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_nonzero(S) ->
    integer(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
negative(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> negative(Stream, Stack, Callbacks, Opts, Acc) end}.


zero(<<?end_object, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_object, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
zero(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_array, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
zero(<<?comma, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    key(Rest, [key|Stack], fold({number, lists:reverse(Acc)}, Callbacks), Opts);
zero(<<?comma, Rest/binary>>, [array|_] = Stack, Callbacks, Opts, Acc) ->
    value(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
zero(<<?decimalpoint, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    fraction(Rest, Stack, Callbacks, Opts, [?decimalpoint] ++ Acc);
zero(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_whitespace(S) ->
    maybe_done(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
zero(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts), Acc) ->
    maybe_comment(Rest, fun(Resume) -> zero(Resume, Stack, Callbacks, Opts, Acc) end);
zero(<<>>, [], Callbacks, Opts, Acc) ->
    {fold(end_of_stream, fold({number, lists:reverse(Acc)}, Callbacks)), 
        fun(Stream) -> zero(Stream, [], Callbacks, Opts, Acc) end};
zero(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> zero(Stream, Stack, Callbacks, Opts, Acc) end}.


integer(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_nonzero(S) ->
    integer(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
integer(<<?end_object, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_object, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
integer(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_array, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
integer(<<?comma, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    key(Rest, [key|Stack], fold({number, lists:reverse(Acc)}, Callbacks), Opts);
integer(<<?comma, Rest/binary>>, [array|_] = Stack, Callbacks, Opts, Acc) ->
    value(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
integer(<<?decimalpoint, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    fraction(Rest, Stack, Callbacks, Opts, [?decimalpoint] ++ Acc);
integer(<<?zero, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    integer(Rest, Stack, Callbacks, Opts, [?zero] ++ Acc);
integer(<<$e, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    e(Rest, Stack, Callbacks, Opts, "e" ++ Acc);
integer(<<$E, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    e(Rest, Stack, Callbacks, Opts, "e" ++ Acc);
integer(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_whitespace(S) ->
    maybe_done(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
integer(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts), Acc) ->
    maybe_comment(Rest, fun(Resume) -> integer(Resume, Stack, Callbacks, Opts, Acc) end);
integer(<<>>, [], Callbacks, Opts, Acc) ->
    {fold(end_of_stream, fold({number, lists:reverse(Acc)}, Callbacks)), 
        fun(Stream) -> integer(Stream, [], Callbacks, Opts, Acc) end};
integer(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> integer(Stream, Stack, Callbacks, Opts, Acc) end}.

fraction(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_nonzero(S) ->
    fraction(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
fraction(<<?end_object, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_object, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
fraction(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_array, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
fraction(<<?comma, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    key(Rest, [key|Stack], fold({number, lists:reverse(Acc)}, Callbacks), Opts);
fraction(<<?comma, Rest/binary>>, [array|_] = Stack, Callbacks, Opts, Acc) ->
    value(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
fraction(<<?zero, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    fraction(Rest, Stack, Callbacks, Opts, [?zero] ++ Acc);
fraction(<<$e, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    e(Rest, Stack, Callbacks, Opts, "e" ++ Acc);
fraction(<<$E, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    e(Rest, Stack, Callbacks, Opts, "e" ++ Acc);
fraction(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_whitespace(S) ->
    maybe_done(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
fraction(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts), Acc) ->
    maybe_comment(Rest, fun(Resume) -> fraction(Resume, Stack, Callbacks, Opts, Acc) end);
fraction(<<>>, [], Callbacks, Opts, Acc) ->
    {fold(end_of_stream, fold({number, lists:reverse(Acc)}, Callbacks)), 
        fun(Stream) -> fraction(Stream, [], Callbacks, Opts, Acc) end};
fraction(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> fraction(Stream, Stack, Callbacks, Opts, Acc) end}.


e(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when S =:= ?zero; ?is_nonzero(S) ->
    exp(Rest, Stack, Callbacks, Opts, [S] ++ Acc);   
e(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when S =:= ?positive; S =:= ?negative ->
    ex(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
e(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> e(Stream, Stack, Callbacks, Opts, Acc) end}.


ex(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when S =:= ?zero; ?is_nonzero(S) ->
    exp(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
ex(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> ex(Stream, Stack, Callbacks, Opts, Acc) end}.


exp(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_nonzero(S) ->
    exp(Rest, Stack, Callbacks, Opts, [S] ++ Acc);
exp(<<?end_object, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_object, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
exp(<<?end_array, Rest/binary>>, [array|Stack], Callbacks, Opts, Acc) ->
    maybe_done(Rest, Stack, fold(end_array, fold({number, lists:reverse(Acc)}, Callbacks)), Opts);
exp(<<?comma, Rest/binary>>, [object|Stack], Callbacks, Opts, Acc) ->
    key(Rest, [key|Stack], fold({number, lists:reverse(Acc)}, Callbacks), Opts);
exp(<<?comma, Rest/binary>>, [array|_] = Stack, Callbacks, Opts, Acc) ->
    value(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
exp(<<?zero, Rest/binary>>, Stack, Callbacks, Opts, Acc) ->
    exp(Rest, Stack, Callbacks, Opts, [?zero] ++ Acc);
exp(<<?solidus, Rest/binary>>, Stack, Callbacks, ?comments_true(Opts), Acc) ->
    maybe_comment(Rest, fun(Resume) -> exp(Resume, Stack, Callbacks, Opts, Acc) end);
exp(<<S, Rest/binary>>, Stack, Callbacks, Opts, Acc) when ?is_whitespace(S) ->
    maybe_done(Rest, Stack, fold({number, lists:reverse(Acc)}, Callbacks), Opts);
exp(<<>>, [], Callbacks, Opts, Acc) ->
    {fold(end_of_stream, fold({number, lists:reverse(Acc)}, Callbacks)), 
        fun(Stream) -> exp(Stream, [], Callbacks, Opts, Acc) end};
exp(<<>>, Stack, Callbacks, Opts, Acc) ->
    {incomplete, fun(Stream) -> exp(Stream, Stack, Callbacks, Opts, Acc) end}.


tr(<<$r, Rest/binary>>, Stack, Callbacks, Opts) ->
    tru(Rest, Stack, Callbacks, Opts);
tr(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> tr(Stream, Stack, Callbacks, Opts) end}.


tru(<<$u, Rest/binary>>, Stack, Callbacks, Opts) ->
    true(Rest, Stack, Callbacks, Opts);
tru(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> tru(Stream, Stack, Callbacks, Opts) end}.


true(<<$e, Rest/binary>>, Stack, Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold({literal, true}, Callbacks), Opts);
true(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> true(Stream, Stack, Callbacks, Opts) end}.


fa(<<$a, Rest/binary>>, Stack, Callbacks, Opts) ->
    fal(Rest, Stack, Callbacks, Opts);
fa(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> fa(Stream, Stack, Callbacks, Opts) end}.


fal(<<$l, Rest/binary>>, Stack, Callbacks, Opts) ->
    fals(Rest, Stack, Callbacks, Opts);
fal(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> fal(Stream, Stack, Callbacks, Opts) end}.


fals(<<$s, Rest/binary>>, Stack, Callbacks, Opts) ->
    false(Rest, Stack, Callbacks, Opts);
fals(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> fals(Stream, Stack, Callbacks, Opts) end}.


false(<<$e, Rest/binary>>, Stack, Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold({literal, false}, Callbacks), Opts);
false(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> false(Stream, Stack, Callbacks, Opts) end}.


nu(<<$u, Rest/binary>>, Stack, Callbacks, Opts) ->
    nul(Rest, Stack, Callbacks, Opts);
nu(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> nu(Stream, Stack, Callbacks, Opts) end}.


nul(<<$l, Rest/binary>>, Stack, Callbacks, Opts) ->
    null(Rest, Stack, Callbacks, Opts);
nul(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> nul(Stream, Stack, Callbacks, Opts) end}.


null(<<$l, Rest/binary>>, Stack, Callbacks, Opts) ->
    maybe_done(Rest, Stack, fold({literal, null}, Callbacks), Opts);
null(<<>>, Stack, Callbacks, Opts) ->
    {incomplete, fun(Stream) -> null(Stream, Stack, Callbacks, Opts) end}.    


%% comments are c style, /* blah blah */ and are STRONGLY discouraged. any unicode
%%   character is valid in a comment, except, obviously the */ sequence which ends
%%   the comment. they're implemented as a closure called when the comment ends that
%%   returns execution to the point where the comment began. comments are not 
%%   recorded in any way, simply parsed.    

maybe_comment(<<?star, Rest/binary>>, Resume) ->
    comment(Rest, Resume);
maybe_comment(<<>>, Resume) ->
    {incomplete, fun(Stream) -> maybe_comment(Stream, Resume) end}.


comment(<<?star, Rest/binary>>, Resume) ->
    maybe_comment_done(Rest, Resume);
comment(<<_/utf8, Rest/binary>>, Resume) ->
    comment(Rest, Resume);
comment(<<>>, Resume) ->
    {incomplete, fun(Stream) -> comment(Stream, Resume) end}.


maybe_comment_done(<<?solidus, Rest/binary>>, Resume) ->
    Resume(Rest);
maybe_comment_done(<<>>, Resume) ->
    {incomplete, fun(Stream) -> maybe_comment_done(Stream, Resume) end}.


%% callbacks to our handler are roughly equivalent to a fold over the events, incremental
%%   rather than all at once.    

fold(end_of_stream, {F, State}) ->
    F(end_of_stream, State);
fold(Event, {F, State}) when is_function(F) ->
    {F, F(Event, State)}.


