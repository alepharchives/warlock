%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Consensus Leader
%%%
%%% Paxos leader
%%%
%%% @end
%%%
%%% @since : 06 June 2012
%%% @end
%%%-------------------------------------------------------------------
-module(consensus_leader).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% --------------------------------------------------------------------
%% Include files and macros
%% -------------------------------------------------------------------
-include_lib("util/include/common.hrl").
-include("consensus.hrl").

-define(SELF, self()).
-define(SELF_NODE, node()).
-define(FIRST_BALLOT, {0, ?SELF}).
%% When the leader is preempted => there is a leader with higher ballot. In
%% order to allow that leader to progress, we can wait for below time.
%% Should ideally be
%% http://en.wikipedia.org/wiki/Additive_increase/multiplicative_decrease
-define(BACKOFF_TIME, 50).  % In milli seconds

-record(state, {
            % Monotonically increasing unique ballot number
            ballot_num = ?FIRST_BALLOT,

            % State of the leader
            active = false,

            % A map of slot numbers to proposals in the form of a set
            % At any time, there is at most one entry per slot number in the set
            proposals = util_ht:new()
}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% Initialize gen_server
%% ------------------------------------------------------------------
init([]) ->
    ?LDEBUG("Starting " ++ erlang:atom_to_list(?MODULE)),

    %% Start a scout if no master is running
    check_master_start_scout(?FIRST_BALLOT),

    {ok, #state{}}.

%% --------------------------------------------------------------------
%% ------------------------------------------------------------------
%% gen_server:handle_call/3
%% ------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% ------------------------------------------------------------------
%% gen_server:handle_cast/2
%% ------------------------------------------------------------------
%% propse request from replica
handle_cast({propose, {Slot, Proposal}},
            #state{proposals = Proposals,
                   active = Active,
                   ballot_num = Ballot} = State) ->
    ?LDEBUG("LEA ~p::Received message ~p", [self(), {propose, {Slot, Proposal}}]),
    % Add the proposal if we do not have a command for the proposed spot
    case util_ht:get(Slot, Proposals) of
        not_found ->
            util_ht:set(Slot, Proposal, Proposals),
            case Active of
                true ->
                    PValue = {Ballot, Slot, Proposal},
                    consensus_commander_sup:create({?SELF, PValue});
                false ->
                    ok
            end;
        _Proposal ->
            ok
    end,
    {noreply, State};
%% adopted message sent by a scout,this message signifies that the current
%% ballot number ballot num has been adopted by a majority of acceptors
%% Note: The adopted ballot_num has to match current ballot_num!
handle_cast({adopted, {CurrBallot, PValues}},
            #state{proposals = Proposals,
                   ballot_num = CurrBallot} = State) ->
    ?LDEBUG("LEA ~p::Received message ~p", [self(),
                                            {adopted, {CurrBallot, PValues}}]),

    %% Now that the ballot is accepted, make self as the master
    spawn_master_commander(CurrBallot),

    % Get all the proposals in PValues with max ballot number and update our
    % proposals with this data
    Pmax = pmax(PValues),
    intersect(Proposals, Pmax),

    {noreply, State};
