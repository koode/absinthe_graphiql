defmodule AbsintheGraphiQL.NoSubscriptionOnHTTP do
  @moduledoc false

  # Same rule as Absinthe.Plug.GraphiQL: a subscription sent to the HTTP
  # endpoint gets a clear error instead of an SSE stream. The IDE sends
  # subscriptions over the Phoenix socket.

  use Absinthe.Phase

  alias Absinthe.Blueprint

  @impl true
  def run(blueprint, _options \\ []) do
    case Blueprint.current_operation(blueprint) do
      %{type: :subscription} ->
        {:error,
         {:http_method,
          "Subscriptions cannot be run over HTTP. Configure the :socket_url option of " <>
            "AbsintheGraphiQL.Plug and send them over the Phoenix socket."}}

      _ ->
        {:ok, blueprint}
    end
  end
end
