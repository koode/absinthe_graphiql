defmodule AbsintheGraphiQL.Plug do
  @moduledoc """
  Serves the GraphiQL 6 IDE for an Absinthe schema and executes queries at
  the same mount point.

  It does what `Absinthe.Plug.GraphiQL` does, with a current GraphiQL that is
  bundled into this package instead of loaded from a CDN:

    * A browser `GET` (the `accept` header contains `text/html` and there is
      no `query` parameter) gets the IDE page.
    * Every other request goes to `Absinthe.Plug.call/2`, so the mount point
      also executes queries and mutations sent with `POST` or `GET ?query=`.
    * `GET <mount>/__assets__/<file>` serves the bundled JavaScript, CSS,
      web workers and fonts.

  Subscriptions run over the Absinthe Phoenix channel of your socket (see
  `:socket_url`). A subscription sent to the HTTP endpoint gets an error.

  ## Usage

      forward "/graphiql", AbsintheGraphiQL.Plug,
        schema: MyAppWeb.Schema,
        socket_url: "/socket"

  ## Options

  All `Absinthe.Plug` options are accepted and passed on, for example
  `:schema`, `:context`, `:json_codec` and `:pipeline`. The options of this
  plug are:

    * `:default_url` - the HTTP endpoint the IDE sends queries and mutations
      to. Defaults to the mount path of this plug. A relative URL is resolved
      against the page URL in the browser.
    * `:socket_url` - the path or URL of the Phoenix socket that has
      `use Absinthe.Phoenix.Socket`, for example `"/socket"`. Without it,
      subscriptions show an error in the result pane; queries still work.
      `http(s)://` URLs are converted to `ws(s)://`.
    * `:socket` - the socket module, for example `MyAppWeb.UserSocket`. When
      `:socket_url` is not set, the path is looked up in the Phoenix endpoint
      of the request, like `Absinthe.Plug.GraphiQL` does.
    * `:socket_params` - a map passed as `params` to the Phoenix `Socket`
      constructor, for example an auth token. The values are written into the
      HTML of the page.
    * `:default_query` - the query of the first tab when the browser has no
      saved state. A string.
    * `:default_variables` - the variables of that tab. A map (encoded as
      JSON) or a JSON string.
    * `:default_headers` - the request headers of new tabs. A map of header
      names to values (encoded as JSON) or a JSON string.
    * `:title` - the page title. Defaults to `"GraphiQL"`.
    * `:theme` - `:system` (default) follows the operating system and lets the
      user pick a theme in the settings dialog. `:light` and `:dark` force
      that theme and hide the theme setting.
    * `:query_builder` - show the query builder plugin. Defaults to `true`.
    * `:history` - show the history plugin. Defaults to `true`.
    * `:collections` - show the collections plugin, which saves operations in
      the browser's `localStorage`. Defaults to `true`.
    * `:should_persist_headers` - save the headers editor in `localStorage`.
      Defaults to `false`, because headers often hold tokens.
    * `:csp` - the `content-security-policy` header of the IDE page. `true`
      (default) builds a strict policy, `false` sends no header, and a string
      is sent as it is.

  `:default_url`, `:socket_url`, `:socket_params`, `:default_query`,
  `:default_variables` and `:default_headers` can also be a function or a
  `{module, function}` tuple. It is called for every page request, with the
  `Plug.Conn` when it has arity 1 and with no arguments when it has arity 0:

      forward "/graphiql", AbsintheGraphiQL.Plug,
        schema: MyAppWeb.Schema,
        socket_url: "/socket",
        socket_params: {__MODULE__, :graphiql_socket_params}

      def graphiql_socket_params(conn) do
        %{"token" => Phoenix.Token.sign(conn, "user socket", conn.assigns.current_user.id)}
      end

  Phoenix routers call `init/1` at compile time, so use a `{module, function}`
  tuple or a captured named function (`&MyApp.Graphiql.params/1`) there; an
  anonymous function cannot be stored in compiled code.
  """

  @behaviour Plug

  import Plug.Conn

  alias AbsintheGraphiQL.Assets

  @dynamic_options [
    :default_url,
    :socket_url,
    :socket_params,
    :default_query,
    :default_variables,
    :default_headers
  ]

  @boolean_options [
    query_builder: true,
    history: true,
    collections: true,
    should_persist_headers: false
  ]

  @themes [:system, :light, :dark]

  @asset_cache_control "public, max-age=31536000, immutable"

  @type dynamic(value) ::
          value | (-> value) | (Plug.Conn.t() -> value) | {module(), atom()}

  @type opts :: [
          {:default_url, dynamic(String.t())}
          | {:socket_url, dynamic(String.t())}
          | {:socket, module()}
          | {:socket_params, dynamic(map())}
          | {:default_query, dynamic(String.t())}
          | {:default_variables, dynamic(map() | String.t())}
          | {:default_headers, dynamic(map() | String.t())}
          | {:title, String.t()}
          | {:theme, :system | :light | :dark}
          | {:query_builder, boolean()}
          | {:history, boolean()}
          | {:collections, boolean()}
          | {:should_persist_headers, boolean()}
          | {:csp, boolean() | String.t()}
          | {atom(), term()}
        ]

  @impl Plug
  @spec init(opts()) :: map()
  def init(opts) when is_list(opts) do
    graphiql = validate_options!(opts)

    opts
    |> Absinthe.Plug.init()
    |> Map.put(:graphiql, graphiql)
    |> set_pipeline()
  end

  @impl Plug
  def call(%Plug.Conn{path_info: ["__assets__" | rest]} = conn, config) do
    serve_asset(conn, rest, config)
  end

  def call(conn, config) do
    conn = fetch_query_params(conn)

    if ide_request?(conn) do
      render_ide(conn, config)
    else
      Absinthe.Plug.call(conn, config)
    end
  end

  @doc false
  # Absinthe.Plug calls this to build the pipeline (see set_pipeline/1).
  def pipeline(config, opts) do
    {module, fun} = config.additional_pipeline

    module
    |> apply(fun, [config, opts])
    |> Absinthe.Pipeline.insert_after(
      Absinthe.Phase.Document.CurrentOperation,
      [AbsintheGraphiQL.NoSubscriptionOnHTTP]
    )
  end

  defp set_pipeline(config) do
    config
    |> Map.put(:additional_pipeline, config.pipeline)
    |> Map.put(:pipeline, {__MODULE__, :pipeline})
  end

  ## Options

  defp validate_options!(opts) do
    dynamic =
      Map.new(@dynamic_options, fn key ->
        value = Keyword.get(opts, key)
        validate_dynamic!(key, value)
        {key, value}
      end)

    booleans =
      Map.new(@boolean_options, fn {key, default} ->
        case Keyword.get(opts, key, default) do
          value when is_boolean(value) -> {key, value}
          other -> invalid!(key, other, "a boolean")
        end
      end)

    socket =
      case Keyword.get(opts, :socket) do
        socket when is_atom(socket) -> socket
        other -> invalid!(:socket, other, "a socket module, for example MyAppWeb.UserSocket")
      end

    title =
      case Keyword.get(opts, :title, "GraphiQL") do
        title when is_binary(title) -> title
        other -> invalid!(:title, other, "a string")
      end

    theme =
      case Keyword.get(opts, :theme, :system) do
        theme when theme in @themes -> theme
        other -> invalid!(:theme, other, "one of :system, :light or :dark")
      end

    csp =
      case Keyword.get(opts, :csp, true) do
        csp when is_boolean(csp) or is_binary(csp) -> csp
        other -> invalid!(:csp, other, "true, false or a policy string")
      end

    static =
      Plug.Static.init(
        at: "/__assets__",
        from: {:absinthe_graphiql, "priv/static"},
        gzip: false,
        cache_control_for_etags: @asset_cache_control
      )

    dynamic
    |> Map.merge(booleans)
    |> Map.merge(%{socket: socket, title: title, theme: theme, csp: csp, static: static})
  end

  defp validate_dynamic!(_key, nil), do: :ok
  defp validate_dynamic!(_key, fun) when is_function(fun, 0) or is_function(fun, 1), do: :ok
  defp validate_dynamic!(_key, {mod, fun}) when is_atom(mod) and is_atom(fun), do: :ok

  defp validate_dynamic!(key, value) do
    case check_value(key, value) do
      :ok ->
        :ok

      {:error, expected} ->
        invalid!(
          key,
          value,
          "#{expected}, a function of arity 0 or 1, or a {module, function} tuple"
        )
    end
  end

  defp check_value(key, value) when key in [:default_url, :socket_url, :default_query] do
    if is_binary(value), do: :ok, else: {:error, "a string"}
  end

  defp check_value(:socket_params, value) do
    if is_map(value), do: :ok, else: {:error, "a map"}
  end

  defp check_value(key, value) when key in [:default_variables, :default_headers] do
    if is_map(value) or is_binary(value), do: :ok, else: {:error, "a map or a JSON string"}
  end

  defp invalid!(key, value, expected) do
    raise ArgumentError,
          "invalid #{inspect(key)} option for AbsintheGraphiQL.Plug: expected #{expected}, got: #{inspect(value)}"
  end

  defp resolve!(conn, key, value) do
    resolved =
      case value do
        fun when is_function(fun, 1) ->
          fun.(conn)

        fun when is_function(fun, 0) ->
          fun.()

        {mod, fun} when is_atom(mod) and is_atom(fun) ->
          Code.ensure_loaded(mod)

          cond do
            function_exported?(mod, fun, 1) ->
              apply(mod, fun, [conn])

            function_exported?(mod, fun, 0) ->
              apply(mod, fun, [])

            true ->
              raise ArgumentError,
                    "invalid #{inspect(key)} option for AbsintheGraphiQL.Plug: " <>
                      "#{inspect(mod)}.#{fun}/1 or #{inspect(mod)}.#{fun}/0 is not exported"
          end

        other ->
          other
      end

    if resolved != nil do
      case check_value(key, resolved) do
        :ok ->
          :ok

        {:error, expected} ->
          raise ArgumentError,
                "invalid #{inspect(key)} option for AbsintheGraphiQL.Plug: expected the " <>
                  "function to return #{expected} or nil, got: #{inspect(resolved)}"
      end
    end

    resolved
  end

  ## IDE page

  defp ide_request?(conn) do
    conn.method == "GET" and not Map.has_key?(conn.query_params, "query") and accepts_html?(conn)
  end

  defp accepts_html?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "text/html"))
  end

  defp render_ide(conn, %{graphiql: opts} = config) do
    mount = mount_path(conn)
    resolved = Map.new(@dynamic_options, &{&1, resolve!(conn, &1, Map.fetch!(opts, &1))})

    default_url = resolved.default_url || mount
    socket_url = resolved.socket_url || socket_path(conn, opts.socket)

    page_config = %{
      url: default_url,
      socketUrl: socket_url,
      socketParams: resolved.socket_params || %{},
      theme: opts.theme,
      queryBuilder: opts.query_builder,
      history: opts.history,
      collections: opts.collections,
      shouldPersistHeaders: opts.should_persist_headers,
      defaultQuery: resolved.default_query,
      defaultVariables: json_text(resolved.default_variables, config),
      defaultHeaders: json_text(resolved.default_headers, config),
      workers: %{
        editor: asset_url(mount, Assets.entry("editor.worker.js")),
        json: asset_url(mount, Assets.entry("json.worker.js")),
        graphql: asset_url(mount, Assets.entry("graphql.worker.js"))
      }
    }

    html = page(mount, opts.title, Jason.encode!(page_config))

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-store")
    |> put_csp(opts.csp, default_url, socket_url)
    |> send_resp(200, html)
  end

  defp json_text(nil, _config), do: nil
  defp json_text(text, _config) when is_binary(text), do: text

  defp json_text(map, config) when is_map(map),
    do: config.json_codec.module.encode!(map, pretty: true)

  defp page(mount, title, config_json) do
    css = asset_url(mount, Assets.entry("app.css"))
    js = asset_url(mount, Assets.entry("app.js"))

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(title)}</title>
        <link rel="stylesheet" href="#{escape(css)}">
        <script type="module" src="#{escape(js)}"></script>
        <style>
          html, body, #graphiql { height: 100%; margin: 0; }
          .absinthe-graphiql-loading { display: flex; height: 100%; align-items: center; justify-content: center; font-family: system-ui, sans-serif; color: #888; }
        </style>
      </head>
      <body>
        <div id="graphiql" data-config="#{escape(config_json)}">
          <div class="absinthe-graphiql-loading">Loading GraphiQL&hellip;</div>
        </div>
      </body>
    </html>
    """
  end

  defp escape(text), do: text |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()

  defp asset_url(mount, file), do: String.trim_trailing(mount, "/") <> "/__assets__/" <> file

  defp mount_path(conn), do: "/" <> Enum.join(conn.script_name, "/")

  defp socket_path(_conn, nil), do: nil

  defp socket_path(conn, socket) do
    with endpoint when is_atom(endpoint) and not is_nil(endpoint) <-
           conn.private[:phoenix_endpoint],
         true <- function_exported?(endpoint, :__sockets__, 0) do
      Enum.find_value(endpoint.__sockets__(), fn
        {path, ^socket, _opts} -> path
        {path, ^socket} -> path
        _ -> nil
      end)
    else
      _ -> nil
    end
  end

  ## Content-Security-Policy

  defp put_csp(conn, false, _default_url, _socket_url), do: conn

  defp put_csp(conn, policy, _default_url, _socket_url) when is_binary(policy),
    do: put_resp_header(conn, "content-security-policy", policy)

  defp put_csp(conn, true, default_url, socket_url) do
    connect_src =
      ["'self'"] ++
        same_origin_websockets(conn) ++
        external_origins(default_url, ["http", "https"]) ++
        external_origins(socket_url, ["ws", "wss"])

    policy =
      Enum.join(
        [
          "default-src 'self'",
          "script-src 'self'",
          "worker-src 'self'",
          "style-src 'self' 'unsafe-inline'",
          "font-src 'self'",
          "img-src 'self' data:",
          "connect-src " <> Enum.join(Enum.uniq(connect_src), " "),
          "base-uri 'none'",
          "form-action 'none'",
          "frame-ancestors 'self'"
        ],
        "; "
      )

    put_resp_header(conn, "content-security-policy", policy)
  end

  # The browser connects to the socket on the host it loaded the page from.
  # 'self' covers ws: and wss: only in browsers that implement CSP level 3,
  # so list them explicitly.
  defp same_origin_websockets(conn) do
    host =
      case get_req_header(conn, "host") do
        [host | _] -> host
        [] -> host_with_port(conn)
      end

    if safe_host?(host), do: ["ws://" <> host, "wss://" <> host], else: []
  end

  defp host_with_port(%Plug.Conn{host: host, port: port, scheme: scheme}) do
    if port == URI.default_port(to_string(scheme)), do: host, else: "#{host}:#{port}"
  end

  # Origins of absolute URLs; relative URLs are same-origin and need nothing.
  # A protocol-relative URL ("//host/path") gets both schemes.
  defp external_origins(nil, _schemes), do: []

  defp external_origins(url, [plain, secure]) do
    uri = URI.parse(url)

    schemes =
      case uri.scheme do
        nil -> [plain, secure]
        scheme when scheme in ["http", "ws"] -> [plain]
        scheme when scheme in ["https", "wss"] -> [secure]
        _ -> []
      end

    authority =
      cond do
        is_nil(uri.host) or uri.host == "" -> nil
        explicit_port?(url, uri) -> "#{host_for_csp(uri.host)}:#{uri.port}"
        true -> host_for_csp(uri.host)
      end

    if authority && safe_host?(authority) do
      Enum.map(schemes, &"#{&1}://#{authority}")
    else
      []
    end
  end

  defp host_for_csp(host), do: if(String.contains?(host, ":"), do: "[#{host}]", else: host)

  defp explicit_port?(url, %URI{port: port}) when is_integer(port),
    do: String.contains?(url, ":#{port}")

  defp explicit_port?(_url, _uri), do: false

  # Keeps request data such as the host header from adding policy directives.
  defp safe_host?(host), do: Regex.match?(~r/\A[A-Za-z0-9.\-\[\]:]+\z/, host)

  ## Assets

  defp serve_asset(conn, [file], %{graphiql: %{static: static}})
       when conn.method in ["GET", "HEAD"] do
    if Assets.file?(file) do
      conn = Plug.Static.call(conn, static)
      if conn.halted, do: conn, else: not_found(conn)
    else
      not_found(conn)
    end
  end

  defp serve_asset(conn, _rest, _config), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
    |> halt()
  end
end
