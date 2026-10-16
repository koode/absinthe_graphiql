# Changelog

## 0.2.0

- Add the `:visible_plugin` option, which opens a side panel plugin (`:query_builder`,
  `:doc_explorer`, `:history` or `:collections`) when the page loads.
- Add the `:default_tabs` option, which opens the IDE with several tabs, each with its
  own query, variables and headers.

## 0.1.1

- Update the bundled GraphiQL to `graphiql@6.0.0-rc.2`, with `@graphiql/react@1.0.0-rc.3`,
  `@graphiql/plugin-query-builder@1.0.0-rc.3`, `@graphiql/plugin-history@1.0.0-rc.2` and
  `@graphiql/plugin-doc-explorer@1.0.0-rc.2`. GraphiQL now uses the stable React Compiler
  runtime, and the query builder follows the operation under the cursor.

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
