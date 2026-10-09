import { describe, expect, it, vi } from "vitest";

import { createUnavailableSubscriptionClient } from "../src/absinthe_socket.js";
import { createAbsintheTransport } from "../src/transport.js";

function fakeFetch(result = { data: { hello: "Hello, world!" } }) {
  return vi.fn(async () => new Response(JSON.stringify(result), { status: 200, headers: { "content-type": "application/json" } }));
}

function fakeSubscriptionClient(results = [{ data: { messageAdded: { body: "hi" } } }]) {
  const client = {
    requests: [],
    returned: 0,
    iterate(request) {
      client.requests.push(request);
      const queue = [...results];
      return {
        next: async () => (queue.length ? { done: false, value: queue.shift() } : { done: true, value: undefined }),
        return: async () => {
          client.returned++;
          return { done: true, value: undefined };
        },
        [Symbol.asyncIterator]() {
          return this;
        },
      };
    },
  };
  return client;
}

const URL = "http://localhost:4401/graphiql";

function isAsyncIterable(value) {
  return value != null && typeof value[Symbol.asyncIterator] === "function";
}

describe("createAbsintheTransport", () => {
  it("sends queries over HTTP with the editor headers and same-origin credentials", async () => {
    const fetch = fakeFetch();
    const subscriptionClient = fakeSubscriptionClient();
    const transport = createAbsintheTransport({ url: URL, subscriptionClient, fetch });

    const response = await transport.send({
      query: "{ hello }",
      variables: { a: 1 },
      headers: { authorization: "Bearer t" },
    });

    expect(response.body).toEqual({ data: { hello: "Hello, world!" } });
    expect(subscriptionClient.requests).toHaveLength(0);
    expect(fetch).toHaveBeenCalledTimes(1);

    const [url, init] = fetch.mock.calls[0];
    expect(url).toBe(URL);
    expect(init.method).toBe("POST");
    expect(init.credentials).toBe("same-origin");
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer t");
    expect(new Headers(init.headers).get("content-type")).toMatch(/application\/json/);
    expect(new Headers(init.headers).get("accept")).not.toMatch(/multipart/);
    expect(JSON.parse(init.body)).toMatchObject({ query: "{ hello }", variables: { a: 1 } });
  });

  it("sends mutations over HTTP", async () => {
    const fetch = fakeFetch({ data: { addMessage: { body: "x" } } });
    const subscriptionClient = fakeSubscriptionClient();
    const transport = createAbsintheTransport({ url: URL, subscriptionClient, fetch });

    const query = 'mutation { addMessage(input: {body: "x"}) { body } }';
    const response = await transport.send({ query });

    expect(response.body).toEqual({ data: { addMessage: { body: "x" } } });
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(subscriptionClient.requests).toHaveLength(0);
  });

  it("sends subscriptions over the socket client and yields its results", async () => {
    const fetch = fakeFetch();
    const subscriptionClient = fakeSubscriptionClient();
    const transport = createAbsintheTransport({ url: URL, subscriptionClient, fetch });

    const stream = transport.send({ query: "subscription { messageAdded { body } }", variables: { v: 1 } });
    expect(isAsyncIterable(stream)).toBe(true);

    const first = await stream[Symbol.asyncIterator]().next();
    expect(first.value.body).toEqual({ data: { messageAdded: { body: "hi" } } });
    expect(first.value.ok).toBe(true);
    expect(fetch).not.toHaveBeenCalled();
    expect(subscriptionClient.requests[0]).toMatchObject({
      query: "subscription { messageAdded { body } }",
      variables: { v: 1 },
    });
  });

  it("stopping the stream returns the socket iterator", async () => {
    const subscriptionClient = fakeSubscriptionClient();
    const transport = createAbsintheTransport({ url: URL, subscriptionClient, fetch: fakeFetch() });

    const iterator = transport.send({ query: "subscription { messageAdded { body } }" })[Symbol.asyncIterator]();
    await iterator.next();
    await iterator.return();
    expect(subscriptionClient.returned).toBe(1);
  });

  it("routes by operationName when the document has several operations", async () => {
    const query = "query Q { hello } subscription S { messageAdded { body } } mutation M { addMessage(input: {body: \"x\"}) { body } }";

    for (const [operationName, expected] of [
      ["S", "socket"],
      ["Q", "http"],
      ["M", "http"],
    ]) {
      const fetch = fakeFetch();
      const subscriptionClient = fakeSubscriptionClient();
      const transport = createAbsintheTransport({ url: URL, subscriptionClient, fetch });

      const result = transport.send({ query, operationName });
      if (isAsyncIterable(result)) await result[Symbol.asyncIterator]().next();
      else await result;

      const route = subscriptionClient.requests.length === 1 ? "socket" : fetch.mock.calls.length === 1 ? "http" : "none";
      expect([operationName, route]).toEqual([operationName, expected]);
      if (expected === "http") expect(JSON.parse(fetch.mock.calls[0][1].body).operationName).toBe(operationName);
      if (expected === "socket") expect(subscriptionClient.requests[0].operationName).toBe("S");
    }
  });

  it("shows a clear error for subscriptions without a socket", async () => {
    const transport = createAbsintheTransport({
      url: URL,
      subscriptionClient: createUnavailableSubscriptionClient("Subscriptions are not available"),
      fetch: fakeFetch(),
    });

    const iterator = transport.send({ query: "subscription { messageAdded { body } }" })[Symbol.asyncIterator]();
    const { value } = await iterator.next();
    expect(value.ok).toBe(false);
    expect(value.body).toEqual({ errors: [{ message: "Subscriptions are not available" }] });
    expect((await iterator.next()).done).toBe(true);
  });
});
