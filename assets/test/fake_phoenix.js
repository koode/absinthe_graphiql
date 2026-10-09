// A fake Phoenix Socket and Channel with the API absinthe_socket.js uses.
// Replies are delivered by the test with push.reply(status, response).

export class FakePush {
  constructor(event, payload) {
    this.event = event;
    this.payload = payload;
    this.hooks = [];
  }

  receive(status, callback) {
    this.hooks.push({ status, callback });
    return this;
  }

  reply(status, response) {
    for (const hook of this.hooks) if (hook.status === status) hook.callback(response);
  }
}

export class FakeChannel {
  constructor(topic, params) {
    this.topic = topic;
    this.params = params;
    this.pushes = [];
    this.errorCallbacks = [];
    this.closeCallbacks = [];
    this.joinPush = null;
  }

  join() {
    if (this.joinPush) throw new Error("joined twice");
    this.joinPush = new FakePush("phx_join", this.params);
    return this.joinPush;
  }

  push(event, payload) {
    const push = new FakePush(event, payload);
    this.pushes.push(push);
    return push;
  }

  onError(callback) {
    this.errorCallbacks.push(callback);
  }

  onClose(callback) {
    this.closeCallbacks.push(callback);
  }

  // Test helpers
  error(reason) {
    for (const callback of this.errorCallbacks) callback(reason);
  }

  pushesOf(event) {
    return this.pushes.filter((push) => push.event === event);
  }
}

export class FakeSocket {
  constructor() {
    this.channels = [];
    this.messageCallbacks = [];
    this.errorCallbacks = [];
    this.connectCount = 0;
  }

  connect() {
    this.connectCount++;
  }

  channel(topic, params) {
    const channel = new FakeChannel(topic, params);
    this.channels.push(channel);
    return channel;
  }

  onMessage(callback) {
    this.messageCallbacks.push(callback);
  }

  onError(callback) {
    this.errorCallbacks.push(callback);
  }

  // Test helpers
  deliver(message) {
    for (const callback of this.messageCallbacks) callback(message);
  }

  error(reason) {
    for (const callback of this.errorCallbacks) callback(reason);
    for (const channel of this.channels) channel.error(reason);
  }
}
