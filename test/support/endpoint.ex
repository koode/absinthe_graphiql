defmodule AbsintheGraphiQL.Test.Socket do
  @moduledoc false
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: AbsintheGraphiQL.Test.Schema

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule AbsintheGraphiQL.Test.Router do
  @moduledoc false
  use Phoenix.Router

  forward("/graphiql", AbsintheGraphiQL.Plug,
    schema: AbsintheGraphiQL.Test.Schema,
    socket: AbsintheGraphiQL.Test.Socket
  )
end

defmodule AbsintheGraphiQL.Test.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :absinthe_graphiql
  use Absinthe.Phoenix.Endpoint

  socket("/socket", AbsintheGraphiQL.Test.Socket, websocket: true)

  plug(AbsintheGraphiQL.Test.Router)
end
