-module(war_db_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("war_util/include/war_common.hrl").

%%-------------------------------------------------------------------
%% setup code
%%-------------------------------------------------------------------
apps() ->
    [compiler, syntax_tools, lager, war_db].

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
    Backend = war_util_conf:get(backend, ?APP),

    case Backend of
        war_db_ets_backend ->
            ?assertEqual(pong, war_db:ping()),

            Keys = keys(),
            Vals = vals(),

            % General test
            insert_mult(Keys, Vals),

            DBVals = get_mult(Keys),
            ?assertEqual(Vals, DBVals),

            delete_mult(Keys),
            DDBVals = get_mult(Keys),
            ?assertNotEqual(Vals, DDBVals),

            % SetNX test
            ResultSetnx1 = war_db:x([setnx, a, b]),
            ?assertEqual({ok, success}, ResultSetnx1),
            ResultSetnx2 = war_db:x([setnx, a, b]),
            ?assertEqual({ok, not_set}, ResultSetnx2),

            % Reset test
            insert_mult(Keys, Vals),
            war_db:reset(),
            ResetDBVals = get_mult(Keys),
            ?assertNotEqual(Vals, ResetDBVals),

            % SETEX test
            ResultSetex1 = war_db:x([setex, 1, x, y]),
            ?assertEqual({ok, success}, ResultSetex1),
            timer:sleep(2000),
            ResultSetex2 = war_db:x([get, x]),
            ?assertEqual({ok, not_found}, ResultSetex2),

            % SETENX test
            ResultSetenx1 = war_db:x([setenx, 1, a, b]),
            ?assertEqual({ok, success}, ResultSetenx1),
            ResultSetenx2 = war_db:x([setenx, 1, a, c]),
            ?assertEqual({ok, not_set}, ResultSetenx2),
            timer:sleep(500),
            ResultSetenx3 = war_db:x([setenx, 1, a, b]),
            ?assertEqual({ok, success}, ResultSetenx3),
            timer:sleep(1000),
            ResultSetenx4 = war_db:x([get, a]),
            ?assertEqual({ok, b}, ResultSetenx4),
            timer:sleep(500),
            ResultSetenx5 = war_db:x([get, a]),
            ?assertEqual({ok, not_found}, ResultSetenx5),

            % Backup test
            insert_mult(Keys, Vals),
            File = "./tmp-db-test",
            war_db:backup(File),
            {Result, _ResultData} = file:read_file_info(File),
            ?assertEqual(ok, Result),

            % Clean table and restore from file
            war_db:reset(),
            war_db:restore(File),
            RestoreDBVals = get_mult(Keys),
            ?assertEqual(Vals, RestoreDBVals),

            file:delete(File);
        _ ->
            %% TODO: Write tests for redis backend
            ok
    end.

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
    war_db:x([set, Key, Val]),
    insert_mult(KTail, VTail).


get_mult(Keys) ->
    lists:reverse(get_mult(Keys, [])).

get_mult([], Acc) ->
    Acc;
get_mult([Key | Tail], Acc) ->
    {ok, Val} = war_db:x([get, Key]),
    get_mult(Tail, [Val | Acc]).

delete_mult([]) ->
    ok;
delete_mult([Key | Tail]) ->
    war_db:x([del, Key]),
    delete_mult(Tail).
