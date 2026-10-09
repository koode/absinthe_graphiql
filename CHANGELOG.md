# Changelog

## 0.1.0

First release.

- `AbsintheGraphiQL.Plug` serves the GraphiQL 6 IDE (`graphiql@6.0.0-rc.1`) for an
  Absinthe schema and passes all other requests to `Absinthe.Plug`.
- The bundle is self-hosted: scripts, Monaco web workers, CSS and fonts are served
  from `<mount>/__assets__/` with content-hashed names.
- Query builder, history, collections and documentation explorer.
- Subscriptions over the `absinthe_phoenix` channel protocol, with `:socket_url`,
  `:socket` and `:socket_params`. Running subscriptions are sent again after a
  reconnect.
- Options `:default_url`, `:default_query`, `:default_variables`, `:default_headers`,
  `:title`, `:theme`, `:query_builder`, `:history`, `:collections`,
  `:should_persist_headers` and `:csp`.
- A strict `content-security-policy` header on the IDE page by default.
