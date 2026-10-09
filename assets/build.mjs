// Builds the GraphiQL page into ../priv/static:
//
//   app-<hash>.js            ES module entry, plus code-split chunks
//   app-<hash>.css           GraphiQL + Monaco styles
//   font-<sha>-<hash>.woff2  fonts, moved out of GraphiQL's CSS data: URLs
//   editor.worker-<hash>.js  Monaco web workers (classic scripts)
//   json.worker-<hash>.js
//   graphql.worker-<hash>.js
//   favicon-<hash>.svg       page icon
//   manifest.json            entry names and the full file list, read by
//                            AbsintheGraphiQL.Assets at compile time
//   THIRD_PARTY_LICENSES.txt license of every bundled package and font
//
// Run with `mix assets.build` from the repository root, or `npm run build`
// from this directory.

import * as esbuild from "esbuild";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const assetsDir = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(assetsDir, "../priv/static");
const fontTmpDir = join(assetsDir, ".build/fonts");

rmSync(outDir, { recursive: true, force: true });
rmSync(fontTmpDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
mkdirSync(fontTmpDir, { recursive: true });

// graphiql/style.css is GraphiQL's complete stylesheet: Monaco's CSS, the
// Roboto, Fira Code and codicon fonts (as base64 data: URLs) and the GraphiQL
// and plugin styles. Use it as the only CSS source:
//
// - Monaco's own `import "./x.css"` statements are replaced with nothing,
//   so its CSS is not bundled twice.
// - Each data: font is written to a file, so the browser only downloads the
//   unicode-range subsets it needs and the CSP needs no `font-src data:`.
const fontFormats = { woff2: "woff2", woff: "woff", ttf: "ttf", otf: "otf" };

const cssPlugin = {
  name: "graphiql-css",
  setup(build) {
    build.onResolve({ filter: /\.css$/ }, (args) => {
      if (/[\\/]node_modules[\\/]monaco-editor[\\/]/.test(args.importer)) {
        return { path: args.path, namespace: "monaco-css-stub" };
      }
      return undefined;
    });
    build.onLoad({ filter: /.*/, namespace: "monaco-css-stub" }, () => ({ contents: "", loader: "css" }));

    build.onLoad({ filter: /[\\/]graphiql[\\/]dist[\\/]style\.css$/ }, (args) => {
      const source = readFileSync(args.path, "utf8");
      let count = 0;
      const contents = source.replace(
        /url\((["']?)data:font\/(woff2|woff|ttf|otf);base64,([A-Za-z0-9+/=]+)\1\)/g,
        (_match, _quote, type, base64) => {
          const bytes = Buffer.from(base64, "base64");
          const sha = createHash("sha256").update(bytes).digest("hex").slice(0, 12);
          const file = join(fontTmpDir, `font-${sha}.${fontFormats[type]}`);
          writeFileSync(file, bytes);
          count++;
          return `url("${file}")`;
        },
      );
      if (count === 0) throw new Error("No inline fonts found in graphiql/dist/style.css; check the build");
      return { contents, loader: "css", resolveDir: dirname(args.path) };
    });
  },
};

const shared = {
  bundle: true,
  minify: true,
  platform: "browser",
  // Licenses are collected into THIRD_PARTY_LICENSES.txt instead.
  legalComments: "none",
  define: { "process.env.NODE_ENV": '"production"' },
  metafile: true,
  logLevel: "warning",
  outdir: outDir,
  entryNames: "[name]-[hash]",
  chunkNames: "[name]-[hash]",
  assetNames: "[name]-[hash]",
};

const app = await esbuild.build({
  ...shared,
  entryPoints: { app: join(assetsDir, "src/app.jsx") },
  format: "esm",
  splitting: true,
  target: ["es2022"],
  jsx: "automatic",
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".otf": "file" },
  plugins: [cssPlugin],
});

// Workers are classic scripts so `new Worker(url)` works in every browser.
const workers = await esbuild.build({
  ...shared,
  entryPoints: {
    "editor.worker": join(assetsDir, "src/workers/editor.worker.js"),
    "json.worker": join(assetsDir, "src/workers/json.worker.js"),
    "graphql.worker": join(assetsDir, "src/workers/graphql.worker.js"),
  },
  format: "iife",
  target: ["es2022"],
});

if (process.env.METAFILE) {
  writeFileSync(process.env.METAFILE, JSON.stringify({ app: app.metafile, workers: workers.metafile }));
}

// The page icon, so browsers do not request /favicon.ico from the host app.
const faviconSource = readFileSync(join(assetsDir, "src/favicon.svg"));
const favicon = `favicon-${createHash("sha256").update(faviconSource).digest("hex").slice(0, 8).toUpperCase()}.svg`;
writeFileSync(join(outDir, favicon), faviconSource);

// ---------------------------------------------------------------- manifest

const outputs = { ...app.metafile.outputs, ...workers.metafile.outputs };
const files = Object.keys(outputs)
  .map((path) => relative(outDir, resolve(process.cwd(), path)))
  .concat([favicon])
  .sort();

for (const file of files) {
  if (file.includes("/") || file.includes("\\")) throw new Error(`Unexpected nested output: ${file}`);
}

function entryOutput(metafile, entry, ext = ".js") {
  const match = Object.entries(metafile.outputs).find(
    ([path, meta]) => meta.entryPoint && meta.entryPoint.endsWith(entry) && path.endsWith(ext),
  );
  if (!match) throw new Error(`No output for ${entry}`);
  return basename(match[0]);
}

const appJs = entryOutput(app.metafile, "src/app.jsx");
const appCss = basename(app.metafile.outputs[join(relative(process.cwd(), outDir), appJs)].cssBundle);

const manifest = {
  "app.js": appJs,
  "app.css": appCss,
  "editor.worker.js": entryOutput(workers.metafile, "src/workers/editor.worker.js"),
  "json.worker.js": entryOutput(workers.metafile, "src/workers/json.worker.js"),
  "graphql.worker.js": entryOutput(workers.metafile, "src/workers/graphql.worker.js"),
  "favicon.svg": favicon,
  files,
};

writeFileSync(join(outDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);

// ---------------------------------------------------------------- licenses

const packageRoots = new Set();
for (const metafile of [app.metafile, workers.metafile]) {
  for (const input of Object.keys(metafile.inputs)) {
    const parts = input.split(/[\\/]/);
    const idx = parts.lastIndexOf("node_modules");
    if (idx === -1) continue;
    const nameParts = parts[idx + 1].startsWith("@") ? parts.slice(idx + 1, idx + 3) : [parts[idx + 1]];
    packageRoots.add(resolve(process.cwd(), ...parts.slice(0, idx + 1), ...nameParts));
  }
}

function licenseText(root, pkg) {
  const names = readdirSync(root);
  const file = names.find((name) => /^(licen[cs]e|copying)(\.(md|txt))?$/i.test(name));
  const notices = names.find((name) => /^thirdpartynotices(\.txt)?$/i.test(name));
  const parts = [];
  if (file) parts.push(readFileSync(join(root, file), "utf8").trim());
  else {
    if (!pkg.license) throw new Error(`No LICENSE file and no license field in ${root}`);
    parts.push(`This package does not ship a LICENSE file. Its package.json declares the license as "${pkg.license}".`);
  }
  if (notices) parts.push(`${notices}:\n\n${readFileSync(join(root, notices), "utf8").trim()}`);
  return parts.join("\n\n");
}

const sections = [...packageRoots]
  .map((root) => {
    const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
    return { name: `${pkg.name}@${pkg.version}`, license: pkg.license, text: licenseText(root, pkg) };
  })
  .sort((a, b) => a.name.localeCompare(b.name));

const fontNote =
  "Fonts embedded in graphiql/dist/style.css and written to the font-*.woff,\n" +
  "font-*.woff2 and font-*.ttf files.";

const fonts = [
  { name: "Roboto (font)", license: "OFL-1.1", file: "Roboto-OFL-1.1.txt" },
  { name: "Fira Code (font)", license: "OFL-1.1", file: "FiraCode-OFL-1.1.txt" },
  { name: "codicon (font, from @vscode/codicons via monaco-editor)", license: "CC-BY-4.0", file: "Codicons-CC-BY-4.0.txt" },
].map((font) => ({
  ...font,
  text: `${fontNote}\n\n${readFileSync(join(assetsDir, "licenses", font.file), "utf8").trim()}`,
}));

const all = [...sections, ...fonts];

const header = [
  "Third-party software bundled in priv/static",
  "",
  "The files in priv/static are built from assets/src and the npm packages and",
  "fonts listed below. Each license text follows.",
  "",
  ...all.map((s) => `- ${s.name} (${s.license})`),
].join("\n");

const body = all
  .map((s) => ["=".repeat(78), s.name, "=".repeat(78), "", s.text].join("\n"))
  .join("\n\n");

writeFileSync(join(outDir, "THIRD_PARTY_LICENSES.txt"), `${header}\n\n${body}\n`);
rmSync(join(assetsDir, ".build"), { recursive: true, force: true });

// ---------------------------------------------------------------- report

const sizes = files.map((file) => [file, readFileSync(join(outDir, file)).length]);
const total = sizes.reduce((sum, [, size]) => sum + size, 0);
const kb = (n) => `${(n / 1024).toFixed(1)} KiB`;
for (const key of ["app.js", "app.css", "editor.worker.js", "json.worker.js", "graphql.worker.js"]) {
  const size = sizes.find(([file]) => file === manifest[key])[1];
  console.log(`${key.padEnd(18)} ${manifest[key].padEnd(40)} ${kb(size)}`);
}
console.log(`${files.length} files, ${kb(total)} total, ${sections.length} packages + ${fonts.length} fonts licensed`);
