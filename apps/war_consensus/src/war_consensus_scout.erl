%%%-------------------------------------------------------------------
%%% @copyright
%%% @end
%%%-------------------------------------------------------------------
%%% @author Sukumar Yethadka <sukumar@thinkapi.com>
%%%
%%% @doc Consensus Scout
%%%
%%% Paxos scout
%%%
%%% @end
%%%
%%% @since : 05 June 2012
%%% @end
%%%-------------------------------------------------------------------
-module(war_consensus_scout).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/1, start/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% --------------------------------------------------------------------
%% Include files and macros
%% --------------------------------------------------------------------
-include_lib("war_util/include/war_common.hrl").
-include("war_consensus.hrl").

-record(state, {
            % The leader that spawned this commander
            leader,

            % Set of pvalues where
            % pvalue = {Ballot number, Slot number, Proposal}
            pvalues,

            % Ballot number
            ballot_num,

            % Number of acceptors that has agreed for this ballot
            votes = []
}).

-define(SELF, self()).
%% Time allowed for the scout to survive being idle
-define(TIMEOUT, 5000).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link({node(), pvalue()}) -> {error, _} | {ok, pid()}.
start_link({Leader, Ballot}) ->
    gen_server:start_link(?MODULE, [{Leader, Ballot}], [{timeout, ?TIMEOUT}]).

-spec start({node(), pvalue()}) -> {error, _} | {ok, pid()}.
start({Leader, Ballot}) ->
    gen_server:start(?MODULE, [{Leader, Ballot}], [{timeout, ?TIMEOUT}]).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% Initialize gen_server
%% ------------------------------------------------------------------
init([{Leader, Ballot}]) ->
    ?LDEBUG("Starting " ++ erlang:atom_to_list(?MODULE)),

    % Send a message to  all the acceptors and wait for their response
    Message = {p1a, {?SELF, Ballot}},
    ?ASYNC_MSG(acceptors, Message),
    {ok, #state{leader = Leader,
                ballot_num = Ballot,
                pvalues=war_util_ets_ht:new()}, ?TIMEOUT}.

%% ------------------------------------------------------------------
%% gen_server:handle_call/3
%% ------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% ------------------------------------------------------------------
%% gen_server:handle_cast/2
%% ------------------------------------------------------------------
%% phase 1 b message from some acceptor
handle_cast({p1b, {Acceptor, ABallot, APValues}},
            #state{ballot_num = CurrBallot,
                   votes = Votes,
                   leader = Leader,
                   pvalues = PValues} = State) ->
    ?LDEBUG("Received message ~p", [{p1b, {Acceptor, ABallot, APValues}}]),
    NewVotes = [Acceptor|Votes],
    case war_consensus_util:ballot_same(ABallot, CurrBallot) of
        true ->
            NewPValues = merge_pvalues(APValues, PValues),
            case war_consensus_util:is_majority(length(NewVotes)) of
                true ->
                    Message = {adopted, {ABallot, war_util_ets_ht:to_list(NewPValues)}},
                    ?ASYNC_MSG(Leader, Message),
                    {stop, normal, State};
                false ->
                    NewState = State#state{pvalues = NewPValues,
                                           votes = NewVotes},
                    {noreply, NewState, ?TIMEOUT}
            end;
        false ->
            % We have another ballot running. Since acceptor will not send any
            % ballot smaller than ours, inform leader and exit
            ?ASYNC_MSG(Leader, {preempted, ABallot}),
            {stop, normal, State}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

%% ------------------------------------------------------------------
%% gen_server:handle_info/2
%% ------------------------------------------------------------------
handle_info(timeout,#state{leader = Leader}=State) ->
    ?ASYNC_MSG(Leader, scout_timeout),
    {stop,normal,State};
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
%% Makes sure only the highest ballot for a slot exists
merge_pvalues([], PValues) ->
    PValues;
merge_pvalues([{Key, {Ballot, _Proposal}=Val} | APValues], PValues) ->
    PValue = war_util_ets_ht:get(Key, PValues),
    NewPValues = case PValue of
        % Object not in dict
        not_found ->
            war_util_ets_ht:set(Key, Val, PValues);
        {CBallot, _CProposal} ->
            case war_consensus_util:ballot_greater(Ballot, CBallot) of
                % New ballot is larger, replace current
                true ->
                    war_util_ets_ht:set(Key, Val, PValues);
                % Nothing to change
                false ->
                    PValues
            end
    end,
    merge_pvalues(APValues, NewPValues).