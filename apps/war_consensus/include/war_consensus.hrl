%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Records and macros for consensus app
%%% @end
%%%-------------------------------------------------------------------

%% Consensus application name
-define(APPLICATION, consensus).

%% rop = Reconfiguration operation
-record(rop, {
          %% Type of operation determine what has to be done
          type,

          %% Has data about the request
          data,

          %% {Client-PID, Client-Cmd-Ref}
          client=undefined
}).

%% Types in consensus app
-type ballot() :: {integer(), integer(), node()}.
-type slot() :: integer().
-type proposal() :: #rop{} | term().
-type pvalue() :: {ballot(), slot(), proposal()}.
-type lease() :: {tuple(), integer()}.

%% Registered names of consensus cluster actors
-define(LEADER, war_consensus_leader).
-define(REPLICA, war_consensus_replica).
-define(ACCEPTOR, war_consensus_acceptor).
-define(CLIENT, war_consensus_client).

%% Consensus Messenger
-define(SYNC_MSG(Target, Msg), war_consensus_msngr:sync(Target, Msg)).
-define(ASYNC_MSG(Target, Msg), war_consensus_msngr:async(Target, Msg)).

%% Default lease time for master node
-define(LEASE_TIME, 5000). % Master lease, 5s

%% Unique identifier for node
-define(SELF_NODE, node()).

%% Default renew lease time for master node
%% Note: Leader may get the master_adopted message before replica has a
%% chance to update local state. Keep this in mind when deciding renew time
%% Needs to be reduced has too long message queues
-define(RENEW_LEASE_TIME, 4800). % Master lease renew after 4.8s

%% Time window before lease expiry we ignore master requests
%% To be tuned as per clock drift rate
-define(MIN_LEASE, 10). % In milli seconds, 10ms


