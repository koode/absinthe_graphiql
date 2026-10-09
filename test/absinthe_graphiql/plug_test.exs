defmodule AbsintheGraphiQL.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AbsintheGraphiQL.Assets
  alias AbsintheGraphiQL.Test.Schema

  defmodule Callbacks do
    def headers, do: %{"x-from" => "mf0"}
    def headers(conn), do: %{"x-path" => conn.request_path}
    def socket_params, do: %{"token" => "mf-token"}
    def params_from_conn(conn), do: %{"token" => conn.assigns[:token]}
    def not_a_map, do: "nope"
  end

  @html "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

  @parsers Plug.Parsers.init(
             parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
             pass: ["*/*"],
             json_decoder: Jason
           )

  # Runs Plug.Parsers first, like a Phoenix endpoint does.
  defp call(conn, opts) do
    conn
    |> Plug.Parsers.call(@parsers)
    |> AbsintheGraphiQL.Plug.call(AbsintheGraphiQL.Plug.init([schema: Schema] ++ opts))
  end

  defp put_host_header(conn, host), do: %{conn | req_headers: [{"host", host} | conn.req_headers]}

  # Builds a request as if the plug were forwarded at /graphiql.
  defp mounted(method, path, body \\ nil) do
    conn = conn(method, "/graphiql" <> path, body)
    [_ | path_info] = conn.path_info
    %{conn | script_name: ["graphiql"], path_info: path_info}
  end

  defp browser_get(opts \\ [], path \\ "") do
    mounted(:get, path)
    |> put_req_header("accept", @html)
    |> call(opts)
  end

  defp page_config(conn) do
    [_, encoded] = Regex.run(~r/<div id="graphiql" data-config="([^"]*)">/, conn.resp_body)

    encoded
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
  end

  defp csp(conn), do: conn |> get_resp_header("content-security-policy") |> List.first()

  describe "IDE page" do
    test "is served for a browser GET" do
      conn = browser_get()

      assert conn.status == 200
      assert ["text/html; charset=utf-8"] = get_resp_header(conn, "content-type")
      assert ["no-store"] = get_resp_header(conn, "cache-control")
      assert conn.resp_body =~ ~s(<title>GraphiQL</title>)

      assert conn.resp_body =~
               ~s(<link rel="icon" type="image/svg+xml" href="/graphiql/__assets__/#{Assets.entry("favicon.svg")}">)

      assert conn.resp_body =~
               ~s(<script type="module" src="/graphiql/__assets__/#{Assets.entry("app.js")}">)

      assert conn.resp_body =~
               ~s(<link rel="stylesheet" href="/graphiql/__assets__/#{Assets.entry("app.css")}">)
    end

    test "has no inline executable script" do
      conn = browser_get()

      scripts = Regex.scan(~r/<script[^>]*>(.*?)<\/script>/s, conn.resp_body)
      assert length(scripts) == 1
      assert Enum.all?(scripts, fn [_, inline] -> String.trim(inline) == "" end)
      refute conn.resp_body =~ ~r/\son[a-z]+=/i
    end

    test "has the default config" do
      config = browser_get() |> page_config()

      assert config["url"] == "/graphiql"
      assert config["socketUrl"] == nil
      assert config["socketParams"] == %{}
      assert config["theme"] == "system"
      assert config["queryBuilder"] == true
      assert config["history"] == true
      assert config["collections"] == true
      assert config["shouldPersistHeaders"] == false
      assert config["defaultQuery"] == nil
      assert config["defaultVariables"] == nil
      assert config["defaultHeaders"] == nil

      assert config["workers"] == %{
               "editor" => "/graphiql/__assets__/" <> Assets.entry("editor.worker.js"),
               "json" => "/graphiql/__assets__/" <> Assets.entry("json.worker.js"),
               "graphql" => "/graphiql/__assets__/" <> Assets.entry("graphql.worker.js")
             }
    end

    test "uses / as the mount path when not forwarded" do
      conn = conn(:get, "/") |> put_req_header("accept", @html) |> call([])

      assert page_config(conn)["url"] == "/"
      assert conn.resp_body =~ ~s(src="/__assets__/#{Assets.entry("app.js")}")
    end

    test "passes static options into the config" do
      config =
        browser_get(
          default_url: "https://api.example.com/graphql",
          socket_url: "/socket",
          socket_params: %{"token" => "abc"},
          default_query: "{ hello }",
          default_variables: %{"name" => "Ada"},
          default_headers: %{"authorization" => "Bearer x"},
          title: "My API",
          theme: :dark,
          query_builder: false,
          history: false,
          collections: false,
          should_persist_headers: true
        )
        |> page_config()

      assert config["url"] == "https://api.example.com/graphql"
      assert config["socketUrl"] == "/socket"
      assert config["socketParams"] == %{"token" => "abc"}
      assert config["defaultQuery"] == "{ hello }"
      assert Jason.decode!(config["defaultVariables"]) == %{"name" => "Ada"}
      assert Jason.decode!(config["defaultHeaders"]) == %{"authorization" => "Bearer x"}
      assert config["theme"] == "dark"
      assert config["queryBuilder"] == false
      assert config["history"] == false
      assert config["collections"] == false
      assert config["shouldPersistHeaders"] == true
    end

    test "passes JSON strings for variables and headers through" do
      config =
        browser_get(default_variables: ~s({"a": 1}), default_headers: ~s({"x": "y"}))
        |> page_config()

      assert config["defaultVariables"] == ~s({"a": 1})
      assert config["defaultHeaders"] == ~s({"x": "y"})
    end

    for theme <- [:system, :light, :dark] do
      test "puts theme #{theme} into the config" do
        assert browser_get(theme: unquote(theme)) |> page_config() |> Map.fetch!("theme") ==
                 Atom.to_string(unquote(theme))
      end
    end

    test "escapes the config so it cannot leave the attribute" do
      evil = ~S|"><script>alert(1)</script></div><div x='| <> "&amp;"
      conn = browser_get(default_query: evil, title: evil)

      refute conn.resp_body =~ "<script>alert(1)</script>"
      refute conn.resp_body =~ ~s("><script>)
      assert length(Regex.scan(~r/<\/div>/, conn.resp_body)) == 2
      assert length(Regex.scan(~r/<script/, conn.resp_body)) == 1
      assert page_config(conn)["defaultQuery"] == evil
      assert conn.resp_body =~ "<title>&quot;&gt;&lt;script&gt;"
    end
  end

  describe "dynamic options" do
    test "default_headers as a 0-arity function" do
      config = browser_get(default_headers: fn -> %{"x-fn" => "0"} end) |> page_config()
      assert Jason.decode!(config["defaultHeaders"]) == %{"x-fn" => "0"}
    end

    test "default_headers as a 1-arity function gets the conn" do
      config =
        browser_get(default_headers: fn conn -> %{"x-method" => conn.method} end) |> page_config()

      assert Jason.decode!(config["defaultHeaders"]) == %{"x-method" => "GET"}
    end

    test "default_headers as {module, function}, arity 1 preferred" do
      config = browser_get(default_headers: {Callbacks, :headers}) |> page_config()
      assert Jason.decode!(config["defaultHeaders"]) == %{"x-path" => "/graphiql"}
    end

    test "socket_params as a function and as {module, function}" do
      config = browser_get(socket_params: fn -> %{"token" => "fn-token"} end) |> page_config()
      assert config["socketParams"] == %{"token" => "fn-token"}

      config = browser_get(socket_params: {Callbacks, :socket_params}) |> page_config()
      assert config["socketParams"] == %{"token" => "mf-token"}

      conn =
        mounted(:get, "")
        |> put_req_header("accept", @html)
        |> assign(:token, "from-assigns")
        |> call(socket_params: {Callbacks, :params_from_conn})

      assert page_config(conn)["socketParams"] == %{"token" => "from-assigns"}
    end

    test "default_url and socket_url as functions" do
      config =
        browser_get(default_url: fn -> "/api/graphql" end, socket_url: fn _conn -> "/live" end)
        |> page_config()

      assert config["url"] == "/api/graphql"
      assert config["socketUrl"] == "/live"
    end

    test "a function returning the wrong type raises a clear error" do
      assert_raise ArgumentError,
                   ~r/:socket_params .* expected the function to return a map/,
                   fn ->
                     browser_get(socket_params: {Callbacks, :not_a_map})
                   end
    end

    test "a {module, function} that does not exist raises a clear error" do
      assert_raise ArgumentError,
                   ~r/Callbacks.missing\/1 or .*Callbacks.missing\/0 is not exported/,
                   fn ->
                     browser_get(default_headers: {Callbacks, :missing})
                   end
    end
  end

  describe "socket lookup" do
    test "socket: finds the path in the Phoenix endpoint" do
      conn =
        mounted(:get, "")
        |> put_req_header("accept", @html)
        |> put_private(:phoenix_endpoint, AbsintheGraphiQL.Test.Endpoint)
        |> call(socket: AbsintheGraphiQL.Test.Socket)

      assert page_config(conn)["socketUrl"] == "/socket"
    end

    test "socket_url wins over socket" do
      conn =
        mounted(:get, "")
        |> put_req_header("accept", @html)
        |> put_private(:phoenix_endpoint, AbsintheGraphiQL.Test.Endpoint)
        |> call(socket: AbsintheGraphiQL.Test.Socket, socket_url: "/other")

      assert page_config(conn)["socketUrl"] == "/other"
    end

    test "socket without an endpoint gives no socket" do
      assert browser_get(socket: AbsintheGraphiQL.Test.Socket)
             |> page_config()
             |> Map.get("socketUrl") ==
               nil
    end
  end

  describe "Content-Security-Policy" do
    test "is strict by default" do
      policy = browser_get() |> csp()

      assert policy ==
               "default-src 'self'; script-src 'self'; worker-src 'self'; " <>
                 "style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; " <>
                 "connect-src 'self' ws://www.example.com wss://www.example.com; " <>
                 "base-uri 'none'; form-action 'none'; frame-ancestors 'self'"
    end

    test "uses the host header, port included" do
      conn =
        mounted(:get, "")
        |> put_req_header("accept", @html)
        |> put_host_header("localhost:4401")
        |> call([])

      assert csp(conn) =~ "connect-src 'self' ws://localhost:4401 wss://localhost:4401;"
    end

    test "falls back to conn.host and conn.port without a host header" do
      conn =
        %{mounted(:get, "") | host: "localhost", port: 4401}
        |> put_req_header("accept", @html)
        |> call([])

      assert csp(conn) =~ "connect-src 'self' ws://localhost:4401 wss://localhost:4401;"
    end

    test "ignores a host header that could add directives" do
      conn =
        mounted(:get, "")
        |> put_req_header("accept", @html)
        |> put_host_header("evil.com; script-src *")
        |> call([])

      assert csp(conn) =~ "connect-src 'self'; base-uri"
    end

    test "allows the origins of absolute default_url and socket_url" do
      policy =
        browser_get(
          default_url: "https://api.example.com:8443/graphql",
          socket_url: "https://sockets.example.com/socket"
        )
        |> csp()

      assert policy =~
               "connect-src 'self' ws://www.example.com wss://www.example.com " <>
                 "https://api.example.com:8443 wss://sockets.example.com;"
    end

    test "protocol-relative socket_url allows ws and wss" do
      assert browser_get(socket_url: "//rt.example.com/socket") |> csp() =~
               "ws://rt.example.com wss://rt.example.com;"
    end

    test "false sends no header" do
      assert browser_get(csp: false) |> csp() == nil
    end

    test "a string is sent verbatim" do
      assert browser_get(csp: "default-src 'none'") |> csp() == "default-src 'none'"
    end
  end

  describe "queries are delegated to Absinthe.Plug" do
    test "POST JSON" do
      conn =
        mounted(:post, "", Jason.encode!(%{query: ~S|{ hello(name: "Ada") }|}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/graphql-response+json, application/json;q=0.9")
        |> call([])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"data" => %{"hello" => "Hello, Ada!"}}
    end

    test "POST mutation with an input argument" do
      query = ~s|mutation($input: MessageInput!) { addMessage(input: $input) { body } }|

      conn =
        mounted(:post, "", Jason.encode!(%{query: query, variables: %{input: %{body: "hi"}}}))
        |> put_req_header("content-type", "application/json")
        |> call([])

      assert Jason.decode!(conn.resp_body) == %{"data" => %{"addMessage" => %{"body" => "hi"}}}
    end

    test "GET with a query parameter, even from a browser" do
      conn =
        mounted(:get, "?query=%7B%20hello%20%7D")
        |> put_req_header("accept", @html)
        |> call([])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"data" => %{"hello" => "Hello, world!"}}
    end

    test "GET without text/html is not the IDE" do
      conn = mounted(:get, "") |> put_req_header("accept", "application/json") |> call([])

      assert conn.status == 400
      refute conn.resp_body =~ "<html"
    end

    test "a subscription over HTTP is rejected" do
      conn =
        mounted(:post, "", Jason.encode!(%{query: "subscription { messageAdded { body } }"}))
        |> put_req_header("content-type", "application/json")
        |> call([])

      assert conn.status == 405
      assert %{"errors" => [%{"message" => message}]} = Jason.decode!(conn.resp_body)
      assert message =~ "Subscriptions cannot be run over HTTP"
    end
  end

  describe "assets" do
    test "serves the hashed entry files with long-lived caching" do
      for {entry, type} <- [
            {"app.js", "text/javascript"},
            {"app.css", "text/css"},
            {"editor.worker.js", "text/javascript"},
            {"json.worker.js", "text/javascript"},
            {"graphql.worker.js", "text/javascript"},
            {"favicon.svg", "image/svg+xml"}
          ] do
        file = Assets.entry(entry)
        conn = mounted(:get, "/__assets__/" <> file) |> call([])

        assert conn.status == 200, "#{file}: #{conn.status}"
        assert [content_type] = get_resp_header(conn, "content-type")
        assert content_type =~ type
        assert ["public, max-age=31536000, immutable"] = get_resp_header(conn, "cache-control")
        assert conn.halted

        assert byte_size(conn.resp_body) ==
                 File.stat!(Application.app_dir(:absinthe_graphiql, "priv/static/" <> file)).size
      end
    end

    test "serves fonts with font content types" do
      fonts = Enum.filter(Assets.files(), &String.starts_with?(&1, "font-"))
      assert fonts != []

      for font <- fonts do
        conn = mounted(:get, "/__assets__/" <> font) |> call([])
        assert conn.status == 200
        assert [type] = get_resp_header(conn, "content-type")
        assert type =~ ~r{^font/(woff2|woff|ttf)}
      end
    end

    test "HEAD works" do
      conn = mounted(:head, "/__assets__/" <> Assets.entry("app.js")) |> call([])
      assert conn.status == 200
    end

    test "unknown files are 404" do
      for path <- [
            "/__assets__/nope.js",
            "/__assets__/manifest.json",
            "/__assets__/THIRD_PARTY_LICENSES.txt",
            "/__assets__",
            "/__assets__/a/b.js"
          ] do
        conn = mounted(:get, path) |> call([])
        assert conn.status == 404, path
      end
    end

    test "path traversal is 404" do
      conn = conn(:get, "/graphiql/__assets__/x")

      for path_info <- [
            ["__assets__", "..", "manifest.json"],
            ["__assets__", "..", "..", "mix.exs"],
            ["__assets__", "../../mix.exs"],
            ["__assets__", "%2e%2e", "mix.exs"]
          ] do
        conn = %{conn | script_name: ["graphiql"], path_info: path_info} |> call([])
        assert conn.status == 404, inspect(path_info)
      end
    end

    test "POST to an asset is 404" do
      conn = mounted(:post, "/__assets__/" <> Assets.entry("app.js")) |> call([])
      assert conn.status == 404
    end
  end

  describe "init/1 validation" do
    test "rejects a bad theme" do
      assert_raise ArgumentError,
                   "invalid :theme option for AbsintheGraphiQL.Plug: expected one of :system, :light or :dark, got: :blue",
                   fn -> AbsintheGraphiQL.Plug.init(schema: Schema, theme: :blue) end
    end

    test "rejects non-boolean flags" do
      for key <- [:query_builder, :history, :collections, :should_persist_headers] do
        assert_raise ArgumentError,
                     ~r/invalid #{inspect(key)} option .* expected a boolean, got: "yes"/,
                     fn ->
                       AbsintheGraphiQL.Plug.init([{:schema, Schema}, {key, "yes"}])
                     end
      end
    end

    test "rejects a bad csp" do
      assert_raise ArgumentError,
                   ~r/invalid :csp option .* expected true, false or a policy string/,
                   fn ->
                     AbsintheGraphiQL.Plug.init(schema: Schema, csp: :strict)
                   end
    end

    test "rejects bad dynamic values" do
      assert_raise ArgumentError,
                   ~r/invalid :socket_url option .* expected a string, a function/,
                   fn ->
                     AbsintheGraphiQL.Plug.init(schema: Schema, socket_url: 4000)
                   end

      assert_raise ArgumentError, ~r/invalid :socket_params option .* expected a map/, fn ->
        AbsintheGraphiQL.Plug.init(schema: Schema, socket_params: [token: "x"])
      end

      assert_raise ArgumentError,
                   ~r/invalid :default_headers option .* expected a map or a JSON string/,
                   fn ->
                     AbsintheGraphiQL.Plug.init(schema: Schema, default_headers: [{"a", "b"}])
                   end

      assert_raise ArgumentError, ~r/invalid :default_url option/, fn ->
        AbsintheGraphiQL.Plug.init(schema: Schema, default_url: fn _a, _b -> "x" end)
      end
    end

    test "rejects a bad title and socket" do
      assert_raise ArgumentError, ~r/invalid :title option/, fn ->
        AbsintheGraphiQL.Plug.init(schema: Schema, title: 1)
      end

      assert_raise ArgumentError, ~r/invalid :socket option .* expected a socket module/, fn ->
        AbsintheGraphiQL.Plug.init(schema: Schema, socket: "/socket")
      end
    end

    test "Absinthe.Plug validation still applies" do
      assert_raise ArgumentError, ~r/is not a valid `Absinthe.Schema`/, fn ->
        AbsintheGraphiQL.Plug.init(schema: "nope")
      end
    end
  end
end
