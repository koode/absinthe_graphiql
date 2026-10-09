defmodule AbsintheGraphiQL.Assets do
  @moduledoc false

  # The built GraphiQL bundle lives in priv/static. assets/build.mjs writes
  # priv/static/manifest.json with the content-hashed file names; it is read
  # here at compile time, so a rebuilt bundle recompiles this module.

  @manifest_path Path.expand("../../priv/static/manifest.json", __DIR__)
  @external_resource @manifest_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @files MapSet.new(@manifest["files"])

  @doc "The hashed file name of a bundle entry, for example `\"app.js\"`."
  @spec entry(String.t()) :: String.t()
  def entry(name) when is_map_key(@manifest, name) and name != "files",
    do: Map.fetch!(@manifest, name)

  @doc "Every file the asset route may serve."
  @spec files() :: MapSet.t(String.t())
  def files, do: @files

  @doc "Whether `name` is a file of the bundle."
  @spec file?(String.t()) :: boolean()
  def file?(name) when is_binary(name), do: MapSet.member?(@files, name)
end
