%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Consensus State
%%%
%%% Wraps the consensus state of the node. Uses ETS internally.
%%% @end
%%%
%%% @since : 04 June 2012
%%% @end
%%%-------------------------------------------------------------------
%% TODO: Write specs
-module(consensus_state).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([new/0, del/0,
         set_node_status/2, get_node_status/1,
         get_nodes/0, get_nodes/1, get_members/0,
         get_master/0, get_valid_master/0, set_master/2, is_master/0,
         get_lease/0
        ]).

%% --------------------------------------------------------------------
%% Include files and macros
%% --------------------------------------------------------------------
%% Default lease time for master node
-define(LEASE_TIME, 5000). % Master lease, 5s

%% Time window before lease expiry we disallow master requests
%% To be tuned as per clock drift rate
-define(MIN_LEASE, 100000). % In microseconds, 100ms

%% Default master for seed node
-define(INITIAL_MASTER, {node(), {erlang:now(), ?LEASE_TIME}}).

%% Initial status of the node
-define(INITIAL_STATUS, down).

%% Node's initial state
-define(INITIAL_SYSTEM_STATE, [
            %% Name of the current node
            {node, node()},

            %% Status of the current node. Start as down
            {status, ?INITIAL_STATUS},

            %% Status of all the connected nodes, including self
            {c_status, [{node(), ?INITIAL_STATUS}]},

            %% Master lease time
            {lease, {now(), 0}},

            %% Valid cluster members
            %% master, valid, join, down are disjoint

            %% Master node
            {master, [node()]},

            %% Valid cluster members
            {valid, []},

            %% Joining cluster members
            {join, []},

            %% Down cluster members
            {down, []}
]).

%% Name of the ets table
-define(TABLE, cons_state).

%% ------------------------------------------------------------------
%% Public functions
%% ------------------------------------------------------------------
new() ->
    ets:new(?TABLE, [set, named_table, public]),
    % Initialize the node state
    ets:insert(?TABLE, ?INITIAL_SYSTEM_STATE).

del() ->
    ets:delete(?TABLE).

%% Get status of a specific node in the cluster
get_node_status(Node) ->
    case lists:keyfind(Node, 1, get_state(c_status)) of
        {Node, Status} ->
            Status;
        _ ->
            undefined
    end.

%% Add a new node or update a node's cluster status
%% Makes sure master, valid, down, join are disjoint
set_node_status(Node, Status) when
  Status == master;
  Status == valid;
  Status == join;
  Status == down ->
    case get_node_status(Node) of
        undefined ->
            add_node(Node, Status);
        OldStatus ->
            update_node(Node, OldStatus, Status)
    end.

%% Get all nodes
get_nodes() ->
    [Node || {Node, _Status} <- get_state(c_status)].

%% Get a list of nodes specified
get_nodes(Type) when
  Type == valid;
  Type == master;
  Type == join;
  Type == down ->
    get_state(Type).

%% Members of the clusters who can vote
get_members() ->
    get_nodes(master) ++ get_nodes(valid).

%% Get the master node
get_master() ->
    get_state(master).

%% Get lease time
get_lease() ->
    get_state(lease).

%% Get master while making sure it still has the lease
get_valid_master() ->
    case is_lease_valid(get_lease()) of
        true ->
            get_master();
        false ->
            undefined
    end.

%% Set a new master node
set_master(Node, Lease) ->
    set_node_status(Node, master),
    set_state(lease, Lease).

%% Check if the current node is the master
is_master() ->
    get_master() =:= [get_state(node)].

%% ------------------------------------------------------------------
%% Internal functions
%% ------------------------------------------------------------------
get_state(Key) ->
    [{Key, Val}] = ets:lookup(?TABLE, Key),
    Val.

set_state(Key, Value) ->
    ets:insert(?TABLE, {Key, Value}).

add_node(Node, Status) ->
    % Update main nodes list
    set_state(c_status, [{Node, Status} | get_state(c_status)]),
    % Update list based in Status
    set_state(Status, [Node | get_state(Status)]).

update_node(Node, OldStatus, NewStatus) ->
    % Update main nodes list
    set_state(c_status, lists:keyreplace(Node, 1, get_state(c_status),
                                         {Node, NewStatus})),
    % Update list based in OldStatus
    set_state(OldStatus, get_state(OldStatus) -- [Node]),
    % Update list based in NewStatus
    set_state(NewStatus, get_state(NewStatus) ++ [Node]).

is_lease_valid(Lease) ->
    timer:now_diff(erlang:now(), Lease) > ?MIN_LEASE.

