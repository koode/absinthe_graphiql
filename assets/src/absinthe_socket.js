// A small client for Absinthe's Phoenix channel protocol
// (absinthe_phoenix, Absinthe.Phoenix.Channel):
//
//   1. Join the topic "__absinthe__:control".
//   2. Push "doc" with %{"query" => ..., "variables" => ...}.
//      - A subscription replies ok with %{subscriptionId: topic}.
//      - A query or mutation replies ok with the result (%{data: ...}).
//      - A document with errors replies error with %{errors: [...]}.
//      - Bad variables reply error with %{error: "..."}.
//   3. The server sends each subscription event as a "subscription:data"
//      message on the topic <subscriptionId>, with the payload
//      %{result: ..., subscriptionId: ...}. The message does not belong to
//      the control channel, so it is read with socket.onMessage.
//   4. Push "unsubscribe" with %{subscriptionId: ...} to stop.
//
// The client exposes `iterate(request)`, the SubscriptionClient contract of
// @graphiql/toolkit's createTransport: it returns an async iterator of
// execution results, and calling `.return()` on it stops the subscription.
//
// Reconnects: Phoenix rejoins the channel after the socket reconnects, but
// the server forgets the subscriptions of the old channel process. When the
// channel is joined again, the client sends the "doc" of every active
// subscription again. Events published while the socket was down are lost.

import { Kind, parse, print, separateOperations } from "graphql";

export const CONTROL_TOPIC = "__absinthe__:control";

/**
 * Reduce a document to the selected operation and the fragments it uses.
 *
 * Absinthe.Phoenix.Channel does not read `operationName`, so a document with
 * several operations would be rejected. Returns the query unchanged when it
 * has a single operation or cannot be parsed (the server reports the error).
 */
export function selectOperation(query, operationName) {
  let document;
  try {
    document = parse(query);
  } catch {
    return query;
  }
  const operations = document.definitions.filter((d) => d.kind === Kind.OPERATION_DEFINITION);
  if (operations.length <= 1 || !operationName) return query;
  const separated = separateOperations(document)[operationName];
  return separated ? print(separated) : query;
}

function errorResult(message) {
  return { errors: [{ message }] };
}

function errorReply(reply) {
  if (reply && Array.isArray(reply.errors)) return { errors: reply.errors };
  if (reply && typeof reply.error === "string") return errorResult(reply.error);
  if (reply && typeof reply.reason === "string") return errorResult(reply.reason);
  return errorResult(`The server rejected the operation: ${JSON.stringify(reply)}`);
}

/**
 * Create a client on top of a Phoenix Socket instance.
 *
 * @param {object} options
 * @param {import("phoenix").Socket} options.socket - an unconnected or connected Phoenix Socket
 * @param {string} [options.url] - shown in connection error messages
 */
