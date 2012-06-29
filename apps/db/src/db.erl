%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc DB wrapper, interface for DB requests
%%%
%%% The DB module consists of a supervised worker that manages and runs
%%% commands on the specified backend
%%% @end
%%%
%%% @since : 30 May 2012
%%% @end
%%%-------------------------------------------------------------------
-module(db).

%% -----------------------------------------------------------------
%% Public interface
%% -----------------------------------------------------------------
-export([ping/0, reset/0, backup/1, restore/1,
         get/1, set/1, del/1]).

%% -----------------------------------------------------------------
%% Private macros
%% -----------------------------------------------------------------
-define(WORKER, db_worker).
-define(CALL_WORKER(Cmd), try gen_server:call(?WORKER, Cmd)
                          catch
                              exit:{timeout, _} -> {error, timeout}
                          end).

%% -----------------------------------------------------------------
%% Public functions
%% -----------------------------------------------------------------

%%-------------------------------------------------------------------
%% @doc
%% Check if DB is up.
%%-------------------------------------------------------------------
-spec ping() -> pong | pang.
ping() ->
    ?CALL_WORKER(ping).

%%-------------------------------------------------------------------
%% @doc
%% Cleans db by deleting all objects
%%-------------------------------------------------------------------
-spec reset() -> ok.
reset() ->
    ?CALL_WORKER(reset).

%%-------------------------------------------------------------------
%% @doc
%% Backup db to given file
%%-------------------------------------------------------------------
-spec backup(string()) -> ok.
backup(File) ->
    ?CALL_WORKER({backup, File}).

%%-------------------------------------------------------------------
%% @doc
%% Restores db from given file
%%-------------------------------------------------------------------
-spec restore(string()) -> ok.
restore(File) ->
    ?CALL_WORKER({restore, File}).

%%-------------------------------------------------------------------
%% @doc
%% Get a value from the DB.
%%-------------------------------------------------------------------
-spec get(term()) -> term().
get(Key) ->
    ?CALL_WORKER({get, Key}).

%%-------------------------------------------------------------------
%% @doc
%% Store an object in the database.
%%-------------------------------------------------------------------
-spec set(list()) -> {ok, success}.
set([Key, Value]) ->
    ?CALL_WORKER({set, {Key, Value}}).

%%-------------------------------------------------------------------
%% @doc
%% Deletes object with given key from the database.
%%-------------------------------------------------------------------
-spec del(term()) -> {ok, success}.
del(Key) ->
    ?CALL_WORKER({del, Key}).
