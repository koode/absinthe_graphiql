# AbsintheGraphiQL

A plug that serves the [GraphiQL 6](https://github.com/graphql/graphiql) IDE for an
[Absinthe](https://github.com/absinthe-graphql/absinthe) schema. It replaces
`Absinthe.Plug.GraphiQL` from `absinthe_plug`, which loads an old GraphiQL from a CDN.

- GraphiQL 6 with the Monaco editor, the documentation explorer, the query builder,
  history and collections.
- Every script, web worker, stylesheet and font is in this package and served by the
  plug. The page makes no requests to other hosts and works without internet access.
- Subscriptions run over the Absinthe channel of your Phoenix socket
  (`absinthe_phoenix`).
- A strict `content-security-policy` header by default.

> **GraphiQL 6 is a release candidate.** This package bundles `graphiql@6.0.0-rc.2`
> and its `1.0.0-rc` companion packages. Expect changes when GraphiQL 6.0.0 ships.

## Installation

```elixir
def deps do
  [
    {:absinthe_graphiql, "~> 0.1.0"}
  ]
end
```

You do not need Node.js. The built bundle is part of the package.

## Usage

Mount the plug where you mounted `Absinthe.Plug.GraphiQL`:

```elixir
# lib/my_app_web/router.ex
forward "/graphiql", AbsintheGraphiQL.Plug,
  schema: MyAppWeb.Schema,
  socket_url: "/socket"
```

A browser `GET /graphiql` gets the IDE. Every other request goes to
`Absinthe.Plug.call/2`, so the same path also executes queries and mutations sent with
`POST` or `GET /graphiql?query=...`. The plug serves its assets at
`/graphiql/__assets__/`.

The endpoint must parse request bodies before the router, as for `Absinthe.Plug`:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
  pass: ["*/*"],
  json_decoder: Jason
```

Most apps only mount the IDE in development:

```elixir
if Mix.env() == :dev do
  forward "/graphiql", AbsintheGraphiQL.Plug, schema: MyAppWeb.Schema, socket_url: "/socket"
end
```

## Options

All `Absinthe.Plug` options (`:schema`, `:context`, `:json_codec`, `:pipeline` and so
on) are accepted and passed on.

| Option | Default | Description |
| --- | --- | --- |
| `:default_url` | mount path | HTTP endpoint for queries and mutations. A relative URL is resolved against the page URL in the browser. |
| `:socket_url` | `nil` | Path or URL of the Phoenix socket, for example `"/socket"`. `http(s)://` becomes `ws(s)://`. Without a socket, subscriptions show an error in the result pane. |
| `:socket` | `nil` | Socket module, for example `MyAppWeb.UserSocket`. When `:socket_url` is not set, the path is looked up in the Phoenix endpoint of the request. |
| `:socket_params` | `%{}` | Map passed as `params` to the Phoenix `Socket`. Written into the page HTML. |
| `:default_query` | GraphiQL's welcome text | Query of the first tab when the browser has no saved state. |
| `:default_variables` | `nil` | Variables of that tab. A map or a JSON string. |
| `:default_headers` | `nil` | Request headers of new tabs. A map or a JSON string. |
| `:default_tabs` | `nil` | Tabs to open when the browser has no saved state, instead of one tab from `:default_query`. A list of maps with the optional keys `:query`, `:variables` and `:headers` (variables and headers as a map or a JSON string). A tab without `:headers` gets `:default_headers`. Cannot be used together with `:default_query` or `:default_variables`. |
| `:visible_plugin` | `nil` | Side panel plugin to open when the page loads: `:query_builder`, `:doc_explorer`, `:history` or `:collections`. `nil` opens the plugin the user had open last time. The plugin must be enabled. |
| `:title` | `"GraphiQL"` | Page title. |
| `:theme` | `:system` | `:system` follows the operating system and lets the user change the theme in the settings dialog. `:light` and `:dark` force a theme and hide that setting. |
| `:query_builder` | `true` | Show the query builder. |
| `:history` | `true` | Show the history. |
| `:collections` | `true` | Show collections. They are stored in the browser's `localStorage`; no account or server is involved. |
| `:should_persist_headers` | `false` | Save the headers editor in `localStorage`. Off by default because headers often hold tokens. |
| `:csp` | `true` | `true` sends a strict `content-security-policy` header with the page, `false` sends none, a string is sent as it is. |

`:default_url`, `:socket_url`, `:socket_params`, `:default_query`, `:default_variables`,
`:default_headers` and `:default_tabs` can also be a function or a `{module, function}`
tuple. The plug
calls it for every page request: with the `Plug.Conn` when it has arity 1, with no
arguments when it has arity 0. When a `{module, function}` tuple exports both arities,
arity 1 is used.

```elixir
forward "/graphiql", AbsintheGraphiQL.Plug,
  schema: MyAppWeb.Schema,
  default_headers: {__MODULE__, :graphiql_headers}

def graphiql_headers(conn) do
  %{"x-csrf-token" => Plug.CSRFProtection.get_csrf_token()}
end
```

Open the IDE with the query builder and two example tabs:

```elixir
forward "/graphiql", AbsintheGraphiQL.Plug,
  schema: MyAppWeb.Schema,
  visible_plugin: :query_builder,
  default_tabs: [
    %{query: "query Me {\n  me {\n    id\n    name\n  }\n}\n"},
    %{query: "query Post($id: ID!) {\n  post(id: $id) {\n    title\n  }\n}\n", variables: %{"id" => "1"}}
  ]
```

GraphiQL saves the open tabs in `localStorage`, so `:default_query` and `:default_tabs`
only show in a browser that has no saved tabs for the page's origin. `:visible_plugin`
applies on every page load.

GraphiQL stores the theme setting in `localStorage` under `graphiql:settings`, shared by
every GraphiQL page on the same origin. A page with a forced `:light` or `:dark` theme
writes that theme there, so a `:system` page on the same origin opened later starts
with it until the user changes it in the settings dialog.

A Phoenix router calls `init/1` at compile time, and an anonymous function cannot be
stored in compiled code. In a router, use a `{module, function}` tuple or a captured
named function such as `&MyApp.GraphiQL.headers/1`.

## Subscriptions

Subscriptions use the Phoenix channel protocol of `absinthe_phoenix`. Set up the socket
as described in the [Absinthe subscription guide](https://hexdocs.pm/absinthe/subscriptions.html):

```elixir
# lib/my_app_web/channels/user_socket.ex
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: MyAppWeb.Schema

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

# lib/my_app_web/endpoint.ex
use Absinthe.Phoenix.Endpoint
socket "/socket", MyAppWeb.UserSocket, websocket: true
```

Then give the plug the socket path with `socket_url: "/socket"`, or the module with
`socket: MyAppWeb.UserSocket`.

How the IDE uses the socket:

- Queries and mutations always go over HTTP to `:default_url`, with the headers from the
  headers editor. Cookies are sent to the same origin only.
- A subscription joins `__absinthe__:control`, pushes the document, and shows every
  `subscription:data` event in the result pane. Validation errors from the server show
  there too. Stopping the operation in GraphiQL sends `unsubscribe`.
- When the document has several operations, the IDE sends only the selected one and
  the fragments it uses, because the Absinthe channel ignores `operationName`.
- When the socket reconnects, the IDE sends every running subscription again. Events
  published while the socket was disconnected are lost.
- The socket connects when the first subscription starts, not when the page loads.
- A subscription sent to the HTTP endpoint gets an error, as with `Absinthe.Plug.GraphiQL`.

### Socket authentication

The headers editor does not apply to the socket. Pass credentials with
`:socket_params`, which become the params of `connect/3` in your socket:

```elixir
forward "/graphiql", AbsintheGraphiQL.Plug,
  schema: MyAppWeb.Schema,
  socket_url: "/socket",
  socket_params: {MyAppWeb.GraphiQL, :socket_params}

defmodule MyAppWeb.GraphiQL do
  def socket_params(conn) do
    user = conn.assigns.current_user
    %{"token" => Phoenix.Token.sign(conn, "user socket", user.id)}
  end
end
```

```elixir
def connect(%{"token" => token}, socket, _connect_info) do
  case Phoenix.Token.verify(socket, "user socket", token, max_age: 86_400) do
    {:ok, user_id} -> {:ok, Absinthe.Phoenix.Socket.put_options(socket, context: %{user_id: user_id})}
    {:error, _} -> :error
  end
end
```

The params are written into the page HTML, so anyone who can see the page can read
them. Use short-lived tokens, and make sure the page itself requires the same login.
The page is sent with `cache-control: no-store`.

## Self-hosting and Content-Security-Policy

The bundle in `priv/static` holds GraphiQL, React, Monaco, its three web workers
(editor, JSON and GraphQL), the Phoenix client, the CSS and the Roboto, Fira Code and
codicon fonts. File names carry a content hash, and the plug serves them with
`cache-control: public, max-age=31536000, immutable`. Unknown files get a 404.
`priv/static/THIRD_PARTY_LICENSES.txt` lists the license of every bundled package and
font.

The page has no inline scripts. The plug passes its configuration as HTML-escaped JSON
in a `data-config` attribute. The default policy is:

```
default-src 'self'; script-src 'self'; worker-src 'self';
style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:;
connect-src 'self' ws://<host> wss://<host> <origins of absolute :default_url and :socket_url>;
base-uri 'none'; form-action 'none'; frame-ancestors 'self'
```

`<host>` is the `host` request header. Monaco adds `<style>` elements at run time, so
`style-src` needs `'unsafe-inline'`. Set `csp: false` when your app already sends its
own policy for this path, or pass your own policy as a string.

The bundle is large because Monaco is large: about 8 MB in 66 files, about 2.3 MB
gzipped. The page loads most of it on demand. Compress responses in your endpoint or
proxy; Bandit does so by default.

## Updating GraphiQL

The bundle is built from `assets/` with esbuild. To update GraphiQL or another
dependency:

1. Change the exact versions in `assets/package.json` and run
   `mise exec -- npm install` in `assets/` to update `package-lock.json`.
2. Run `mise exec -- mix assets.build`. It runs `npm ci` and `npm run build`, which
   rewrites `priv/static/`, including `manifest.json` and `THIRD_PARTY_LICENSES.txt`.
3. Run `mise exec -- mix assets.test` and `mise exec -- mix test`, then open the
   example app and check the IDE.
4. Commit `assets/package-lock.json` and `priv/static/`.

`mise.toml` pins Erlang, Elixir and Node.js.

## Example app

`examples/dev_server.exs` is a single-file Phoenix app with a query, a mutation and a
subscription:

```sh
mise exec -- elixir examples/dev_server.exs
```

Open <http://localhost:4401/graphiql>, run the `OnMessage` subscription, and send a
message from a terminal:

```sh
curl -s localhost:4401/graphiql -H 'content-type: application/json' \
  -d '{"query":"mutation { addMessage(input: {body: \"hi\"}) { id body } }"}'
```

Set `THEME=light` or `THEME=dark` to force a theme, and `PORT` to use another port.

## Development

```sh
mise trust && mise install
mise exec -- mix deps.get
mise exec -- mix test
mise exec -- mix assets.test   # vitest, needs assets/node_modules (npm ci)
mise exec -- mix dialyzer
```

See `CONTRIBUTING.md` for the checks to run before a pull request and the
Conventional Commits format that commit messages use.

## License

MIT. See `LICENSE`. The bundled third-party software is listed in
`priv/static/THIRD_PARTY_LICENSES.txt`.