export function createAbsintheSocketClient({ socket, url = "the socket" }) {
  let channel = null;
  let joined = false;
  let everJoined = false;
  let nextId = 1;
  const active = new Map(); // local id -> operation
  const byServerId = new Map(); // subscriptionId -> operation

  function ensureChannel() {
    if (channel) return;
    socket.onMessage(onSocketMessage);
    socket.onError(onSocketError);
    socket.connect();
    channel = socket.channel(CONTROL_TOPIC, {});
    channel.onError(() => markDisconnected());
    channel.onClose(() => markDisconnected());
    channel
      .join()
      .receive("ok", () => {
        joined = true;
        everJoined = true;
        for (const op of active.values()) sendDoc(op);
      })
      .receive("error", (reply) => {
        failPending(`Could not join ${CONTROL_TOPIC}: ${errorReply(reply).errors[0].message}`);
      })
      .receive("timeout", () => {
        failPending(`Timed out joining ${CONTROL_TOPIC} on ${url}`);
      });
  }

  function markDisconnected() {
    joined = false;
    // The server dropped the subscriptions of this channel process.
    for (const op of active.values()) op.subscriptionId = null;
    byServerId.clear();
  }

  function onSocketError() {
    markDisconnected();
    // Before the first join there is nothing to resume; report the failure
    // instead of leaving the result pane waiting while Phoenix retries.
    if (!everJoined) failPending(`Could not connect to ${url}`);
  }

  function onSocketMessage(message) {
    if (!message || message.event !== "subscription:data") return;
    const payload = message.payload || {};
    const op = byServerId.get(payload.subscriptionId ?? message.topic);
    if (op) op.emit(payload.result);
  }

  function failPending(message) {
    for (const op of [...active.values()]) {
      op.emit(errorResult(message));
      op.finish();
    }
  }

  function sendDoc(op) {
    const generation = ++op.generation;
    channel
      .push("doc", { query: op.query, variables: op.variables })
      .receive("ok", (reply) => {
        if (generation !== op.generation) return;
        if (reply && typeof reply.subscriptionId === "string") {
          if (op.done) {
            channel.push("unsubscribe", { subscriptionId: reply.subscriptionId });
            return;
          }
          op.subscriptionId = reply.subscriptionId;
          byServerId.set(reply.subscriptionId, op);
        } else {
          // A query or mutation sent over the socket: one result, then done.
          op.emit(reply);
          op.finish();
        }
      })
      .receive("error", (reply) => {
        if (generation !== op.generation) return;
        op.emit(errorReply(reply));
        op.finish();
      })
      .receive("timeout", () => {
        if (generation !== op.generation || op.done) return;
        // A lost connection causes the timeout too; the rejoin resends.
        if (!joined) return;
        op.emit(errorResult(`Timed out waiting for the server to accept the subscription`));
        op.finish();
      });
  }

  function iterate(request) {
    const queue = [];
    const waiters = [];
    const op = {
      id: nextId++,
      query: selectOperation(request.query, request.operationName),
      variables: request.variables || {},
      subscriptionId: null,
      generation: 0,
      done: false,
      emit(value) {
        if (op.done) return;
        const waiter = waiters.shift();
        if (waiter) waiter.resolve({ done: false, value });
        else queue.push(value);
      },
      finish() {
        if (op.done) return;
        op.done = true;
        active.delete(op.id);
        if (op.subscriptionId) byServerId.delete(op.subscriptionId);
        // Results already queued are still delivered; pending waiters end.
        for (const waiter of waiters.splice(0)) waiter.resolve({ done: true, value: undefined });
      },
    };

    active.set(op.id, op);
    ensureChannel();
    if (joined) sendDoc(op);

    return {
      next() {
        if (queue.length > 0) return Promise.resolve({ done: false, value: queue.shift() });
        if (op.done) return Promise.resolve({ done: true, value: undefined });
        return new Promise((resolve) => waiters.push({ resolve }));
      },
      return() {
        const subscriptionId = op.subscriptionId;
        const wasDone = op.done;
        queue.length = 0;
        op.finish();
        if (!wasDone && subscriptionId && joined) {
          channel.push("unsubscribe", { subscriptionId });
        }
        return Promise.resolve({ done: true, value: undefined });
      },
      [Symbol.asyncIterator]() {
        return this;
      },
    };
  }

  return {
    iterate,
    /** Number of operations that have not finished. For tests and debugging. */
    get activeCount() {
      return active.size;
    },
  };
}

/**
 * A SubscriptionClient for pages without a socket: every subscription
 * returns one error result that explains how to enable subscriptions.
 */
export function createUnavailableSubscriptionClient(message) {
  return {
    iterate() {
      let sent = false;
      return {
        next() {
          if (sent) return Promise.resolve({ done: true, value: undefined });
          sent = true;
          return Promise.resolve({ done: false, value: errorResult(message) });
        },
        return() {
          sent = true;
          return Promise.resolve({ done: true, value: undefined });
        },
        [Symbol.asyncIterator]() {
          return this;
        },
      };
    },
  };
}
