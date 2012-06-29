%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Utility functions
%%% @end
%%%
%%% @since : 01 June 2012
%%% @end
%%%-------------------------------------------------------------------
-module(server_util).

%% -----------------------------------------------------------------
%% Public interface
%% -----------------------------------------------------------------
-export([get_type/1, get_clientid/1]).

%% -----------------------------------------------------------------
%% Include files and private macros
%% -----------------------------------------------------------------
-include_lib("util/include/common.hrl").

%% -----------------------------------------------------------------
%% Public functions
%% -----------------------------------------------------------------

%%-------------------------------------------------------------------
%% @doc
%% Get the type for the given command
%%-------------------------------------------------------------------
-spec get_type(atom()) -> read | write.
get_type(Cmd) ->
    case Cmd of
        get ->
            read;
        set ->
            write;
        del ->
            write
    end.

%%-------------------------------------------------------------------
%% @doc
%% Get client id from the operation
%%-------------------------------------------------------------------
-spec get_clientid(#dop{}) -> pid().
get_clientid(#dop{client=Client}) ->
    Client.