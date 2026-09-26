# Save and start 'shidashi' apps for AI agents

`save_launcher` saves how to start a 'shidashi' app, so that an AI agent
connected through the `MCP` proxy can list it and, after asking the
user, start it and open one of its modules in the browser. Nothing is
started automatically: the agent only launches a saved app when the user
picks it.

`run_launcher` starts a saved app. The `MCP` proxy calls it when the
agent launches an app; it can also be called from R.

## Usage

``` r
save_launcher(
  id,
  root_path,
  host = "127.0.0.1",
  port = NA,
  modules = NULL,
  description = "",
  prelaunch = NULL,
  copy_app = FALSE,
  ...
)

run_launcher(id, ...)
```

## Arguments

- id:

  a short name for the app, made of letters, digits, `"-"`, and `"_"`.
  The agent and the user refer to the app by this name.

- root_path:

  the app directory; it must contain `modules.yaml`

- host:

  the host to listen on

- port:

  the port to listen on; `NA` picks a free port at launch

- modules:

  the module identifiers the agent may open; default is the modules that
  have AI agents enabled (an `agents.yaml` file)

- description:

  a short description shown to the agent

- prelaunch:

  optional R code, as a character string, to run before the app starts

- copy_app:

  whether to start a copy of the app, kept in the cache folder, instead
  of the app directory itself

- ...:

  for `save_launcher`, named metadata about the app (character, numeric,
  or logical values), shown to the agent but not used to start the app;
  for `run_launcher`, extra arguments passed to
  [`render`](https://dipterix.org/shidashi/reference/render.md), which
  override the defaults (`launch_browser = FALSE`, `as_job = FALSE`)

## Value

`save_launcher` returns the saved launcher, invisibly. `run_launcher`
runs the app; see
[`render`](https://dipterix.org/shidashi/reference/render.md).

## Details

All launchers are kept in one file, `launchers.json`, in the 'shidashi'
cache folder (`tools::R_user_dir("shidashi", "cache")`). Saving again
with the same `id` replaces that launcher. Saving a launcher also
installs or updates the `MCP` proxy script.

With `copy_app = TRUE`, the app folder is copied to `saved_apps/<id>/`
in the cache folder (without `.git` and `node_modules`), and the
launcher starts the copy. The folder is cleared before each copy.
Without `copy_app`, a copy left from an earlier save of the same `id` is
removed.

## Examples

``` r

# This example saves into a temporary folder; by default launchers are
# saved in the user's cache folder
old_opt <- options(shidashi.cache_dir = tempfile())

root <- system.file("builtin-templates", "bslib-bare", package = "shidashi")
save_launcher(
  "demo-app", root,
  description = "Demo dashboard shipped with shidashi",
  lab = "example"
)

if (interactive()) {
  run_launcher("demo-app", launch_browser = TRUE)
}

options(old_opt)
```
