// Entry point of the GraphiQL page served by AbsintheGraphiQL.Plug.
//
// The plug renders <div id="graphiql" data-config="{...}"> with HTML-escaped
// JSON; nothing else on the page is executable inline code.

import "graphiql/style.css";

import { COLLECTIONS_PLUGIN, GraphiQL, HISTORY_PLUGIN, QUERY_BUILDER_PLUGIN } from "graphiql";
import { Socket } from "phoenix";
import { createRoot } from "react-dom/client";

import { createAbsintheSocketClient, createUnavailableSubscriptionClient } from "./absinthe_socket.js";
import { createAbsintheTransport } from "./transport.js";

const root = document.getElementById("graphiql");
const config = JSON.parse(root.dataset.config);

// Monaco runs its language services in web workers. Load them from the
// plug's asset route; never from a CDN or a blob.
globalThis.MonacoEnvironment = {
  getWorker(_workerId, label) {
    switch (label) {
      case "json":
        return new Worker(config.workers.json, { name: "json" });
      case "graphql":
        return new Worker(config.workers.graphql, { name: "graphql" });
      default:
        return new Worker(config.workers.editor, { name: "editor" });
    }
  },
};

const url = new URL(config.url, location.href).toString();

function socketEndpoint(socketUrl) {
  const resolved = new URL(socketUrl, location.href);
  if (resolved.protocol === "http:") resolved.protocol = "ws:";
  if (resolved.protocol === "https:") resolved.protocol = "wss:";
  return resolved.toString();
}

let subscriptionClient;
if (config.socketUrl) {
  const endpoint = socketEndpoint(config.socketUrl);
  const socket = new Socket(endpoint, { params: config.socketParams || {} });
  subscriptionClient = createAbsintheSocketClient({ socket, url: endpoint });
} else {
  subscriptionClient = createUnavailableSubscriptionClient(
    "Subscriptions are not available: this GraphiQL has no socket. " +
      "Set the :socket_url (or :socket) option of AbsintheGraphiQL.Plug.",
  );
}

const transport = createAbsintheTransport({ url, subscriptionClient });

const plugins = [
  config.history && HISTORY_PLUGIN,
  config.queryBuilder && QUERY_BUILDER_PLUGIN,
  config.collections && COLLECTIONS_PLUGIN,
].filter(Boolean);

const props = {
  transport,
  plugins,
  shouldPersistHeaders: config.shouldPersistHeaders,
  isHeadersEditorEnabled: true,
};

if (config.theme === "light" || config.theme === "dark") props.forcedTheme = config.theme;
if (config.defaultQuery != null) props.defaultQuery = config.defaultQuery;
if (config.defaultHeaders != null) props.defaultHeaders = config.defaultHeaders;
if (config.defaultQuery != null || config.defaultVariables != null || config.defaultHeaders != null) {
  props.defaultTabs = [
    {
      query: config.defaultQuery ?? undefined,
      variables: config.defaultVariables ?? undefined,
      headers: config.defaultHeaders ?? undefined,
    },
  ];
}

createRoot(root).render(<GraphiQL {...props} />);
