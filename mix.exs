defmodule AbsintheGraphiQL.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/koode/absinthe_graphiql"

  def project do
    [
      app: :absinthe_graphiql,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description:
        "A self-hosted GraphiQL 6 IDE for Absinthe, with subscriptions over Phoenix channels.",
      package: package(),
      source_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.2"},
      {:absinthe_phoenix, "~> 2.0", only: [:dev, :test]},
      {:phoenix, "~> 1.7", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "assets.build": ["cmd --cd assets npm ci", "cmd --cd assets npm run build"],
      "assets.test": ["cmd --cd assets npm test"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "GraphiQL" => "https://github.com/graphql/graphiql"},
      files: ~w(lib priv/static mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      # No :underspecs: AbsintheGraphiQL.Plug.init/1 accepts every
      # Absinthe.Plug option ({atom(), term()}) and returns Absinthe.Plug's
      # config map. A spec that is not wider than the success typing would have
      # to copy absinthe_plug's internal config keys and option types.
      flags: [:error_handling, :extra_return, :missing_return]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
    ]
  end
end
