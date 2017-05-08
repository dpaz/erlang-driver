-module(driver_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1,loop/0,splitByDots/1]).
-include_lib("eunit/include/eunit.hrl").



start(_StartType, _StartArgs) ->
    try
      %If you are modifying the code comment the next line to show the exceptions
      error_logger:tty(false),
      loop()
    catch
      throw:{eofErr,_}->
        exit(normal)
    end.
stop(_State) ->
    ok.

loop()->
  StatusFatal = {<<"status">>,<<"fatal">>},
  EmptyAST = {<<"ast">>,[""]},
  try
    process()
  catch
    throw:{json,BadJSON} ->
        Json =jsx:encode([StatusFatal,{<<"errors">>,[BadJSON]},EmptyAST]),
        io:format("~s~n",[binary_to_list(Json)]);
    throw:{parse,BadParse} ->
        {_,_,ErrorAux} = BadParse,
        ErrStr = list_to_binary(lists:concat(["An error ocurred while parsing: ",lists:concat(ErrorAux)])),

        Json =jsx:encode([StatusFatal,{<<"errors">>,[ErrStr]},EmptyAST]),
        io:format("~s~n",[binary_to_list(Json)]);
    throw:{scan,BadScan} ->
        {_,_,ErrorAux} = BadScan,
        ErrStr = list_to_binary(lists:concat(["An error ocurred while scanning tokens: ",lists:concat(tuple_to_list(ErrorAux))])),

        Json =jsx:encode([StatusFatal,{<<"errors">>,[ErrStr]},EmptyAST]),
        io:format("~s~n",[binary_to_list(Json)]);
    throw:{eofErr,EOF} ->
        throw({eofErr,EOF});
    throw:_ ->
        Json =jsx:encode([StatusFatal,{<<"errors">>,[<<"Unexpected error">>]},EmptyAST]),
        io:format("~s~n",[binary_to_list(Json)])
  end,
  loop().

process() ->
    case io:get_line("") of
        eof ->
            EOF = {eofErr,<<"End of the file">>},
            throw(EOF);
        N ->
            Content = case  decode(N) of
              {ok,Res} -> Res;
              {error,BadJSON} ->
                  throw(BadJSON)
            end,
            TokExprList = tokenize(binary_to_list(Content)),
            {ok,ParseList} = parse(TokExprList),
            FormatParse = format(ParseList),
            JSON = jsx:encode([{<<"status">>,<<"ok">>},{<<"ast">>,FormatParse}]),
            io:format("~s~n",[binary_to_list(JSON)])
    end.

decode(InputSrt) ->
    SubS = string:substr(InputSrt,1,string:len(InputSrt)-1),
    case jsx:is_json(list_to_binary(SubS)) of
      true->Data= jsx:decode(list_to_binary(SubS)),
          case proplists:lookup(<<"content">>,Data) of
              none -> {error,{json,<<"Content propertie don't found in JSON input">>}};
              _ -> Content = proplists:get_value(<<"content">>,Data),
                  {ok,Content}
          end;
      false->
          {error,{json,<<"Input is not a valid JSON">>}}
    end.

tokenize(Content) ->
    TokExprList = case erl_scan:string(Content) of
      {ok,Tokens,_} ->
            splitByDots(Tokens);
      {error,BadScan,_}-> throw({scan,BadScan})
    end,
    TokExprList.

parse(ExprList) ->
    List = lists:foldl(fun (Expr,ParseList)->
      case parseExpr(Expr) of
        {ok,AST} -> lists:append(ParseList,AST);
        {error,BadParse} -> throw({parse,BadParse})
      end
    end,[],ExprList),
    {ok,List}.

parseExpr(Tokens) ->
    case erl_parse:parse_form(Tokens) of
        {ok,AbsForm} -> {ok,[AbsForm]};
        {error,_}->
            case erl_parse:parse_exprs(Tokens) of
                {ok,AbsForm} -> {ok,AbsForm};
                {error,BadParse} -> {error,BadParse}
            end
    end.

splitByDots(TokenList)->
    splitByDots(TokenList,[],[]).

splitByDots([H|T],Acc,Final)->
    if
      element(1,H) == dot ->
        SubList = [lists:append(Acc,[H])],
        splitByDots(T,[],lists:append(Final,SubList));
      true ->
        splitByDots(T,lists:append(Acc,[H]),Final)
    end;
