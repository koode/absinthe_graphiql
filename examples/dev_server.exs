# A minimal Phoenix app that serves AbsintheGraphiQL.Plug at /graphiql.
#
#     mise exec -- elixir examples/dev_server.exs
#
# Then open http://localhost:4401/graphiql. Send a message from outside the
# IDE to see a running `messageAdded` subscription receive it:
#
#     curl -s localhost:4401/graphiql -H 'content-type: application/json' \
#       -d '{"query":"mutation { addMessage(input: {body: \"hi\"}) { id body } }"}'
#
# Set PORT to use another port.

Mix.install([
  {:absinthe_graphiql, path: Path.expand("..", __DIR__)},
  {:absinthe, "~> 1.7"},
  {:absinthe_plug, "~> 1.5"},
  {:absinthe_phoenix, "~> 2.0"},
  {:phoenix, "~> 1.7"},
  {:phoenix_pubsub, "~> 2.1"},
  {:bandit, "~> 1.5"},
  {:jason, "~> 1.4"}
])

defmodule Example.Store do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def all, do: Agent.get(__MODULE__, &Enum.reverse/1)

  def add(body) do
    message = %{id: Integer.to_string(System.unique_integer([:positive])), body: body}
    Agent.update(__MODULE__, &[message | &1])
    message
  end
end

defmodule Example.Schema do
  use Absinthe.Schema

  @desc "A chat message"
  object :message do
    field(:id, non_null(:id))
    field(:body, non_null(:string))
  end

  input_object :message_input do
    field(:body, non_null(:string))
  end

  query do
    @desc "Say hello"
    field :hello, non_null(:string) do
      arg(:name, :string)
      resolve(fn args, _ -> {:ok, "Hello, #{Map.get(args, :name, "world")}!"} end)
    end

    @desc "All messages, oldest first"
    field :messages, non_null(list_of(non_null(:message))) do
      resolve(fn _, _ -> {:ok, Example.Store.all()} end)
    end
  end

  mutation do
    @desc "Add a message; `messageAdded` subscribers receive it"
    field :add_message, non_null(:message) do
      arg(:input, non_null(:message_input))
      resolve(fn %{input: %{body: body}}, _ -> {:ok, Example.Store.add(body)} end)
    end
  end

  subscription do
    @desc "Every message added with `addMessage`"
    field :message_added, non_null(:message) do
      config(fn _args, _resolution -> {:ok, topic: "messages"} end)
      trigger(:add_message, topic: fn _message -> "messages" end)
    end
  end
end

defmodule Example.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: Example.Schema

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule Example.Router do
  use Phoenix.Router

  get("/", Example.RedirectController, :index)

  forward("/graphiql", AbsintheGraphiQL.Plug,
    schema: Example.Schema,
    socket_url: "/socket",
    socket_params: %{"client" => "graphiql"},
    title: "Example API",
    theme:
      case System.get_env("THEME") do
        "light" -> :light
        "dark" -> :dark
        _ -> :system
      end,
    default_query: """
    # Start the subscription, then send a message from a terminal:
    #
    #   curl -s localhost:4401/graphiql -H 'content-type: application/json' \\
    #     -d '{"query":"mutation { addMessage(input: {body: \\"hi\\"}) { id body } }"}'

    subscription OnMessage {
      messageAdded {
        id
        body
      }
    }
    """
  )
end

defmodule Example.RedirectController do
  use Phoenix.Controller, formats: []

  def index(conn, _params), do: redirect(conn, to: "/graphiql")
end

defmodule Example.ErrorJSON do
  # Error responses, for example the 404 for /favicon.ico.
  def render(template, _assigns),
    do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end

defmodule Example.Endpoint do
  use Phoenix.Endpoint, otp_app: :example
  use Absinthe.Phoenix.Endpoint

  socket("/socket", Example.UserSocket, websocket: true, longpoll: false)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Example.Router)
end

port = String.to_integer(System.get_env("PORT", "4401"))

Application.put_env(:example, Example.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  pubsub_server: Example.PubSub,
  secret_key_base: String.duplicate("absinthe_graphiql", 4),
  check_origin: false,
  render_errors: [formats: [json: Example.ErrorJSON], layout: false]
)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Example.PubSub},
      Example.Store,
      Example.Endpoint,
      {Absinthe.Subscription, Example.Endpoint}
    ],
    strategy: :one_for_one
  )

IO.puts("GraphiQL at http://localhost:#{port}/graphiql")
Process.sleep(:infinity)
