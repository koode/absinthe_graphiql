// Turns the page config from AbsintheGraphiQL.Plug into GraphiQL props.
// Kept free of GraphiQL imports so it can be tested without a browser: the
// plugin objects are passed in.

// Builds the plugin list, the visible plugin and the tab props.
//
// `available` maps the plug's plugin names to GraphiQL plugin objects:
// { query_builder, doc_explorer, history, collections }.
export function graphiqlProps(config, available) {
  const plugins = [
    config.history && available.history,
    config.queryBuilder && available.query_builder,
    config.collections && available.collections,
  ].filter(Boolean);

  const props = {
    plugins,
    shouldPersistHeaders: config.shouldPersistHeaders,
    isHeadersEditorEnabled: true,
  };

  if (config.theme === "light" || config.theme === "dark") props.forcedTheme = config.theme;

  // Pass the plugin object, not its title, so a renamed title in a GraphiQL
  // update cannot silently open nothing. The plug only sends names of
  // enabled plugins.
  const visiblePlugin = config.visiblePlugin != null && available[config.visiblePlugin];
  if (visiblePlugin && plugins.concat(available.doc_explorer).includes(visiblePlugin)) {
    props.visiblePlugin = visiblePlugin;
  }

  if (config.defaultQuery != null) props.defaultQuery = config.defaultQuery;
  if (config.defaultHeaders != null) props.defaultHeaders = config.defaultHeaders;

  if (config.defaultTabs != null) {
    // GraphiQL only applies defaultHeaders to tabs it creates later, so give
    // the initial tabs the default headers here.
    props.defaultTabs = config.defaultTabs.map((tab) => ({
      query: tab.query ?? undefined,
      variables: tab.variables ?? undefined,
      headers: tab.headers ?? config.defaultHeaders ?? undefined,
    }));
  } else if (config.defaultQuery != null || config.defaultVariables != null || config.defaultHeaders != null) {
    props.defaultTabs = [
      {
        query: config.defaultQuery ?? undefined,
        variables: config.defaultVariables ?? undefined,
        headers: config.defaultHeaders ?? undefined,
      },
    ];
  }

  return props;
}