%% master_adopted message sent by master_commander when everyone has accepted
%% this leader as their master
handle_cast({master_adopted, CurrBallot},
            #state{proposals = Proposals,
                   ballot_num = CurrBallot} = State) ->
    ?LDEBUG("LEA ~p::Received message ~p", [self(),
                                            {master_adopted, CurrBallot}]),

    % Set a timer to renew the lease
    erlang:send_after(get_renew_time(), ?SELF, spawn_master_commander),

    % Spawn a commander for every proposal
    spawn_commanders(CurrBallot, Proposals),
    {noreply, State#state{active = true}};
%% preempted message sent by either a scout or a commander, it means that some
%% acceptor has adopted some other ballot
handle_cast({preempted, ABallot}, #state{ballot_num = CurrBallot} = State) ->
    ?LDEBUG("LEA ~p::Received message ~p", [self(), {preempted, ABallot}]),

    % If the new ballot number is bigger, increase ballot number and scout for
    % the next adoption
    NewBallot = case consensus_util:ballot_greater(ABallot, CurrBallot) of
        true ->
            NextBallot = consensus_util:incr_ballot(CurrBallot, ABallot),
            erlang:send_after(?BACKOFF_TIME, ?SELF, spawn_scout),
            NextBallot;
        false ->
            CurrBallot
    end,
    {noreply, State#state{active = false, ballot_num = NewBallot}};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% ------------------------------------------------------------------
%% gen_server:handle_info/2
%% ------------------------------------------------------------------
handle_info(spawn_scout, #state{ballot_num=Ballot}=State) ->
    check_master_start_scout(Ballot),
    {noreply, State};
handle_info(spawn_master_commander, #state{ballot_num=Ballot}=State) ->
    spawn_master_commander(Ballot),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%% ------------------------------------------------------------------
%% gen_server:terminate/2
%% ------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% ------------------------------------------------------------------
%% gen_server:code_change/3
%% ------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
% TODO: Naive implementation!! Make it better!
pmax(PValues) ->
    PList = sets:to_list(PValues),
    PDict = dict:new(),
    NewPDict = pmax(PList, PDict),
    NewPList = lists:map(fun({Key, Value}) -> get_obj(Key, Value) end,
                             dict:to_list(NewPDict)),
    sets:from_list(NewPList).

pmax([], PDict) ->
    PDict;
pmax([PVal|PList], PDict) ->
    {Key, Val} = get_keyval(PVal),
    NewPDict = case dict:find(Key, PDict) of
        % We already have a proposal with a different ballot num
        {ok, AltVal} ->
            % Get one with max ballot num
            case Val > AltVal of
                true ->
                    dict:store(Key, Val, PDict);
                false ->
                    PDict
            end;
        % Its a new proposal for the specified ballot
        error ->
            dict:store(Key, Val, PDict)
    end,
    pmax(PList, NewPDict).

get_keyval({A, B, C}) ->
    {{B, C}, A}.

get_obj({B, C}, A) ->
    {A, B, C}.

% TODO: Try to make this faster
intersect(Proposals, MaxPValues) ->
    intersect_lst(Proposals, sets:to_list(MaxPValues)).

intersect_lst(_, []) ->
    ok;
intersect_lst(Proposals, [PVal|PList]) ->
    {_Ballot, Slot, Proposal} = PVal,
    util_ht:set(Slot, Proposal, Proposals),
    intersect_lst(Proposals, PList).

spawn_commanders(Ballot, Proposals) ->
    spawn_commanders_lst(Ballot, util_ht:to_list(Proposals)).

spawn_commanders_lst(_Ballot, []) ->
    ok;
spawn_commanders_lst(Ballot, [H|L]) ->
    {Slot, Proposal} = H,
    PValue = {Ballot, Slot, Proposal},
    consensus_commander_sup:create({?SELF, PValue}),
    spawn_commanders_lst(Ballot, L).

get_lease() ->
    {now(), ?LEASE_TIME}.

spawn_master_commander(Ballot) ->
    Proposal = #dop{type=write,
                    module=?STATE_MGR,
                    function=set_master,
                    args=[?SELF_NODE, get_lease()],
                    client=undefined
                   },
    PValue = {Ballot, ?MASTER_SLOT, Proposal},
    consensus_commander_sup:create({?SELF, PValue}).

% Start Scout only if we do not have a master with valid lease
check_master_start_scout(Ballot) ->
    LeaseTime = consensus_state:get_lease_validity(),
    case (LeaseTime > ?MIN_LEASE) andalso not consensus_state:is_master() of
        % Master is active, try to spawn scout after LeaseTime
        true ->
            erlang:send_after(LeaseTime, ?SELF, spawn_scout);
        false ->
            consensus_scout_sup:create({?SELF, Ballot})
    end.

% The time after which master leader should try to renew its lease
get_renew_time() ->
    LeaseTime = consensus_state:get_lease_validity(),
    RenewTime = LeaseTime - (10 * ?MIN_LEASE),
    case RenewTime > 0 of
        true ->
            RenewTime;
        false ->
            0
    end.

