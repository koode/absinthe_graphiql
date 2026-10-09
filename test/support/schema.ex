defmodule AbsintheGraphiQL.Test.Schema do
  @moduledoc false
  use Absinthe.Schema

  object :message do
    field(:id, non_null(:id))
    field(:body, non_null(:string))
  end

  input_object :message_input do
    field(:body, non_null(:string))
  end

  query do
    field :hello, non_null(:string) do
      arg(:name, :string)
      resolve(fn args, _ -> {:ok, "Hello, #{Map.get(args, :name, "world")}!"} end)
    end
  end

  mutation do
    field :add_message, non_null(:message) do
      arg(:input, non_null(:message_input))

      resolve(fn %{input: %{body: body}}, _ ->
        {:ok, %{id: Integer.to_string(System.unique_integer([:positive])), body: body}}
      end)
    end
  end

  subscription do
    field :message_added, non_null(:message) do
      config(fn _args, _resolution -> {:ok, topic: "messages"} end)
      trigger(:add_message, topic: fn _message -> "messages" end)
    end
  end
end
