Application.put_env(:absinthe_graphiql, AbsintheGraphiQL.Test.Endpoint,
  pubsub_server: AbsintheGraphiQL.Test.PubSub,
  secret_key_base: String.duplicate("a", 64),
  server: false
)

{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: AbsintheGraphiQL.Test.PubSub)
{:ok, _} = AbsintheGraphiQL.Test.Endpoint.start_link()
{:ok, _} = Absinthe.Subscription.start_link(AbsintheGraphiQL.Test.Endpoint)

Logger.configure(level: :warning)
ExUnit.start()
