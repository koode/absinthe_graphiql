// The GraphiQL transport: queries and mutations go over HTTP to the plug,
// subscriptions go over the Phoenix socket.
//
// @graphiql/toolkit's createTransport does the routing: it parses the
// document with graphql-js, picks the operation named by `operationName`
// (or the only operation), and hands subscriptions to `subscriptionClient`.
// test/transport.test.js pins that behavior, so a GraphiQL upgrade that
// changes it fails the build.

import { createTransport } from "@graphiql/toolkit";

/**
 * @param {object} options
 * @param {string} options.url - absolute HTTP endpoint
 * @param {{iterate: Function}} options.subscriptionClient
 * @param {typeof fetch} [options.fetch]
 */
export function createAbsintheTransport({ url, subscriptionClient, fetch: fetchImpl }) {
  const baseFetch = fetchImpl || ((...args) => globalThis.fetch(...args));
  return createTransport({
    url,
    subscriptionClient,
    // Absinthe does not implement @defer/@stream over multipart/mixed.
    enableIncrementalDelivery: false,
    // Send cookies to the same origin only, so session auth works and a
    // cross-origin default_url never receives them.
    fetch: (input, init = {}) => baseFetch(input, { ...init, credentials: "same-origin" }),
  });
}
