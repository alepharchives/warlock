-module(db_test).

-include_lib("eunit/include/eunit.hrl").

%%-------------------------------------------------------------------
%% setup code
%%-------------------------------------------------------------------
apps() ->
    [db].

app_start() ->
    lists:foreach (fun (App) ->
                           case application:start (App) of
                               {error, {already_started, App}} -> ok;
                               ok -> ok;
                               Other ->
                                   erlang:error ({error,
                                                  {?MODULE, ?LINE,
                                                   'could not start',
                                                   App,
                                                   'reason was', Other}})
                           end
                   end,
                   apps ()),
    error_logger:tty(false).

app_stop(_) ->
    [ ?assertEqual(ok, application:stop(App)) || App <- lists:reverse(apps())],
    error_logger:tty(true).

%%-------------------------------------------------------------------
%% test code
%%-------------------------------------------------------------------

db_test_() ->
    {timeout, 60,
     {setup,
      fun app_start/0,
      fun app_stop/1,
      [
       ?_test(simple_run())
      ]
     }}.

simple_run() ->
    Keys = keys(),
    Vals = vals(),
    insert_mult(Keys, Vals),

    DBVals = get_mult(Keys),
    ?assertEqual(Vals, DBVals),

    delete_mult(Keys),
    DDBVals = get_mult(Keys),
    ?assertNotEqual(Vals, DDBVals).

%%-------------------------------------------------------------------
%% internal functions
%%-------------------------------------------------------------------
keys() ->
    [key, {bigger_term, {some_values, [1, 2, 3, {a, b}]}}, 1].

vals() ->
    [value, {big_term_val}, 2].

insert_mult([], []) ->
    ok;
insert_mult([Key | KTail], [Val | VTail]) ->
    db:set(Key, Val),
    insert_mult(KTail, VTail).


get_mult(Keys) ->
    lists:reverse(get_mult(Keys, [])).

get_mult([], Acc) ->
    Acc;
get_mult([Key | Tail], Acc) ->
    {ok, Val} = db:get(Key),
    get_mult(Tail, [Val | Acc]).

delete_mult([]) ->
    ok;
delete_mult([Key | Tail]) ->
    db:del(Key),
    delete_mult(Tail).