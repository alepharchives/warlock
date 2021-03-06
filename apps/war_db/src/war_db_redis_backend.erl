%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc DB Redis backend
%%%
%%% Backend implementation for Redis
%%% @end
%%%
%%% @since : 30 May 2012
%%% @end
%%%-------------------------------------------------------------------
-module(war_db_redis_backend).
-behavior(war_db_backend).

-include("war_db.hrl").

%% ------------------------------------------------------------------
%% Function Exports
%% ------------------------------------------------------------------
-export([start/0, start/1, ping/1, reset/1, backup/2, restore/2,
         x/2]).

%% ------------------------------------------------------------------
%% Function Definitions
%% ------------------------------------------------------------------
-spec start() -> {ok, #client{}}.
start() ->
    Options = war_util_conf:get(options, ?MODULE),
    {ok, C} = eredis:start_link(Options),
    {ok, #client{inst=C}}.

-spec start(term()) -> {ok, #client{}}.
start(Options) ->
    {ok, C} = eredis:start_link(Options),
    {ok, #client{inst=C}}.

-spec reset(Client::#client{}) -> {ok, #client{}}.
reset(#client{inst=C}) ->
    eredis:q(C, ["FLUSHDB"]).

%% FIXME: To be implemented
-spec backup(File::string(), Client::#client{}) -> ok | {error, _}.
backup(_File, #client{inst=_C}) ->
    ok.

%% FIXME: To be implemented
-spec restore(File::string(), Client::#client{}) -> {ok, success}.
restore(_File, #client{inst=_C}) ->
    ok.

-spec ping(Client::#client{}) -> ping | pang.
ping(#client{inst=C}) ->
    case eredis:q(C, ["PING"]) of
        "PONG" ->
            pong;
        _ ->
            pang
    end.

-spec x(Cmd::term(), Client::#client{}) -> term().
x(Cmd, #client{inst=C}) ->
    eredis:q(C, Cmd).
