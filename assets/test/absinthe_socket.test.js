import { describe, expect, it } from "vitest";

import {
  CONTROL_TOPIC,
  createAbsintheSocketClient,
  createUnavailableSubscriptionClient,
  selectOperation,
} from "../src/absinthe_socket.js";
import { FakeSocket } from "./fake_phoenix.js";

const SUBSCRIPTION = "subscription { messageAdded { body } }";
const SUB_ID = "__absinthe__:doc:-576460752303423216:6D23";

// Same shape as Absinthe.Phoenix.Endpoint.publish_subscription/4 and the
// Elixir test in test/absinthe_graphiql/subscription_test.exs.
function dataMessage(subscriptionId, body) {
  return {
    topic: subscriptionId,
    event: "subscription:data",
    payload: { subscriptionId, result: { data: { messageAdded: { body } } } },
    ref: null,
  };
}

function setup() {
  const socket = new FakeSocket();
  const client = createAbsintheSocketClient({ socket, url: "ws://localhost/socket" });
  return { socket, client };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("createAbsintheSocketClient", () => {
  it("connects lazily and joins the control topic once", () => {
    const { socket, client } = setup();
    expect(socket.connectCount).toBe(0);

    client.iterate({ query: SUBSCRIPTION });
    client.iterate({ query: SUBSCRIPTION });

    expect(socket.connectCount).toBe(1);
    expect(socket.channels).toHaveLength(1);
    expect(socket.channels[0].topic).toBe(CONTROL_TOPIC);
    expect(socket.channels[0].topic).toBe("__absinthe__:control");
  });

  it("sends the doc after the join succeeds", () => {
    const { socket, client } = setup();
    client.iterate({ query: SUBSCRIPTION, variables: { id: 1 } });
    const channel = socket.channels[0];

    expect(channel.pushesOf("doc")).toHaveLength(0);
    channel.joinPush.reply("ok", {});

    const [doc] = channel.pushesOf("doc");
    expect(doc.payload).toEqual({ query: SUBSCRIPTION, variables: { id: 1 } });
  });

  it("sends the doc right away when already joined, with {} for missing variables", () => {
    const { socket, client } = setup();
    client.iterate({ query: SUBSCRIPTION });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});

    client.iterate({ query: "subscription Other { messageAdded { body } }" });
    expect(channel.pushesOf("doc")).toHaveLength(2);
    expect(channel.pushesOf("doc")[1].payload.variables).toEqual({});
  });

  it("yields subscription:data results for its subscriptionId only", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});
    channel.pushesOf("doc")[0].reply("ok", { subscriptionId: SUB_ID });

    socket.deliver(dataMessage("__absinthe__:doc:other", "not mine"));
    socket.deliver({ topic: SUB_ID, event: "phx_reply", payload: {} });
    socket.deliver(dataMessage(SUB_ID, "first"));
    socket.deliver(dataMessage(SUB_ID, "second"));

    expect(await iterator.next()).toEqual({ done: false, value: { data: { messageAdded: { body: "first" } } } });
    expect(await iterator.next()).toEqual({ done: false, value: { data: { messageAdded: { body: "second" } } } });

    const pending = iterator.next();
    socket.deliver(dataMessage(SUB_ID, "third"));
    expect(await pending).toEqual({ done: false, value: { data: { messageAdded: { body: "third" } } } });
  });

  it("unsubscribes when the iterator is returned", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});
    channel.pushesOf("doc")[0].reply("ok", { subscriptionId: SUB_ID });

    const pending = iterator.next();
    expect(await iterator.return()).toEqual({ done: true, value: undefined });
    expect(await pending).toEqual({ done: true, value: undefined });

    const [unsubscribe] = channel.pushesOf("unsubscribe");
    expect(unsubscribe.payload).toEqual({ subscriptionId: SUB_ID });

    socket.deliver(dataMessage(SUB_ID, "late"));
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
    expect(client.activeCount).toBe(0);
  });

  it("unsubscribes when stopped before the server accepted the doc", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});

    await iterator.return();
    expect(channel.pushesOf("unsubscribe")).toHaveLength(0);

    channel.pushesOf("doc")[0].reply("ok", { subscriptionId: SUB_ID });
    expect(channel.pushesOf("unsubscribe").map((p) => p.payload)).toEqual([{ subscriptionId: SUB_ID }]);
  });

  it("shows validation errors from the doc reply", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: "subscription { nope }" });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});

    const errors = [{ message: 'Cannot query field "nope" on type "RootSubscriptionType".', locations: [{ line: 1, column: 16 }] }];
    channel.pushesOf("doc")[0].reply("error", { errors });

    expect(await iterator.next()).toEqual({ done: false, value: { errors } });
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
  });

  it("turns an {error: string} reply into a GraphQL error", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});
    channel.pushesOf("doc")[0].reply("error", { error: "Could not parse variables as map" });

    expect(await iterator.next()).toEqual({
      done: false,
      value: { errors: [{ message: "Could not parse variables as map" }] },
    });
  });

  it("returns a query result sent over the socket and finishes", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: "{ hello }" });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});
    channel.pushesOf("doc")[0].reply("ok", { data: { hello: "Hello, world!" } });

    expect(await iterator.next()).toEqual({ done: false, value: { data: { hello: "Hello, world!" } } });
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
  });

  it("reports a join error", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    socket.channels[0].joinPush.reply("error", { reason: "unauthorized" });

    expect(await iterator.next()).toEqual({
      done: false,
      value: { errors: [{ message: "Could not join __absinthe__:control: unauthorized" }] },
    });
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
  });

  it("reports a join timeout", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    socket.channels[0].joinPush.reply("timeout");

    const { value } = await iterator.next();
    expect(value.errors[0].message).toMatch(/Timed out joining __absinthe__:control/);
  });

  it("reports a socket that cannot connect", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    socket.error(new Error("connection refused"));

    expect(await iterator.next()).toEqual({
      done: false,
      value: { errors: [{ message: "Could not connect to ws://localhost/socket" }] },
    });
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
  });

  it("resubscribes after the socket reconnects", async () => {
    const { socket, client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION, variables: { a: 1 } });
    const channel = socket.channels[0];
    channel.joinPush.reply("ok", {});
    channel.pushesOf("doc")[0].reply("ok", { subscriptionId: SUB_ID });

    // Connection lost: the subscription stays active, nothing is reported.
    socket.error(new Error("connection lost"));
    socket.deliver(dataMessage(SUB_ID, "stale"));

    // Phoenix rejoins the channel; the same join push replies ok again.
    channel.joinPush.reply("ok", {});
    const docs = channel.pushesOf("doc");
    expect(docs).toHaveLength(2);
    expect(docs[1].payload).toEqual({ query: SUBSCRIPTION, variables: { a: 1 } });

    const NEW_ID = "__absinthe__:doc:-576460752303423000:AAAA";
    docs[1].reply("ok", { subscriptionId: NEW_ID });
    // A late reply to the first doc must not be used.
    docs[0].reply("error", { errors: [{ message: "stale" }] });
    socket.deliver(dataMessage(NEW_ID, "after reconnect"));

    expect(await iterator.next()).toEqual({
      done: false,
      value: { data: { messageAdded: { body: "after reconnect" } } },
    });

    await iterator.return();
    expect(channel.pushesOf("unsubscribe").map((p) => p.payload)).toEqual([{ subscriptionId: NEW_ID }]);
  });

  it("sends only the selected operation of a multi-operation document", () => {
    const { socket, client } = setup();
    const query = `
      query Q { hello }
      subscription S { messageAdded { ...M } }
      fragment M on Message { body }
      fragment Unused on Message { id }
    `;
    client.iterate({ query, operationName: "S" });
    socket.channels[0].joinPush.reply("ok", {});

    const sent = socket.channels[0].pushesOf("doc")[0].payload.query;
    expect(sent).toContain("subscription S");
    expect(sent).toContain("fragment M on Message");
    expect(sent).not.toContain("query Q");
    expect(sent).not.toContain("Unused");
  });

  it("can be stopped before the channel is joined", async () => {
    const { client } = setup();
    const iterator = client.iterate({ query: SUBSCRIPTION });
    await flush();
    await iterator.return();
    expect(client.activeCount).toBe(0);
  });
});

describe("selectOperation", () => {
  it("keeps single-operation documents as they are", () => {
    expect(selectOperation(SUBSCRIPTION, "Anything")).toBe(SUBSCRIPTION);
    expect(selectOperation(SUBSCRIPTION)).toBe(SUBSCRIPTION);
  });

  it("keeps documents that do not parse, so the server reports the error", () => {
    expect(selectOperation("subscription {", "S")).toBe("subscription {");
  });

  it("keeps the document when the operation name is unknown", () => {
    const query = "query A { hello } query B { hello }";
    expect(selectOperation(query, "C")).toBe(query);
  });
});

describe("createUnavailableSubscriptionClient", () => {
  it("yields one error result, then finishes", async () => {
    const iterator = createUnavailableSubscriptionClient("No socket").iterate({ query: SUBSCRIPTION });
    expect(await iterator.next()).toEqual({ done: false, value: { errors: [{ message: "No socket" }] } });
    expect(await iterator.next()).toEqual({ done: true, value: undefined });
  });
});
