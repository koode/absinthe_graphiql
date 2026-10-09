# Credo with every ExSlop check, including the opt-in ones.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "examples/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      checks: %{extra: Enum.map(ExSlop.checks(), &{&1, []})}
    }
  ]
}
