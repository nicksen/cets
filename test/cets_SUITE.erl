%% Code conventions:
%% - Use PeerNum for peer pids (i.e. Peer2, Peer3...)
%% - Use NodeNum for nodes (i.e. Node2, Node3...)
%% - Node1 is the test node
%% - Use assertException macro to test errors
%% - Tests should cleanup after themself (we use repeat_until_any_fail to ensure this)
%% - Use repeat_until_any_fail=100 to ensure new tests are not flaky
-module(cets_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/logger.hrl").

-compile([export_all, nowarn_export_all]).

-import(cets_test_peer, [
    disconnect_node/2
]).

-import(cets_test_rpc, [
    rpc/4,
    insert/3,
    insert_many/3,
    delete/3,
    delete_request/3,
    delete_many/3,
    dump/2,
    other_nodes/2,
    join/4
]).

-import(cets_test_setup, [
    start/2,
    start_local/1,
    start_local/2,
    make_name/1,
    make_name/2,
    lock_name/1,
    given_two_joined_tables/1,
    given_two_joined_tables/2,
    given_3_servers/1,
    make_process/0
]).

-import(cets_test_wait, [
    wait_for_down/1,
    wait_for_unpaused/3,
    wait_for_join_ref_to_match/2,
    wait_till_test_stage/2,
    wait_till_message_queue_length/2
]).

-import(cets_test_receive, [
    receive_message/1,
    receive_message_with_arg/1
]).

-import(cets_test_helper, [
    assert_unique/1,
    set_join_ref/2
]).

suite() ->
    cets_test_setup:suite().

all() ->
    [
        {group, cets},
        %% To improve the code coverage we need to test with logging disabled
        %% More info: https://github.com/erlang/otp/issues/7531
        {group, cets_no_log},
        {group, cets_seq},
        {group, cets_seq_no_log}
    ].

groups() ->
    %% Cases should have unique names, because we name CETS servers based on case names
    [
        {cets, [parallel, {repeat_until_any_fail, 3}],
            assert_unique(cases() ++ only_for_logger_cases())},
        {cets_no_log, [parallel], assert_unique(cases())},
        %% These tests actually simulate a netsplit on the distribution level.
        %% Though, global's prevent_overlapping_partitions option starts kicking
        %% all nodes from the cluster, so we have to be careful not to break other cases.
        %% Setting prevent_overlapping_partitions=false on ct5 helps.
        {cets_seq, [sequence, {repeat_until_any_fail, 2}], assert_unique(seq_cases())},
        {cets_seq_no_log, [sequence, {repeat_until_any_fail, 2}],
            assert_unique(cets_seq_no_log_cases())}
    ].

cases() ->
    [
        start_link_inits_and_accepts_records,
        inserted_records_could_be_read_back,
        insert_many_with_one_record,
        insert_many_with_two_records,
        delete_works,
        delete_many_works,
        inserted_records_could_be_read_back_from_replicated_table,
        insert_new_works,
        insert_new_works_with_table_name,
        insert_new_works_when_leader_is_back,
        insert_new_when_new_leader_has_joined,
        insert_new_when_new_leader_has_joined_duplicate,
        insert_new_when_inconsistent_minimal,
        insert_new_when_inconsistent,
        insert_new_is_retried_when_leader_is_reelected,
        insert_new_fails_if_the_leader_dies,
        insert_new_fails_if_the_local_server_is_dead,
        insert_new_or_lookup_works,
        insert_serial_works,
        insert_serial_overwrites_data,
        insert_overwrites_data_inconsistently,
        insert_new_does_not_overwrite_data,
        insert_serial_overwrites_data_consistently,
        insert_serial_works_when_leader_is_back,
        insert_serial_blocks_when_leader_is_not_back,
        leader_is_the_same_in_metadata_after_join,
        send_dump_contains_already_added_servers,
        test_multinode,
        test_multinode_remote_insert,
        node_list_is_correct,
        get_nodes_request,
        test_locally,
        handle_down_is_called,
        handle_down_gets_correct_leader_arg_when_leader_goes_down,
        events_are_applied_in_the_correct_order_after_unpause,
        pause_multiple_times,
        unpause_twice,
        unpause_if_pause_owner_crashes,
        write_returns_if_remote_server_crashes,
        ack_process_stops_correctly,
        ack_process_handles_unknown_remote_server,
        ack_process_handles_unknown_from,
        ack_calling_add_when_server_list_is_empty_is_not_allowed,
        ping_all_using_name_works,
        insert_many_request,
        insert_many_requests,
        insert_many_requests_timeouts,
        insert_into_bag,
        delete_from_bag,
        delete_many_from_bag,
        delete_request_from_bag,
        delete_request_many_from_bag,
        insert_into_bag_is_replicated,
        insert_into_keypos_table,
        table_name_works,
        info_contains_opts,
        info_contains_pause_monitors,
        info_contains_other_servers,
        check_could_reach_each_other_fails,
        unknown_down_message_is_ignored,
        unknown_message_is_ignored,
        unknown_cast_message_is_ignored,
        unknown_message_is_ignored_in_ack_process,
        unknown_cast_message_is_ignored_in_ack_process,
        unknown_call_returns_error_from_ack_process,
        code_change_returns_ok,
        code_change_returns_ok_for_ack,
        run_spawn_forwards_errors,
        run_tracked_failed,
        run_tracked_logged,
        long_call_to_unknown_name_throws_pid_not_found,
        send_leader_op_throws_noproc,
        pinfo_returns_value,
        pinfo_returns_undefined,
        ignore_send_dump_received_when_unpaused,
        ignore_send_dump_received_when_paused_with_another_pause_ref,
        pause_on_remote_node_returns_if_monitor_process_dies
    ].

only_for_logger_cases() ->
    [
        run_tracked_logged_check_logger,
        long_call_fails_because_linked_process_dies,
        pause_owner_crashed_is_logged,
        pause_owner_crashed_is_not_logged_if_reason_is_normal,
        atom_error_is_logged_in_tracked,
        shutdown_reason_is_not_logged_in_tracked,
        other_reason_is_logged_in_tracked,
        nested_calls_errors_are_logged_once_with_tuple_reason,
        nested_calls_errors_are_logged_once_with_map_reason,
        send_dump_received_when_unpaused_is_logged
    ].

seq_cases() ->
    [
        send_check_servers_is_called_before_last_server_got_dump,
        remote_ops_are_not_sent_before_last_server_got_dump,
        pause_on_remote_node_crashes
    ].

cets_seq_no_log_cases() ->
    [
        send_check_servers_is_called_before_last_server_got_dump,
        remote_ops_are_not_sent_before_last_server_got_dump
    ].

init_per_suite(Config) ->
    cets_test_setup:init_cleanup_table(),
    cets_test_peer:start([ct2, ct3, ct4, ct5, ct6, ct7], Config).

end_per_suite(Config) ->
    cets_test_setup:remove_cleanup_table(),
    cets_test_peer:stop(Config),
    Config.

init_per_group(Group, Config) when Group == cets_seq_no_log; Group == cets_no_log ->
    [ok = logger:set_module_level(M, none) || M <- log_modules()],
    Config;
init_per_group(_Group, Config) ->
    Config.

end_per_group(Group, Config) when Group == cets_seq_no_log; Group == cets_no_log ->
    [ok = logger:unset_module_level(M) || M <- log_modules()],
    Config;
end_per_group(_Group, Config) ->
    Config.

init_per_testcase(Name, Config) ->
    init_per_testcase_generic(Name, Config).

init_per_testcase_generic(Name, Config) ->
    [{testcase, Name} | Config].

end_per_testcase(_, _Config) ->
    cets_test_setup:wait_for_cleanup(),
    ok.

%% Modules that use a multiline LOG_ macro
log_modules() ->
    [cets, cets_call, cets_long, cets_join, cets_discovery].

start_link_inits_and_accepts_records(Config) ->
    Tab = make_name(Config),
    cets_test_setup:start_link_local(Tab),
    cets:insert(Tab, {alice, 32}),
    [{alice, 32}] = ets:lookup(Tab, alice).

inserted_records_could_be_read_back(Config) ->
    Tab = make_name(Config),
    start_local(Tab),
    cets:insert(Tab, {alice, 32}),
    [{alice, 32}] = ets:lookup(Tab, alice).

insert_many_with_one_record(Config) ->
    Tab = make_name(Config),
    start_local(Tab),
    cets:insert_many(Tab, [{alice, 32}]),
    [{alice, 32}] = ets:lookup(Tab, alice).

insert_many_with_two_records(Config) ->
    Tab = make_name(Config),
    start_local(Tab),
    cets:insert_many(Tab, [{alice, 32}, {bob, 55}]),
    [{alice, 32}, {bob, 55}] = ets:tab2list(Tab).

delete_works(Config) ->
    Tab = make_name(Config),
    start_local(Tab),
    cets:insert(Tab, {alice, 32}),
    cets:delete(Tab, alice),
    [] = ets:lookup(Tab, alice).

delete_many_works(Config) ->
    Tab = make_name(Config, 1),
    start_local(Tab),
    cets:insert(Tab, {alice, 32}),
    cets:delete_many(Tab, [alice]),
    [] = ets:lookup(Tab, alice).

inserted_records_could_be_read_back_from_replicated_table(Config) ->
    #{tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    cets:insert(Tab1, {alice, 32}),
    [{alice, 32}] = ets:lookup(Tab2, alice).

insert_new_works(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    true = cets:insert_new(Pid1, {alice, 32}),
    %% Duplicate found
    false = cets:insert_new(Pid1, {alice, 32}),
    false = cets:insert_new(Pid1, {alice, 33}),
    false = cets:insert_new(Pid2, {alice, 33}).

insert_new_works_with_table_name(Config) ->
    #{tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    true = cets:insert_new(Tab1, {alice, 32}),
    false = cets:insert_new(Tab2, {alice, 32}).

insert_new_works_when_leader_is_back(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    NotLeader = not_leader(Pid1, Pid2, Leader),
    cets:set_leader(Leader, false),
    proc_lib:spawn(fun() ->
        timer:sleep(100),
        cets:set_leader(Leader, true)
    end),
    true = cets:insert_new(NotLeader, {alice, 32}).

insert_new_when_new_leader_has_joined(Config) ->
    #{pids := Pids, tabs := Tabs} = given_3_servers(Config),
    %% Processes do not always start in order (i.e. sort them now)
    [Pid1, Pid2, Pid3] = lists:sort(Pids),
    %% Join first network segment
    ok = cets_join:join(lock_name(Config), #{}, Pid1, Pid2),
    %% Pause insert into the first segment
    Leader = cets:get_leader(Pid1),
    PauseMon = cets:pause(Leader),
    proc_lib:spawn(fun() ->
        timer:sleep(100),
        ok = cets_join:join(lock_name(Config), #{}, Pid1, Pid3),
        cets:unpause(Leader, PauseMon)
    end),
    %% Inserted by Pid3
    true = cets:insert_new(Pid1, {alice, 32}),
    Res = [{alice, 32}],
    [Res = cets:dump(T) || T <- Tabs].

%% Checks that the handle_wrong_leader is called
insert_new_when_new_leader_has_joined_duplicate(Config) ->
    #{pids := Pids, tabs := Tabs} = given_3_servers(Config),
    %% Processes do not always start in order (i.e. sort them now)
    [Pid1, Pid2, Pid3] = lists:sort(Pids),
    %% Join first network segment
    ok = cets_join:join(lock_name(Config), #{}, Pid1, Pid2),
    %% Put record into the second network segment
    true = cets:insert_new(Pid3, {alice, 33}),
    %% Pause insert into the first segment
    Leader = cets:get_leader(Pid1),
    PauseMon = cets:pause(Leader),
    proc_lib:spawn(fun() ->
        timer:sleep(100),
        ok = cets_join:join(insert_new_lock5, #{}, Pid1, Pid3),
        cets:unpause(Leader, PauseMon)
    end),
    %% Checked and ignored by Pid3
    false = cets:insert_new(Pid1, {alice, 32}),
    Res = [{alice, 33}],
    [Res = cets:dump(T) || T <- Tabs].

insert_new_when_inconsistent_minimal(Config) ->
    #{pids := [Pid1, _Pid2]} = given_two_joined_tables(Config),
    true = cets:insert_new(Pid1, {alice, 33}),
    false = cets:insert_new(Pid1, {alice, 55}).

%% Rare case when tables contain different data
%% (the developer should try to avoid the manual removal of data if possible)
insert_new_when_inconsistent(Config) ->
    #{pids := [Pid1, Pid2]} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    NotLeader = not_leader(Pid1, Pid2, Leader),
    {ok, LeaderTab} = cets:table_name(Leader),
    {ok, NotLeaderTab} = cets:table_name(NotLeader),
    true = cets:insert_new(NotLeader, {alice, 33}),
    true = cets:insert_new(Leader, {bob, 40}),
    %% Introduce inconsistency
    ets:delete(NotLeaderTab, alice),
    ets:delete(LeaderTab, bob),
    false = cets:insert_new(NotLeader, {alice, 55}),
    true = cets:insert_new(Leader, {bob, 66}),
    [{bob, 40}] = cets:dump(NotLeaderTab),
    [{alice, 33}, {bob, 66}] = cets:dump(LeaderTab).

insert_new_is_retried_when_leader_is_reelected(Config) ->
    Me = self(),
    F = fun(X) ->
        put(test_stage, detected),
        Me ! {wrong_leader_detected, X}
    end,
    {ok, Pid1} = start_local(make_name(Config, 1), #{handle_wrong_leader => F}),
    {ok, Pid2} = start_local(make_name(Config, 2), #{handle_wrong_leader => F}),
    ok = cets_join:join(lock_name(Config), #{}, Pid1, Pid2),
    Leader = cets:get_leader(Pid1),
    NotLeader = not_leader(Pid1, Pid2, Leader),
    %% Ask process to reject all the leader operations
    cets:set_leader(Leader, false),
    proc_lib:spawn_link(fun() ->
        wait_till_test_stage(Leader, detected),
        %% Fix the leader, so it can process our insert_new call
        cets:set_leader(Leader, true)
    end),
    %% This function would block, because Leader process would reject the operation
    %% Until we call cets:set_leader(Leader, true)
    true = cets:insert_new(NotLeader, {alice, 32}),
    %% Check that we actually use retry logic
    %% Check that handle_wrong_leader callback function is called at least once
    receive
        {wrong_leader_detected, Info} ->
            ct:pal("wrong_leader_detected ~p", [Info])
    after 5000 ->
        ct:fail(wrong_leader_not_detected)
    end,
    %% Check that data is written (i.e. retry works)
    {ok, [{alice, 32}]} = cets:remote_dump(Pid1),
    {ok, [{alice, 32}]} = cets:remote_dump(Pid2).

%% We could retry automatically, but in this case return value from insert_new
%% could be incorrect.
%% If you want to make insert_new more robust:
%% - handle cets_down exception
%% - call insert_new one more time
%% - read the data back using ets:lookup to ensure it is your record written
insert_new_fails_if_the_leader_dies(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    cets:pause(Pid2),
    proc_lib:spawn(fun() ->
        timer:sleep(100),
        exit(Pid2, kill)
    end),
    try
        cets:insert_new(Pid1, {alice, 32})
    catch
        exit:{killed, _} -> ok
    end.

insert_new_fails_if_the_local_server_is_dead(_Config) ->
    Pid = stopped_pid(),
    try
        cets:insert_new(Pid, {alice, 32})
    catch
        exit:{noproc, {gen_server, call, _}} -> ok
    end.

insert_new_or_lookup_works(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    Rec1 = {alice, 32},
    Rec2 = {alice, 33},
    {true, [Rec1]} = cets:insert_new_or_lookup(Pid1, Rec1),
    %% Duplicate found
    {false, [Rec1]} = cets:insert_new_or_lookup(Pid1, Rec1),
    {false, [Rec1]} = cets:insert_new_or_lookup(Pid2, Rec1),
    {false, [Rec1]} = cets:insert_new_or_lookup(Pid1, Rec2),
    {false, [Rec1]} = cets:insert_new_or_lookup(Pid2, Rec2).

insert_serial_works(Config) ->
    #{pid1 := Pid1, tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    ok = cets:insert_serial(Pid1, {a, 1}),
    [{a, 1}] = cets:dump(Tab1),
    [{a, 1}] = cets:dump(Tab2).

insert_serial_overwrites_data(Config) ->
    #{pid1 := Pid1, tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    ok = cets:insert_serial(Pid1, {a, 1}),
    ok = cets:insert_serial(Pid1, {a, 2}),
    [{a, 2}] = cets:dump(Tab1),
    [{a, 2}] = cets:dump(Tab2).

%% Test case when both servers receive a request to update the same key.
%% Compare with insert_serial_overwrites_data_consistently
%% and insert_new_does_not_overwrite_data.
insert_overwrites_data_inconsistently(Config) ->
    Me = self(),
    #{pid1 := Pid1, pid2 := Pid2, tab1 := Tab1, tab2 := Tab2} =
        given_two_joined_tables(Config),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid1, fun(State) ->
            Me ! replacing_state1,
            receive_message(continue_test),
            State
        end)
    end),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid2, fun(State) ->
            Me ! replacing_state2,
            receive_message(continue_test),
            State
        end)
    end),
    receive_message(replacing_state1),
    receive_message(replacing_state2),
    %% Insert at the same time
    proc_lib:spawn_link(fun() ->
        ok = cets:insert(Tab1, {a, 1}),
        Me ! inserted1
    end),
    proc_lib:spawn_link(fun() ->
        ok = cets:insert(Tab2, {a, 2}),
        Me ! inserted2
    end),
    %% Wait till got an insert op in the queue
    wait_till_message_queue_length(Pid1, 1),
    wait_till_message_queue_length(Pid2, 1),
    Pid1 ! continue_test,
    Pid2 ! continue_test,
    receive_message(inserted1),
    receive_message(inserted2),
    %% Different values due to a race condition
    [{a, 2}] = cets:dump(Tab1),
    [{a, 1}] = cets:dump(Tab2).

insert_new_does_not_overwrite_data(Config) ->
    Me = self(),
    #{pid1 := Pid1, pid2 := Pid2, tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid1, fun(State) ->
            Me ! replacing_state1,
            receive_message(continue_test),
            State
        end)
    end),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid2, fun(State) ->
            Me ! replacing_state2,
            receive_message(continue_test),
            State
        end)
    end),
    receive_message(replacing_state1),
    receive_message(replacing_state2),
    %% Insert at the same time
    proc_lib:spawn_link(fun() ->
        true = cets:insert_new(Tab1, {a, 1}),
        Me ! inserted1
    end),
    wait_till_message_queue_length(Leader, 1),
    proc_lib:spawn_link(fun() ->
        false = cets:insert_new(Tab2, {a, 2}),
        Me ! inserted2
    end),
    %% Wait till got the insert ops in the queue.
    %% Leader gets both requests.
    wait_till_message_queue_length(Leader, 2),
    Pid1 ! continue_test,
    Pid2 ! continue_test,
    receive_message(inserted1),
    receive_message(inserted2),
    [{a, 1}] = cets:dump(Tab1),
    [{a, 1}] = cets:dump(Tab2).

%% We have to use table names instead of pids to insert, because
%% get_leader is an ETS call, if ServerRef is a table name.
%% And get_leader is a gen_server call, if ServerRef is a pid.
insert_serial_overwrites_data_consistently(Config) ->
    Me = self(),
    #{pid1 := Pid1, pid2 := Pid2, tab1 := Tab1, tab2 := Tab2} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid1, fun(State) ->
            Me ! replacing_state1,
            receive_message(continue_test),
            State
        end)
    end),
    proc_lib:spawn_link(fun() ->
        sys:replace_state(Pid2, fun(State) ->
            Me ! replacing_state2,
            receive_message(continue_test),
            State
        end)
    end),
    receive_message(replacing_state1),
    receive_message(replacing_state2),
    %% Insert at the same time
    proc_lib:spawn_link(fun() ->
        ok = cets:insert_serial(Tab1, {a, 1}),
        Me ! inserted1
    end),
    %% Ensure, that first insert comes before the second
    %% (just to get a predictable value. The value would be still
    %%  consistent in case first insert comes after the second).
    wait_till_message_queue_length(Leader, 1),
    proc_lib:spawn_link(fun() ->
        ok = cets:insert_serial(Tab2, {a, 2}),
        Me ! inserted2
    end),
    %% Wait till got the insert ops in the queue.
    %% Leader gets both requests.
    wait_till_message_queue_length(Leader, 2),
    Pid1 ! continue_test,
    Pid2 ! continue_test,
    receive_message(inserted1),
    receive_message(inserted2),
    [{a, 2}] = cets:dump(Tab1),
    [{a, 2}] = cets:dump(Tab2).

%% Similar to insert_new_works_when_leader_is_back
insert_serial_works_when_leader_is_back(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    NotLeader = not_leader(Pid1, Pid2, Leader),
    cets:set_leader(Leader, false),
    proc_lib:spawn(fun() ->
        timer:sleep(100),
        cets:set_leader(Leader, true)
    end),
    %% Blocks, until cets:set_leader sets leader back to true.
    ok = cets:insert_serial(NotLeader, {alice, 32}).

insert_serial_blocks_when_leader_is_not_back(Config) ->
    Me = self(),
    F = fun(X) ->
        put(test_stage, detected),
        Me ! {wrong_leader_detected, X}
    end,
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config, #{handle_wrong_leader => F}),
    Leader = cets:get_leader(Pid1),
    NotLeader = not_leader(Pid1, Pid2, Leader),
    cets:set_leader(Leader, false),
    InserterPid = proc_lib:spawn(fun() ->
        %% Will block indefinetely, because we set is_leader flag manually.
        ok = cets:insert_serial(NotLeader, {alice, 32})
    end),
    receive
        {wrong_leader_detected, Info} ->
            ct:log("wrong_leader_detected ~p", [Info])
    after 5000 ->
        ct:fail(wrong_leader_not_detected)
    end,
    %% Still alive and blocking
    pong = cets:ping(Pid1),
    pong = cets:ping(Pid2),
    ?assert(erlang:is_process_alive(InserterPid)).

leader_is_the_same_in_metadata_after_join(Config) ->
    #{tabs := [T1, T2], pids := [Pid1, Pid2]} = given_two_joined_tables(Config),
    Leader = cets:get_leader(Pid1),
    Leader = cets:get_leader(Pid2),
    Leader = cets_metadata:get(T1, leader),
    Leader = cets_metadata:get(T2, leader).

pause_owner_crashed_is_logged(Config) ->
    ct:timetrap({seconds, 6}),
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    {ok, Pid1} = start_local(make_name(Config, 1)),
    Me = self(),
    PausedByPid = proc_lib:spawn(fun() ->
        cets:pause(Pid1),
        Me ! paused,
        error(oops)
    end),
    %% Wait for unpausing before checking logs
    receive_message(paused),
    wait_for_unpaused(node(), Pid1, PausedByPid),
    [
        #{
            level := error,
            msg :=
                {report, #{
                    what := pause_owner_crashed,
                    reason := {oops, _}
                }}
        }
    ] =
        cets_test_log:receive_all_logs_from_pid(?FUNCTION_NAME, Pid1).

pause_owner_crashed_is_not_logged_if_reason_is_normal(Config) ->
    ct:timetrap({seconds, 6}),
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    {ok, Pid1} = start_local(make_name(Config, 1)),
    Me = self(),
    PausedByPid = proc_lib:spawn(fun() ->
        cets:pause(Pid1),
        Me ! paused
    end),
    %% Wait for unpausing before checking logs
    receive_message(paused),
    wait_for_unpaused(node(), Pid1, PausedByPid),
    [] = cets_test_log:receive_all_logs_from_pid(?FUNCTION_NAME, Pid1).

atom_error_is_logged_in_tracked(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    LogRef = make_ref(),
    F = fun() -> error(oops) end,
    ?assertException(
        error,
        {task_failed, oops, #{log_ref := LogRef}},
        cets_long:run_tracked(#{log_ref => LogRef}, F)
    ),
    [
        #{
            level := error,
            msg :=
                {report, #{
                    what := task_failed,
                    log_ref := LogRef,
                    reason := oops
                }}
        }
    ] =
        cets_test_log:receive_all_logs_with_log_ref(?FUNCTION_NAME, LogRef).

shutdown_reason_is_not_logged_in_tracked(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    Me = self(),
    LogRef = make_ref(),
    F = fun() ->
        Me ! ready,
        timer:sleep(infinity)
    end,
    Pid = proc_lib:spawn(fun() -> cets_long:run_tracked(#{log_ref => LogRef}, F) end),
    receive_message(ready),
    exit(Pid, shutdown),
    wait_for_down(Pid),
    [] = cets_test_log:receive_all_logs_with_log_ref(?FUNCTION_NAME, LogRef).

%% Complementary to shutdown_reason_is_not_logged_in_tracked
other_reason_is_logged_in_tracked(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    Me = self(),
    LogRef = make_ref(),
    F = fun() ->
        Me ! ready,
        timer:sleep(infinity)
    end,
    Pid = proc_lib:spawn(fun() -> cets_long:run_tracked(#{log_ref => LogRef}, F) end),
    receive_message(ready),
    exit(Pid, bad_stuff_happened),
    wait_for_down(Pid),
    [
        #{
            level := error,
            msg :=
                {report, #{
                    what := task_failed,
                    log_ref := LogRef,
                    reason := bad_stuff_happened
                }}
        }
    ] = cets_test_log:receive_all_logs_with_log_ref(?FUNCTION_NAME, LogRef).

nested_calls_errors_are_logged_once_with_tuple_reason(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    LogRef = make_ref(),
    F = fun() -> error({something_is_wrong, ?FUNCTION_NAME}) end,
    FF = fun() -> cets_long:run_tracked(#{log_ref => LogRef, task => subtask}, F) end,
    ?assertException(
        error,
        {task_failed, {something_is_wrong, nested_calls_errors_are_logged_once_with_tuple_reason},
            #{log_ref := LogRef}},
        cets_long:run_tracked(#{log_ref => LogRef, task => main}, FF)
    ),
    [
        #{
            level := error,
            msg :=
                {report, #{
                    what := task_failed,
                    log_ref := LogRef,
                    reason := {something_is_wrong, ?FUNCTION_NAME}
                }}
        }
    ] =
        cets_test_log:receive_all_logs_with_log_ref(?FUNCTION_NAME, LogRef).

nested_calls_errors_are_logged_once_with_map_reason(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    LogRef = make_ref(),
    F = fun() -> error(#{something_is_wrong => ?FUNCTION_NAME}) end,
    FF = fun() -> cets_long:run_tracked(#{log_ref => LogRef, task => subtask}, F) end,
    ?assertException(
        error,
        {task_failed,
            #{
                something_is_wrong :=
                    nested_calls_errors_are_logged_once_with_map_reason
            },
            #{log_ref := LogRef}},
        cets_long:run_tracked(#{log_ref => LogRef, task => main}, FF)
    ),
    [
        #{
            level := error,
            msg :=
                {report, #{
                    what := task_failed,
                    log_ref := LogRef,
                    reason := #{something_is_wrong := ?FUNCTION_NAME}
                }}
        }
    ] =
        cets_test_log:receive_all_logs_with_log_ref(?FUNCTION_NAME, LogRef).

send_dump_contains_already_added_servers(Config) ->
    %% Check that even if we have already added server in send_dump, nothing crashes
    {ok, Pid1} = start_local(make_name(Config, 1)),
    {ok, Pid2} = start_local(make_name(Config, 2)),
    ok = cets_join:join(lock_name(Config), #{}, Pid1, Pid2, #{}),
    PauseRef = cets:pause(Pid1),
    %% That should be called by cets_join module
    cets:send_dump(Pid1, [Pid2], make_ref(), PauseRef, [{1}]),
    cets:unpause(Pid1, PauseRef),
    {ok, [{1}]} = cets:remote_dump(Pid1).

ignore_send_dump_received_when_paused_with_another_pause_ref(Config) ->
    ignore_send_dump_received_when_unpaused([{extra_pause, true} | Config]).

send_dump_received_when_unpaused_is_logged(Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    ignore_send_dump_received_when_unpaused(Config),
    receive
        {log, ?FUNCTION_NAME, #{
            level := error,
            msg := {report, #{what := send_dump_received_when_unpaused}}
        }} ->
            ok
    after 5000 ->
        ct:fail(timeout)
    end.

ignore_send_dump_received_when_unpaused(Config) ->
    Self = self(),
    %% Check that even if we have already added server in send_dump, nothing crashes
    {ok, Pid1} = start_local(make_name(Config, 1)),
    {ok, Pid2} = start_local(make_name(Config, 2)),
    CheckPointF = fun
        ({before_send_dump, Pid}) when Pid == Pid1 ->
            #{pause_monitors := [PauseRef]} = cets:info(Pid1),
            cets:unpause(Pid1, PauseRef),
            case proplists:get_value(extra_pause, Config, false) of
                true ->
                    cets:pause(Pid1);
                false ->
                    ok
            end,
            ok;
        ({after_send_dump, Pid, Result}) when Pid == Pid1 ->
            Self ! {after_send_dump, Result},
            ok;
        (_) ->
            ok
    end,
    Lock = lock_name(Config),
    ok = cets_join:join(Lock, #{}, Pid1, Pid2, #{checkpoint_handler => CheckPointF}),
    ?assertEqual({error, ignored}, receive_message_with_arg(after_send_dump)),
    ok.

pause_on_remote_node_returns_if_monitor_process_dies(Config) ->
    JoinPid = make_process(),
    #{ct2 := Node2} = proplists:get_value(nodes, Config),
    AllPids = [rpc(Node2, cets_test_setup, make_process, [])],
    TestPid = proc_lib:spawn(fun() ->
        %% Would block
        cets_join:pause_on_remote_node(JoinPid, AllPids)
    end),
    cets_test_wait:wait_until(
        fun() ->
            case erlang:process_info(TestPid, monitors) of
                {monitors, [{process, MonitorProcess}]} -> is_pid(MonitorProcess);
                _ -> false
            end
        end,
        true
    ),
    {monitors, [{process, MonitorProcess}]} = erlang:process_info(TestPid, monitors),
    exit(MonitorProcess, killed),
    wait_for_down(TestPid).

pause_on_remote_node_crashes(Config) ->
    #{ct2 := Node2} = proplists:get_value(nodes, Config),
    Node1 = node(),
    Tab = make_name(Config),
    {ok, Pid1} = start(Node1, Tab),
    {ok, Pid2} = start(Node2, Tab),
    ok = rpc(Node2, cets_test_setup, mock_pause_on_remote_node_failing, []),
    try
        {error,
            {task_failed,
                {assert_all_ok, [
                    {Node2, {error, {exception, mock_pause_on_remote_node_failing, _}}}
                ]},
                #{}}} =
            cets_join:join(lock_name(Config), #{}, Pid1, Pid2, #{})
    after
        [cets_join] = rpc(Node2, meck, unload, [])
    end.

%% Happens when one node receives send_dump and loses connection with the node
%% that runs cets_join logic.
send_check_servers_is_called_before_last_server_got_dump(Config) ->
    Self = self(),
    %% For this test we need nodes with prevent_overlapping_partitions=false
    %% Otherwise disconnect_node would kick both CETS nodes
    #{ct6 := Peer6, ct7 := Peer7, ct5 := Peer5} = proplists:get_value(peers, Config),
    Tab = make_name(Config),
    Lock = lock_name(Config),
    {ok, Pid6} = start(Peer6, Tab),
    {ok, Pid7} = start(Peer7, Tab),
    CheckPointF = fun
        ({before_send_dump, Pid}) when Pid == Pid7 ->
            %% Node6 already got its dump
            disconnect_node(Peer6, node()),
            %% Wait for Pid6 to lose pause monitor from the join process
            wait_for_unpaused(Peer6, Pid6, self()),
            %% Wait for check_server to be send from Pid6 to Pid7
            rpc(Peer6, cets, ping_all, [Pid6]),
            Self ! before_send_dump7,
            ok;
        ({after_send_dump, Pid, Result}) when Pid == Pid7 ->
            Self ! {after_send_dump7, Result},
            ok;
        (_) ->
            ok
    end,
    JoinRef = make_ref(),
    ok = rpc(Peer5, cets_join, join, [
        Lock, #{}, Pid6, Pid7, #{join_ref => JoinRef, checkpoint_handler => CheckPointF}
    ]),
    receive_message(before_send_dump7),
    ?assertEqual(ok, receive_message_with_arg(after_send_dump7)),
    wait_for_join_ref_to_match(Pid6, JoinRef),
    wait_for_join_ref_to_match(Pid7, JoinRef),
    cets:ping_all(Pid6),
    cets:ping_all(Pid7),
    #{other_servers := OtherServers6} = Info6 = cets:info(Pid6),
    #{other_servers := OtherServers7} = Info7 = cets:info(Pid7),
    ?assertEqual([Pid7], OtherServers6, Info6),
    ?assertEqual([Pid6], OtherServers7, Info7),
    ok.

remote_ops_are_not_sent_before_last_server_got_dump(Config) ->
    %% For this test we need nodes with prevent_overlapping_partitions=false
    %% Otherwise disconnect_node would kick both CETS nodes
    #{ct6 := Peer6, ct7 := Peer7, ct5 := Peer5} = proplists:get_value(peers, Config),
    Tab = make_name(Config),
    Lock = lock_name(Config),
    {ok, Pid6} = start(Peer6, Tab),
    {ok, Pid7} = start(Peer7, Tab),
    insert(Peer6, Tab, {a, 1}),
    CheckPointF = fun
        ({before_send_dump, Pid}) when Pid == Pid7 ->
            %% Node6 already got its dump.
            %% Use disconnect_node to lose connection between the coordinator and Pid6.
            %% But Pid6 would still be paused by cets_join:pause_on_remote_node/2 from Node7.
            disconnect_node(Peer6, node()),
            %% We cannot use blocking cets:delete/2 here because we would deadlock.
            %% Use delete_request/2 instead and wait till
            %% at least the local node precessed the operation.
            delete_request(Peer6, Tab, a),
            rpc(Peer6, cets, ping, [Tab]),
            ok;
        (_) ->
            ok
    end,
    JoinRef = make_ref(),
    ok = rpc(Peer5, cets_join, join, [
        Lock, #{}, Pid6, Pid7, #{join_ref => JoinRef, checkpoint_handler => CheckPointF}
    ]),
    cets:ping_all(Pid6),
    cets:ping_all(Pid7),
    {ok, []} = cets:remote_dump(Pid6),
    {ok, []} = cets:remote_dump(Pid7),
    ok.

test_multinode(Config) ->
    Node1 = node(),
    #{ct2 := Peer2, ct3 := Peer3, ct4 := Peer4} = proplists:get_value(peers, Config),
    Tab = make_name(Config),
    {ok, Pid1} = start(Node1, Tab),
    {ok, Pid2} = start(Peer2, Tab),
    {ok, Pid3} = start(Peer3, Tab),
    {ok, Pid4} = start(Peer4, Tab),
    ok = join(Node1, Tab, Pid1, Pid3),
    ok = join(Peer2, Tab, Pid2, Pid4),
    insert(Node1, Tab, {a}),
    insert(Peer2, Tab, {b}),
    insert(Peer3, Tab, {c}),
    insert(Peer4, Tab, {d}),
    [{a}, {c}] = dump(Node1, Tab),
    [{b}, {d}] = dump(Peer2, Tab),
    ok = join(Node1, Tab, Pid2, Pid1),
    [{a}, {b}, {c}, {d}] = dump(Node1, Tab),
    [{a}, {b}, {c}, {d}] = dump(Peer2, Tab),
    insert(Node1, Tab, {f}),
    insert(Peer4, Tab, {e}),
    Same = fun(X) ->
        X = dump(Node1, Tab),
        X = dump(Peer2, Tab),
        X = dump(Peer3, Tab),
        X = dump(Peer4, Tab),
        ok
    end,
    Same([{a}, {b}, {c}, {d}, {e}, {f}]),
    delete(Node1, Tab, e),
    Same([{a}, {b}, {c}, {d}, {f}]),
    delete(Peer4, Tab, a),
    Same([{b}, {c}, {d}, {f}]),
    %% Bulk operations are supported
    insert_many(Peer4, Tab, [{m}, {a}, {n}, {y}]),
    Same([{a}, {b}, {c}, {d}, {f}, {m}, {n}, {y}]),
    delete_many(Peer4, Tab, [a, n]),
    Same([{b}, {c}, {d}, {f}, {m}, {y}]),
    ok.

test_multinode_remote_insert(Config) ->
    Tab = make_name(Config),
    #{ct2 := Node2, ct3 := Node3} = proplists:get_value(nodes, Config),
    {ok, Pid2} = start(Node2, Tab),
    {ok, Pid3} = start(Node3, Tab),
    ok = join(Node2, Tab, Pid2, Pid3),
    %% Ensure it is a remote node
    true = node() =/= node(Pid2),
    %% Insert without calling rpc module
    cets:insert(Pid2, {a}),
    [{a}] = dump(Node3, Tab).

node_list_is_correct(Config) ->
    Node1 = node(),
    #{ct2 := Node2, ct3 := Node3, ct4 := Node4} = proplists:get_value(nodes, Config),
    Tab = make_name(Config),
    {ok, Pid1} = start(Node1, Tab),
    {ok, Pid2} = start(Node2, Tab),
    {ok, Pid3} = start(Node3, Tab),
    {ok, Pid4} = start(Node4, Tab),
    ok = join(Node1, Tab, Pid1, Pid3),
    ok = join(Node2, Tab, Pid2, Pid4),
    ok = join(Node1, Tab, Pid1, Pid2),
    [Node2, Node3, Node4] = other_nodes(Node1, Tab),
    [Node1, Node3, Node4] = other_nodes(Node2, Tab),
    [Node1, Node2, Node4] = other_nodes(Node3, Tab),
    [Node1, Node2, Node3] = other_nodes(Node4, Tab),
    ok.

get_nodes_request(Config) ->
    #{ct2 := Node2, ct3 := Node3, ct4 := Node4} = proplists:get_value(nodes, Config),
    Tab = make_name(Config),
    {ok, Pid2} = start(Node2, Tab),
    {ok, Pid3} = start(Node3, Tab),
    {ok, Pid4} = start(Node4, Tab),
    ok = cets_join:join(lock_name(Config), #{}, Pid2, Pid3),
    ok = cets_join:join(lock_name(Config), #{}, Pid2, Pid4),
    Res = cets:wait_response(cets:get_nodes_request(Pid2), 5000),
    ?assertEqual({reply, [Node2, Node3, Node4]}, Res).

test_locally(Config) ->
    #{tabs := [T1, T2]} = given_two_joined_tables(Config),
    cets:insert(T1, {1}),
    cets:insert(T1, {1}),
    cets:insert(T2, {2}),
    D = cets:dump(T1),
    D = cets:dump(T2).

handle_down_is_called(Config) ->
    Parent = self(),
    DownFn = fun(#{remote_pid := _RemotePid, table := _Tab}) ->
        Parent ! down_called
    end,
    {ok, Pid1} = start_local(make_name(Config, 1), #{handle_down => DownFn}),
    {ok, Pid2} = start_local(make_name(Config, 2), #{}),
    ok = cets_join:join(lock_name(Config), #{table => [d1, d2]}, Pid1, Pid2),
    exit(Pid2, oops),
    receive
        down_called -> ok
    after 5000 -> ct:fail(timeout)
    end.

handle_down_gets_correct_leader_arg_when_leader_goes_down(Config) ->
    Parent = self(),
    DownFn = fun(#{is_leader := IsLeader}) ->
        Parent ! {is_leader_arg, IsLeader}
    end,
    {ok, Pid1} = start_local(make_name(Config, 1), #{handle_down => DownFn}),
    {ok, Pid2} = start_local(make_name(Config, 2), #{handle_down => DownFn}),
    ok = cets_join:join(lock_name(Config), #{table => [d1, d2]}, Pid1, Pid2),
    Leader = cets:get_leader(Pid1),
    exit(Leader, oops),
    ?assertEqual(true, receive_message_with_arg(is_leader_arg)).

events_are_applied_in_the_correct_order_after_unpause(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T),
    PauseMon = cets:pause(Pid),
    R1 = cets:insert_request(T, {1}),
    R2 = cets:delete_request(T, 1),
    cets:delete_request(T, 2),
    cets:insert_request(T, {2}),
    cets:insert_request(T, {3}),
    cets:insert_request(T, {4}),
    cets:insert_request(T, {5}),
    R3 = cets:insert_request(T, [{6}, {7}]),
    R4 = cets:delete_many_request(T, [5, 4]),
    [] = lists:sort(cets:dump(T)),
    ok = cets:unpause(Pid, PauseMon),
    [{reply, ok} = cets:wait_response(R, 5000) || R <- [R1, R2, R3, R4]],
    [{2}, {3}, {6}, {7}] = lists:sort(cets:dump(T)).

pause_multiple_times(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T),
    PauseMon1 = cets:pause(Pid),
    PauseMon2 = cets:pause(Pid),
    Ref1 = cets:insert_request(Pid, {1}),
    Ref2 = cets:insert_request(Pid, {2}),
    %% No records yet, even after pong
    [] = cets:dump(T),
    ok = cets:unpause(Pid, PauseMon1),
    pong = cets:ping(Pid),
    %% No records yet, even after pong
    [] = cets:dump(T),
    ok = cets:unpause(Pid, PauseMon2),
    pong = cets:ping(Pid),
    {reply, ok} = cets:wait_response(Ref1, 5000),
    {reply, ok} = cets:wait_response(Ref2, 5000),
    [{1}, {2}] = lists:sort(cets:dump(T)).

unpause_twice(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T),
    PauseMon = cets:pause(Pid),
    ok = cets:unpause(Pid, PauseMon),
    {error, unknown_pause_monitor} = cets:unpause(Pid, PauseMon).

unpause_if_pause_owner_crashes(Config) ->
    Me = self(),
    {ok, Pid} = start_local(make_name(Config)),
    spawn_monitor(fun() ->
        cets:pause(Pid),
        Me ! pause_called,
        error(wow)
    end),
    receive
        pause_called -> ok
    after 5000 -> ct:fail(timeout)
    end,
    %% Check that the server is unpaused
    ok = cets:insert(Pid, {1}).

write_returns_if_remote_server_crashes(Config) ->
    #{tab1 := Tab1, pid2 := Pid2} = given_two_joined_tables(Config),
    sys:suspend(Pid2),
    R = cets:insert_request(Tab1, {1}),
    exit(Pid2, oops),
    {reply, ok} = cets:wait_response(R, 5000).

ack_process_stops_correctly(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    #{ack_pid := AckPid} = cets:info(Pid),
    AckMon = monitor(process, AckPid),
    cets:stop(Pid),
    receive
        {'DOWN', AckMon, process, AckPid, normal} -> ok
    after 5000 -> ct:fail(timeout)
    end.

ack_process_handles_unknown_remote_server(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    sys:suspend(Pid2),
    #{ack_pid := AckPid} = cets:info(Pid1),
    [Pid2] = cets:other_pids(Pid1),
    RandomPid = proc_lib:spawn(fun() -> ok end),
    %% Request returns immediately,
    %% we actually need to send a ping to ensure it has been processed locally
    R = cets:insert_request(Pid1, {1}),
    pong = cets:ping(Pid1),
    %% Extract From value
    [{servers, _}, {From, [Pid2]}] = maps:to_list(sys:get_state(AckPid)),
    cets_ack:ack(AckPid, From, RandomPid),
    sys:resume(Pid2),
    %% Ack process still works fine
    {reply, ok} = cets:wait_response(R, 5000).

ack_process_handles_unknown_from(Config) ->
    #{pid1 := Pid1} = given_two_joined_tables(Config),
    #{ack_pid := AckPid} = cets:info(Pid1),
    R = cets:insert_request(Pid1, {1}),
    From = {self(), make_ref()},
    cets_ack:ack(AckPid, From, self()),
    %% Ack process still works fine
    {reply, ok} = cets:wait_response(R, 5000).

ack_calling_add_when_server_list_is_empty_is_not_allowed(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    Mon = monitor(process, Pid),
    #{ack_pid := AckPid} = cets:info(Pid),
    FakeFrom = {self(), make_ref()},
    cets_ack:add(AckPid, FakeFrom),
    %% cets server would never send an add message in the single node configuration
    %% (cets_ack is not used if there is only one node,
    %% so cets module calls gen_server:reply and skips the replication)
    receive
        {'DOWN', Mon, process, Pid, Reason} ->
            {unexpected_add_msg, _} = Reason
    after 5000 -> ct:fail(timeout)
    end.

ping_all_using_name_works(Config) ->
    T = make_name(Config),
    {ok, _Pid1} = start_local(T),
    cets:ping_all(T).

insert_many_request(Config) ->
    Tab = make_name(Config),
    {ok, Pid} = start_local(Tab),
    R = cets:insert_many_request(Pid, [{a}, {b}]),
    {reply, ok} = cets:wait_response(R, 5000),
    [{a}, {b}] = ets:tab2list(Tab).

insert_many_requests(Config) ->
    Tab1 = make_name(Config, 1),
    Tab2 = make_name(Config, 2),
    {ok, Pid1} = start_local(Tab1),
    {ok, Pid2} = start_local(Tab2),
    R1 = cets:insert_many_request(Pid1, [{a}, {b}]),
    R2 = cets:insert_many_request(Pid2, [{a}, {b}]),
    [{reply, ok}, {reply, ok}] = cets:wait_responses([R1, R2], 5000).

insert_many_requests_timeouts(Config) ->
    Tab1 = make_name(Config, 1),
    Tab2 = make_name(Config, 2),
    {ok, Pid1} = start_local(Tab1),
    {ok, Pid2} = start_local(Tab2),
    cets:pause(Pid1),
    R1 = cets:insert_many_request(Pid1, [{a}, {b}]),
    R2 = cets:insert_many_request(Pid2, [{a}, {b}]),
    %% We assume 100 milliseconds is more than enough to insert one record
    %% (it is time sensitive testcase though)
    [timeout, {reply, ok}] = cets:wait_responses([R1, R2], 100).

insert_into_bag(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{type => bag}),
    cets:insert(T, {1, 1}),
    cets:insert(T, {1, 1}),
    cets:insert(T, {1, 2}),
    [{1, 1}, {1, 2}] = lists:sort(cets:dump(T)).

delete_from_bag(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{type => bag}),
    cets:insert_many(T, [{1, 1}, {1, 2}]),
    cets:delete_object(T, {1, 2}),
    [{1, 1}] = cets:dump(T).

delete_many_from_bag(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{type => bag}),
    cets:insert_many(T, [{1, 1}, {1, 2}, {1, 3}, {1, 5}, {2, 3}]),
    cets:delete_objects(T, [{1, 2}, {1, 5}, {1, 4}]),
    [{1, 1}, {1, 3}, {2, 3}] = lists:sort(cets:dump(T)).

delete_request_from_bag(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{type => bag}),
    cets:insert_many(T, [{1, 1}, {1, 2}]),
    R = cets:delete_object_request(T, {1, 2}),
    {reply, ok} = cets:wait_response(R, 5000),
    [{1, 1}] = cets:dump(T).

delete_request_many_from_bag(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{type => bag}),
    cets:insert_many(T, [{1, 1}, {1, 2}, {1, 3}]),
    R = cets:delete_objects_request(T, [{1, 1}, {1, 3}]),
    {reply, ok} = cets:wait_response(R, 5000),
    [{1, 2}] = cets:dump(T).

insert_into_bag_is_replicated(Config) ->
    #{pid1 := Pid1, tab2 := T2} = given_two_joined_tables(Config, #{type => bag}),
    cets:insert(Pid1, {1, 1}),
    [{1, 1}] = cets:dump(T2).

insert_into_keypos_table(Config) ->
    T = make_name(Config),
    {ok, _Pid} = start_local(T, #{keypos => 2}),
    cets:insert(T, {rec, 1}),
    cets:insert(T, {rec, 2}),
    [{rec, 1}] = lists:sort(ets:lookup(T, 1)),
    [{rec, 1}, {rec, 2}] = lists:sort(cets:dump(T)).

table_name_works(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T),
    {ok, T} = cets:table_name(T),
    {ok, T} = cets:table_name(Pid),
    #{table := T} = cets:info(Pid).

info_contains_opts(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T, #{type => bag}),
    #{opts := #{type := bag}} = cets:info(Pid).

info_contains_pause_monitors(Config) ->
    T = make_name(Config),
    {ok, Pid} = start_local(T, #{}),
    PauseMon = cets:pause(Pid),
    #{pause_monitors := [PauseMon]} = cets:info(Pid).

info_contains_other_servers(Config) ->
    #{pid1 := Pid1, pid2 := Pid2} = given_two_joined_tables(Config),
    #{other_servers := [Pid2]} = cets:info(Pid1).

check_could_reach_each_other_fails(_Config) ->
    ?assertException(
        error,
        check_could_reach_each_other_failed,
        cets_join:check_could_reach_each_other(#{}, [self()], [bad_node_pid()])
    ).

%% Cases to improve code coverage

unknown_down_message_is_ignored(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    RandPid = proc_lib:spawn(fun() -> ok end),
    Pid ! {'DOWN', make_ref(), process, RandPid, oops},
    still_works(Pid).

unknown_message_is_ignored(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    Pid ! oops,
    still_works(Pid).

unknown_cast_message_is_ignored(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    gen_server:cast(Pid, oops),
    still_works(Pid).

unknown_message_is_ignored_in_ack_process(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    #{ack_pid := AckPid} = cets:info(Pid),
    AckPid ! oops,
    still_works(Pid).

unknown_cast_message_is_ignored_in_ack_process(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    #{ack_pid := AckPid} = cets:info(Pid),
    gen_server:cast(AckPid, oops),
    still_works(Pid).

unknown_call_returns_error_from_ack_process(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    #{ack_pid := AckPid} = cets:info(Pid),
    {error, unexpected_call} = gen_server:call(AckPid, oops),
    still_works(Pid).

code_change_returns_ok(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    sys:suspend(Pid),
    ok = sys:change_code(Pid, cets, v2, []),
    sys:resume(Pid).

code_change_returns_ok_for_ack(Config) ->
    {ok, Pid} = start_local(make_name(Config)),
    #{ack_pid := AckPid} = cets:info(Pid),
    sys:suspend(AckPid),
    ok = sys:change_code(AckPid, cets_ack, v2, []),
    sys:resume(AckPid).

run_spawn_forwards_errors(_Config) ->
    ?assertException(
        error,
        {task_failed, oops, #{}},
        cets_long:run_spawn(#{}, fun() -> error(oops) end)
    ).

run_tracked_failed(_Config) ->
    F = fun() -> error(oops) end,
    ?assertException(
        error,
        {task_failed, oops, #{}},
        cets_long:run_tracked(#{}, F)
    ).

run_tracked_logged(_Config) ->
    F = fun() -> timer:sleep(100) end,
    cets_long:run_tracked(#{report_interval => 10}, F).

run_tracked_logged_check_logger(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    LogRef = make_ref(),
    F = fun() -> timer:sleep(infinity) end,
    %% Run it in a separate process, so we can check logs in the test process
    %% Overwrite default five seconds interval with 10 milliseconds
    spawn_link(fun() -> cets_long:run_tracked(#{report_interval => 10, log_ref => LogRef}, F) end),
    %% Exit test after first log event
    receive
        {log, ?FUNCTION_NAME, #{
            level := warning,
            msg := {report, #{what := long_task_progress, log_ref := LogRef}}
        }} ->
            ok
    after 5000 ->
        ct:fail(timeout)
    end.

%% Improves code coverage, checks logs
long_call_fails_because_linked_process_dies(_Config) ->
    logger_debug_h:start(#{id => ?FUNCTION_NAME}),
    LogRef = make_ref(),
    Me = self(),
    F = fun() ->
        Me ! task_started,
        timer:sleep(infinity)
    end,
    RunPid = proc_lib:spawn(fun() -> cets_long:run_tracked(#{log_ref => LogRef}, F) end),
    %% To avoid race conditions
    receive_message(task_started),
    proc_lib:spawn(fun() ->
        link(RunPid),
        error(sim_error_in_linked_process)
    end),
    wait_for_down(RunPid),
    %% Exit test after first log event
    receive
        {log, ?FUNCTION_NAME, #{
            level := error,
            msg := {report, #{what := task_failed, log_ref := LogRef, caller_pid := RunPid}}
        }} ->
            ok
    after 5000 ->
        ct:fail(timeout)
    end.

long_call_to_unknown_name_throws_pid_not_found(_Config) ->
    ?assertException(
        error,
        {pid_not_found, unknown_name_please},
        cets_call:long_call(unknown_name_please, test)
    ).

send_leader_op_throws_noproc(_Config) ->
    ?assertException(
        exit,
        {noproc, {gen_server, call, [unknown_name_please, get_leader]}},
        cets_call:send_leader_op(unknown_name_please, {op, {insert, {1}}})
    ).

pinfo_returns_value(_Config) ->
    true = is_list(cets_long:pinfo(self(), messages)).

pinfo_returns_undefined(_Config) ->
    undefined = cets_long:pinfo(stopped_pid(), messages).

%% Helper functions

still_works(Pid) ->
    pong = cets:ping(Pid),
    %% The server works fine
    ok = cets:insert(Pid, {1}),
    {ok, [{1}]} = cets:remote_dump(Pid).

stopped_pid() ->
    %% Get a pid for a stopped process
    {Pid, Mon} = spawn_monitor(fun() -> ok end),
    receive
        {'DOWN', Mon, process, Pid, _Reason} -> ok
    end,
    Pid.

bad_node_pid() ->
    binary_to_term(bad_node_pid_binary()).

bad_node_pid_binary() ->
    %% Pid <0.90.0> on badnode@localhost
    <<131, 88, 100, 0, 17, 98, 97, 100, 110, 111, 100, 101, 64, 108, 111, 99, 97, 108, 104, 111,
        115, 116, 0, 0, 0, 90, 0, 0, 0, 0, 100, 206, 70, 92>>.

not_leader(Leader, Other, Leader) ->
    Other;
not_leader(Other, Leader, Leader) ->
    Other.
