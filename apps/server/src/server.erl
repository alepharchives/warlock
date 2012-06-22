%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Server wrapper, interface for handling server requests
%%%
%%% The Server module consists of a supervised worker that runs
%%% commands on the local DB as per consensus
%%%
%%% How a request is handled
%%% 1. A command is constructed based on the request (command_worker)
%%% 2. Command is passed on to the consensus module
%%% 3. Consensus module gets agreement based on the client
%%% 4. The callback function (part of command) is called by consensus module
%%% 5. If reply required, the master replies
%%%
%%% @end
%%%
%%% @since : 01 June 2012
%%% @end
%%%-------------------------------------------------------------------
%% TODO: Write specs
-module(server).

%% -----------------------------------------------------------------
%% Public interface
%% -----------------------------------------------------------------
-export([ping/0, ping_service/0, ping_backend/0,
         get/1, set/2, del/1]).

%% -----------------------------------------------------------------
%% Private macros
%% -----------------------------------------------------------------

%% -----------------------------------------------------------------
%% Public functions
%% -----------------------------------------------------------------

%%-------------------------------------------------------------------
%% @doc
%% Check if this server is up.
%%-------------------------------------------------------------------
-spec ping() -> pong | pang.
ping() ->
    pong.

%%-------------------------------------------------------------------
%% @doc
%% Check if the service(cluster) is up.
%%-------------------------------------------------------------------
-spec ping_service() -> pong | pang.
ping_service() ->
    % TODO: Check implementation
    consensus:ping().

%%-------------------------------------------------------------------
%% @doc
%% Check if the backend for this server is up.
%%-------------------------------------------------------------------
-spec ping_backend() -> pong | pang.
ping_backend() ->
    db:ping().

%%-------------------------------------------------------------------
%% @doc
%% Get a value from the DB.
%%-------------------------------------------------------------------
get(Key) ->
    spawncall_worker(get, Key).

%%-------------------------------------------------------------------
%% @doc
%% Store an object in the database.
%%-------------------------------------------------------------------
set(Key, Value) ->
    spawncall_worker(set, {Key, Value}).

%%-------------------------------------------------------------------
%% @doc
%% Deletes object with given key from the database.
%%-------------------------------------------------------------------
del(Key) ->
    spawncall_worker(del, Key).

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% TODO: Check if there is a usecase where we need cast worker
spawncall_worker(Cmd, Data) ->
    {ok, Worker} = server_command_worker:start_link(),
    try gen_server:call(Worker, {request, {Cmd, Data}})
    catch
        exit:{timeout, _} -> {error, timeout}
    end.
