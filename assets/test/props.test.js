import { describe, expect, it } from "vitest";

import { graphiqlProps } from "../src/props.js";

const available = {
  query_builder: { title: "Query Builder" },
  doc_explorer: { title: "Documentation Explorer" },
  history: { title: "History" },
  collections: { title: "Collections" },
};

function config(overrides = {}) {
  return {
    theme: "system",
    queryBuilder: true,
    history: true,
    collections: true,
    shouldPersistHeaders: false,
    defaultQuery: null,
    defaultVariables: null,
    defaultHeaders: null,
    defaultTabs: null,
    visiblePlugin: null,
    ...overrides,
  };
}

describe("graphiqlProps", () => {
  it("has the defaults", () => {
    const props = graphiqlProps(config(), available);

    expect(props.plugins).toEqual([available.history, available.query_builder, available.collections]);
    expect(props.shouldPersistHeaders).toBe(false);
    expect(props.isHeadersEditorEnabled).toBe(true);
    expect(props).not.toHaveProperty("forcedTheme");
    expect(props).not.toHaveProperty("visiblePlugin");
    expect(props).not.toHaveProperty("defaultTabs");
    expect(props).not.toHaveProperty("defaultQuery");
  });

  it("leaves out disabled plugins", () => {
    const props = graphiqlProps(config({ history: false, collections: false }), available);
    expect(props.plugins).toEqual([available.query_builder]);
  });

  it("forces a light or dark theme", () => {
    expect(graphiqlProps(config({ theme: "dark" }), available).forcedTheme).toBe("dark");
    expect(graphiqlProps(config({ theme: "light" }), available).forcedTheme).toBe("light");
  });

  it.each(["query_builder", "doc_explorer", "history", "collections"])("passes the %s plugin object as visiblePlugin", (name) => {
    const props = graphiqlProps(config({ visiblePlugin: name }), available);
    expect(props.visiblePlugin).toBe(available[name]);
  });

  it("ignores a visible plugin that is disabled or unknown", () => {
    expect(graphiqlProps(config({ visiblePlugin: "history", history: false }), available)).not.toHaveProperty("visiblePlugin");
    expect(graphiqlProps(config({ visiblePlugin: "nope" }), available)).not.toHaveProperty("visiblePlugin");
  });

  it("builds one tab from the single-tab options", () => {
    const props = graphiqlProps(config({ defaultQuery: "{ a }", defaultVariables: '{"x": 1}', defaultHeaders: '{"h": "v"}' }), available);

    expect(props.defaultQuery).toBe("{ a }");
    expect(props.defaultHeaders).toBe('{"h": "v"}');
    expect(props.defaultTabs).toEqual([{ query: "{ a }", variables: '{"x": 1}', headers: '{"h": "v"}' }]);
  });

  it("builds a tab when only headers are set", () => {
    const props = graphiqlProps(config({ defaultHeaders: '{"h": "v"}' }), available);
    expect(props.defaultTabs).toEqual([{ query: undefined, variables: undefined, headers: '{"h": "v"}' }]);
  });

  it("passes defaultTabs, with the default headers for tabs without headers", () => {
    const props = graphiqlProps(
      config({
        defaultHeaders: '{"h": "default"}',
        defaultTabs: [
          { query: "{ a }", variables: '{"x": 1}', headers: null },
          { query: "{ b }", variables: null, headers: '{"h": "own"}' },
          { query: null, variables: null, headers: null },
        ],
      }),
      available,
    );

    expect(props.defaultTabs).toEqual([
      { query: "{ a }", variables: '{"x": 1}', headers: '{"h": "default"}' },
      { query: "{ b }", variables: undefined, headers: '{"h": "own"}' },
      { query: undefined, variables: undefined, headers: '{"h": "default"}' },
    ]);
    expect(props.defaultHeaders).toBe('{"h": "default"}');
  });

  it("passes defaultTabs without default headers", () => {
    const props = graphiqlProps(config({ defaultTabs: [{ query: "{ a }", variables: null, headers: null }] }), available);
    expect(props.defaultTabs).toEqual([{ query: "{ a }", variables: undefined, headers: undefined }]);
  });
});
