# Contributing

Thanks for helping with AbsintheGraphiQL. This file explains how to set up the
project, what to check before you open a pull request, and how to write commit
messages.

## Setup

The project uses [mise](https://mise.jdx.dev) to pin Erlang, Elixir and Node.js in
`mise.toml`. Do not use another version manager or a global install.

```sh
mise trust && mise install
mise exec -- mix deps.get
cd assets && mise exec -- npm ci && cd ..
```

Run the example app to try a change in a browser:

```sh
mise exec -- elixir examples/dev_server.exs
```

Then open <http://localhost:4401/graphiql>.

## Before you open a pull request

Run these checks. All of them must pass.

```sh
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix credo
mise exec -- mix test
mise exec -- mix assets.test
mise exec -- mix docs
```

- **Credo runs in strict mode with every [ExSlop](https://github.com/elixir-vibe/ex_slop)
  check** (`.credo.exs`). Fix a finding rather than disable it. If a check is wrong
  for one line, disable it for that line only and add a comment with the reason.
- **New logic needs tests.** Elixir code gets ExUnit tests in `test/`. JavaScript in
  `assets/src/` gets vitest tests in `assets/test/`.
- **If you change `assets/`**, run `mise exec -- mix assets.build` and commit the
  rebuilt `priv/static/` in the same pull request. Hex users get the built files and
  never run Node.js.
- **Do not load anything from a CDN.** Every script, web worker, stylesheet and font
  must be part of the bundle and served by the plug. The IDE must work with the
  internet blocked. Do not add a `<script src>`, a remote `@font-face` or a remote
  `import()`.
- **Pin npm dependencies to exact versions** in `assets/package.json`, and commit
  `assets/package-lock.json`.
- **Update `CHANGELOG.md`** under an `## Unreleased` heading for changes that users
  can see.
- **Check UI changes** in the example app in light and dark theme, and add a
  screenshot to the pull request.

## Commit messages

This project uses [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
Every commit on `main` follows this format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

The scope, body and footer are optional.

### Types

| Type | Use it for |
|---|---|
| `feat` | A new feature or option that users can see |
| `fix` | A bug fix |
| `docs` | Documentation only: README, guides, module docs, examples |
| `test` | Tests only |
| `refactor` | A code change that does not change behavior |
| `perf` | A change that makes something faster or smaller |
| `build` | The esbuild bundle, npm or Hex dependencies, package metadata |
| `ci` | CI configuration |
| `style` | Formatting only |
| `chore` | Other maintenance, for example tool versions or releases |
| `revert` | Reverts an earlier commit |

### Scopes

Use a scope when the change is in one area:

| Scope | Area |
|---|---|
| `plug` | `AbsintheGraphiQL.Plug` and the other code in `lib/` |
| `assets` | The frontend in `assets/` and the built files in `priv/static/` |
| `socket` | The Absinthe channel client in `assets/src/absinthe_socket.js` |
| `examples` | `examples/` |
| `deps` | Dependency updates |
| `hex` | Hex package metadata |
| `release` | Release commits |

### Subject and body

- Write the subject in the imperative mood, in lower case, with no period at the end:
  `fix(socket): resubscribe after the channel rejoins`.
- Keep the subject line to 72 characters or fewer.
- Use the body to explain why the change is necessary, not what each line does.
- Refer to issues in the footer, for example `Closes #12`.

### Breaking changes

Mark a breaking change with `!` after the type or scope, and explain it in a
`BREAKING CHANGE:` footer:

```
feat(plug)!: rename :default_url to :endpoint

BREAKING CHANGE: the :default_url option is now :endpoint. Rename it in your router.
```

Before 1.0.0, a breaking change increments the minor version (0.1.x to 0.2.0).

## Pull requests

- Keep one topic per pull request.
- Rebase on `main` before you ask for a review. History on `main` is linear: no merge
  commits and no squash merges, so every commit must pass the checks on its own and
  have a Conventional Commits message.
- Describe what changed and how you tested it.

## Releases

Maintainers make releases:

1. Set the new version in `mix.exs` and move the `## Unreleased` entries in
   `CHANGELOG.md` under the new version.
2. Commit with `chore(release): vX.Y.Z`.
3. Tag the commit with `git tag -a vX.Y.Z -m vX.Y.Z` and push the branch and the tag.
4. Run `mise exec -- mix hex.publish`.

## License

By contributing, you agree that your contributions are licensed under the MIT
license in `LICENSE`.