splitByDots([],Acc,Final)->
    if
      length(Acc) == 0 ->
        Res = Final;
      true ->
        Res =lists:append(Final,[Acc])
    end,
    Res.

%% Format do a conversion of erlang tuples to list, also change strings to binaries
format(T) when is_list(T)->
    format(list_to_tuple(T));
format(T) ->
    format(T, tuple_size(T), []).

format(_, 0, Acc) ->
    Result = case io_lib:printable_unicode_list(Acc) of
        true -> list_to_binary(Acc);
        false -> Acc
    end,
    Result;
format(T, N, Acc) when is_tuple(element(N,T)) ->
    format(T, N-1, [format(element(N,T),tuple_size(element(N,T)),[])|Acc]);
format(T,N,Acc) when is_list(element(N,T)) ->
    Tuple = list_to_tuple(element(N,T)),
    format(T, N-1, [format(Tuple,tuple_size(Tuple),[])|Acc]);
format(T,N,Acc)->
    format(T,N-1,[element(N,T)|Acc]).



%%Tests
% Test are inside the same file because we need to test private functions
decode_test_()->
    {Status,_} = decode("{\"aaa\":\"bbbb\"}"),
    {Status2,_} = decode("adddkhfdlhfasf"),
    {Status3,_} = decode("{\"content\": \"hola\"}."),
    [?_assertEqual(error,Status),
    ?_assertEqual(error,Status2),
    ?_assertEqual(ok,Status3)].

parseExpr_test_()->
    {_,Tokens,_} = erl_scan:string("fun () -> hola."),
    {Status,_} = parseExpr(Tokens),
    {_,Tokens2,_} = erl_scan:string("-module(test)."),
    {Status2,_} = parseExpr(Tokens2),
    {_,Tokens3,_} = erl_scan:string("3+5-2"),
    {Status3,_} = parseExpr(Tokens3),
    {_,Tokens4,_} = erl_scan:string("io:format(\"blah~n\")."),
    {Status4,_} = parseExpr(Tokens4),
    {_,Tokens5,_} = erl_scan:string("3+5-2."),
    {Status5,_} = parseExpr(Tokens5),
    {_,Tokens6,_} = erl_scan:string("?MODULE."),
    {Status6,_} = parseExpr(Tokens6),
    [?_assertEqual(error,Status),
    ?_assertEqual(ok,Status2),
    ?_assertEqual(error,Status3),
    ?_assertEqual(ok,Status4),
    ?_assertEqual(ok,Status5),
    ?_assertEqual(error,Status6)].

format_test_()->
   [?_assert(format({a,b,c,{d,e}}) =:= [a,b,c,[d,e]]),
   ?_assert(format([a,b,c,{d,e}]) =:= [a,b,c,[d,e]]),
   ?_assert(format({{a,b,c},d,e}) =:= [[a,b,c],d,e]),
   ?_assert(format({a,b,c,[d,e]}) =:= [a,b,c,[d,e]]),
   ?_assert(format({{a},{b},[c],[d],{{f}}}) =:= [[a],[b],[c],[d],[[f]]]),
   ?_assert(format({"hello","world"})=:= [<<"hello">>,<<"world">>]),
   ?_assert(format({a,b,[c,"hello",{"world",["this","is","a","test"]}]})=:= [a,b,[c,<<"hello">>,[<<"world">>,[<<"this">>,<<"is">>,<<"a">>,<<"test">>]]]]),
   ?_assert(format({"hello",<<"world">>})=:= [<<"hello">>,<<"world">>])].

 splitByDots_test_()->
   String1 = "ok . ok . ok . ok",
   String2 = ". . . . ok",
   String3 = "ok",
   String4 = ".",
   {_,Tokens1,_} = erl_scan:string(String1),
   {_,Tokens2,_} = erl_scan:string(String2),
   {_,Tokens3,_} = erl_scan:string(String3),
   {_,Tokens4,_} = erl_scan:string(String4),
   Res1 = length(splitByDots(Tokens1)),
   Res2 = length(splitByDots(Tokens2)),
   Res3 = length(splitByDots(Tokens3)),
   Res4 = length(splitByDots(Tokens4)),
   [?_assertEqual(4,Res1),
   ?_assertEqual(5,Res2),
   ?_assertEqual(1,Res3),
   ?_assertEqual(1,Res4)].
