%% Copyright (c) 2013, Michael Santos <michael.santos@gmail.com>
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%% Redistributions of source code must retain the above copyright
%% notice, this list of conditions and the following disclaimer.
%%
%% Redistributions in binary form must reproduce the above copyright
%% notice, this list of conditions and the following disclaimer in the
%% documentation and/or other materials provided with the distribution.
%%
%% Neither the name of the author nor the names of its contributors
%% may be used to endorse or promote products derived from this software
%% without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.
-module(gen_unix_tests).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

-define(SOCKDIR, "/tmp/gen_unix").

fd_array_test() ->
    FD = [9,10,11,12,13,14],
    FD = gen_unix:fd(gen_unix:fd(FD)).

ucred_struct_test() ->
    % Layout for struct ucred on this platform
    Cred = gen_unix:cred([]),
    Cred = gen_unix:cred(gen_unix:cred(Cred)).

credpass_test() ->
    ok = file:make_dir(?SOCKDIR),
    {ok, Socket0} = gen_unix:listen(?SOCKDIR ++ "/s"),
    spawn(fun() ->
            os:cmd("erl -pa ../ebin ../deps/*/ebin -s gen_unix_tests credsend")
            end),
    {ok, Socket} = poll(fun() -> procket:accept(Socket0) end),
    {ok, Cred} = poll(fun() -> gen_unix:credrecv(Socket) end),

    % Do socket cleanup first
    ok = procket:close(Socket0),
    ok = file:delete(?SOCKDIR ++ "/s"),
    ok = file:del_dir(?SOCKDIR),

    % Check the struct ucred is valid; the only common field between
    % OS'es is the uid. Doesn't appear to be a way natively to get our
    % uid, so all we do is check that the result is an integer.
    Ucred = gen_unix:cred(Cred),
    Uid = proplists:get_value(uid, Ucred),
    error_logger:info_report(Ucred),
    true = is_integer(Uid).

fdpass_test() ->
    ok = file:make_dir(?SOCKDIR),
    {ok, Socket0} = gen_unix:listen(?SOCKDIR ++ "/s"),
    os:cmd("erl -pa ../ebin ../deps/*/ebin -s gen_unix_tests fdsend"),
    {ok, Socket} = poll(fun() -> procket:accept(Socket0) end),
    {ok, FDs} = poll(fun() -> gen_unix:fdrecv(Socket, 2) end),

    % Do socket cleanup first
    ok = procket:close(Socket0),
    ok = file:delete(?SOCKDIR ++ "/s"),
    ok = file:del_dir(?SOCKDIR),

    [FD1,FD2] = gen_unix:fd(FDs),
    true = is_integer(FD1),
    true = is_integer(FD2),

    {ok, Socket1} = gen_udp:open(0, [binary, {fd, FD1}, {active, false}]),
    {ok, Socket2} = gen_udp:open(0, [binary, {fd, FD2}, {active, false}]),

    {ok, {{127,0,0,1}, _, <<0,1,2,3,4,5,6,7,8,9>>}} = gen_udp:recv(Socket1, 20),
    {ok, {{127,0,0,1}, _, <<0,1,2,3,4,5,6,7,8,9>>}} = gen_udp:recv(Socket2, 20).

poll(Fun) ->
    case Fun() of
        {ok, Buf} ->
            {ok, Buf};
        {error, eagain} ->
            timer:sleep(10),
            poll(Fun);
        Error ->
            Error
    end.

credsend() ->
    {ok, Socket} = gen_unix:connect(?SOCKDIR ++ "/s"),
    ok = gen_unix:credsend(Socket).

fdsend() ->
    {ok, Socket} = gen_unix:connect(?SOCKDIR ++ "/s"),

    % Open 2 random UDP ports
    {ok, Socket1} = gen_udp:open(0, [{active,false}]),
    {ok, Socket2} = gen_udp:open(0, [{active,false}]),

    {ok, Port1} = inet:port(Socket1),
    {ok, Port2} = inet:port(Socket2),

    {ok, FD1} = inet:getfd(Socket1),
    {ok, FD2} = inet:getfd(Socket2),

    ok = gen_unix:fdsend(Socket, [FD1, FD2]),

    ok = gen_udp:close(Socket1),
    ok = gen_udp:close(Socket2),

    % Open 2 new sockets
    {ok, Socket3} = gen_udp:open(0, [{active,false}]),
    {ok, Socket4} = gen_udp:open(0, [{active,false}]),

    ok = gen_udp:send(Socket3, {127,0,0,1}, Port1, <<0,1,2,3,4,5,6,7,8,9>>),
    ok = gen_udp:send(Socket4, {127,0,0,1}, Port2, <<0,1,2,3,4,5,6,7,8,9>>).