defmodule AbsintheGraphiQL.SubscriptionTest do
  # Pins the Absinthe channel protocol that assets/src/absinthe_socket.js
  # speaks: topic, event names and payload shapes. The JS unit tests in
  # assets/test/absinthe_socket.test.js use the same shapes.
  use ExUnit.Case, async: false
  use Absinthe.Phoenix.SubscriptionTest, schema: AbsintheGraphiQL.Test.Schema

  import Phoenix.ChannelTest
  import Plug.Conn, only: [put_req_header: 3, put_private: 3]
  import Plug.Test

  @endpoint AbsintheGraphiQL.Test.Endpoint

  @subscription "subscription { messageAdded { body } }"
  @mutation ~s|mutation($input: MessageInput!) { addMessage(input: $input) { body } }|

  setup do
    {:ok, socket} = connect(AbsintheGraphiQL.Test.Socket, %{})
    {:ok, socket} = join_absinthe(socket)
    {:ok, socket: socket}
  end

  # Sends the mutation through the plug, as curl or the IDE would.
  defp add_message(body) do
    opts = AbsintheGraphiQL.Plug.init(schema: AbsintheGraphiQL.Test.Schema)

    conn =
      conn(:post, "/", Jason.encode!(%{query: @mutation, variables: %{input: %{body: body}}}))
      |> put_req_header("content-type", "application/json")
      |> put_private(:phoenix_endpoint, @endpoint)
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:json], json_decoder: Jason))
      |> AbsintheGraphiQL.Plug.call(opts)

    assert conn.status == 200
    Jason.decode!(conn.resp_body)
  end

  test "the control topic is __absinthe__:control", %{socket: socket} do
    assert socket.topic == "__absinthe__:control"
  end

  test "doc replies with a subscriptionId and events arrive as subscription:data", %{
    socket: socket
  } do
    ref = push(socket, "doc", %{"query" => @subscription, "variables" => %{}})
    assert_reply(ref, :ok, %{subscriptionId: subscription_id})
    assert is_binary(subscription_id)

    assert %{"data" => %{"addMessage" => %{"body" => "hello"}}} = add_message("hello")

    # The event is not on the control topic: it is on the subscription id.
    assert_receive %Phoenix.Socket.Message{
      topic: ^subscription_id,
      event: "subscription:data",
      payload: %{
        subscriptionId: ^subscription_id,
        result: %{data: %{"messageAdded" => %{"body" => "hello"}}}
      }
    }
  end

  test "unsubscribe stops the events", %{socket: socket} do
    ref = push(socket, "doc", %{"query" => @subscription, "variables" => %{}})
    assert_reply(ref, :ok, %{subscriptionId: subscription_id})

    ref = push(socket, "unsubscribe", %{"subscriptionId" => subscription_id})
    assert_reply(ref, :ok, %{subscriptionId: ^subscription_id})

    add_message("after unsubscribe")
    refute_receive %Phoenix.Socket.Message{event: "subscription:data"}, 200
  end

  test "a validation error replies error with errors", %{socket: socket} do
    ref = push(socket, "doc", %{"query" => "subscription { nope }", "variables" => %{}})
    assert_reply(ref, :error, %{errors: [%{message: message} | _]})
    assert message =~ "nope"
  end

  test "bad variables reply error with an error string", %{socket: socket} do
    ref = push(socket, "doc", %{"query" => @subscription, "variables" => "not a map"})
    assert_reply(ref, :error, %{error: "Could not parse variables as map"})
  end

  test "a query over the socket replies ok with the result", %{socket: socket} do
    ref = push(socket, "doc", %{"query" => "{ hello }", "variables" => %{}})
    assert_reply(ref, :ok, %{data: %{"hello" => "Hello, world!"}})
  end

  test "the channel ignores operationName, so documents must hold one operation", %{
    socket: socket
  } do
    query = "query A { hello } subscription B { messageAdded { body } }"
    ref = push(socket, "doc", %{"query" => query, "variables" => %{}, "operationName" => "B"})
    assert_reply(ref, :error, %{errors: [%{message: message} | _]})
    assert message =~ "operation name"
  end
end
