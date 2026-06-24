# Shiny session registration and cross-tab synchronization

Shiny session registration and cross-tab synchronization

## Usage

``` r
register_session(session)

unregister_session(session)

enable_input_broadcast(
  session = shiny::getDefaultReactiveDomain(),
  once = FALSE
)

disable_input_broadcast(session = shiny::getDefaultReactiveDomain())

enable_input_sync(session = shiny::getDefaultReactiveDomain(), once = FALSE)

disable_input_sync(session = shiny::getDefaultReactiveDomain())

get_handler(name, session = shiny::getDefaultReactiveDomain())

set_handler(name, handler, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- session:

  A Shiny session object or session proxy (created by
  [`moduleServer`](https://rdrr.io/pkg/shiny/man/moduleServer.html)).
  Most functions in this family default to
  [`shiny::getDefaultReactiveDomain()`](https://rdrr.io/pkg/shiny/man/domains.html)
  so callers inside module server functions do not need to pass it
  explicitly. `register_session` and `unregister_session` require an
  explicit value.

- once:

  Logical; if `TRUE`, resume the suspended observer for a single run via
  `$run()` instead of permanently re-activating it with `$resume()`.
  Useful for one-shot snapshots without installing a persistent
  observer.

- name:

  A single character string identifying a named slot in the session's
  handler list (used by `get_handler` and `set_handler`). Three names
  are reserved for internal use and will trigger an error if passed to
  `set_handler`: `"event_handler"`, `"broadcast_handler"`, and
  `"input_sync_handler"`.

- handler:

  A Shiny Observer object created by
  [`shiny::observe()`](https://rdrr.io/pkg/shiny/man/observe.html), or
  `NULL` to clear the named slot (used by `set_handler`). Passing any
  other object type raises an error.

## Value

`register_session` returns the session token (`session$token`)
invisibly; it is idempotent and safe to call multiple times for the same
session.

`unregister_session` returns `NULL` invisibly; it is idempotent.

`enable_input_broadcast`, `disable_input_broadcast`,
`enable_input_sync`, and `disable_input_sync` all return invisibly. They
are silent no-ops when the session is already closed.

`get_handler` returns the named `Observer` object stored under `name`,
or `NULL` if the slot is empty or the session is closed.

`set_handler` returns `TRUE` invisibly when it successfully installs the
handler, or `FALSE` invisibly when the session is already closed.

## Details

### Session registration

**`register_session()`** — Call once at the top of every Shiny module
server function. It is idempotent: calling it a second time on the same
session safely refreshes the session object and URL in the registry
entry without re-creating observers.

Internally it creates an entry in the application-global session
registry (initialized by
[`init_app`](https://dipterix.org/shidashi/reference/init_app.md)),
resolves a `shared_id` token shared across browser tabs from the
`?shared_id=...` URL query string (or generates a random 26-character
string when absent), sets up the per-session reactive event bus, and —
for named module sessions — sends a `shidashi.register_module_token`
custom message to bind the module namespace to its session token on the
JavaScript side.

**`unregister_session()`** — Removes the session entry from the registry
and destroys all attached observers. This is called automatically when
the session ends via the `onSessionEnded` hook installed by
`register_session()`. Direct calls are only needed for explicit early
cleanup (e.g. in tests).

### Session-scoped handlers

Each registered session maintains a named slot list for Shiny `Observer`
objects called *handlers*. This provides a lightweight system for
attaching module-level life-cycle hooks that are tied to the session's
lifetime.

**User-defined handlers — `get_handler()` / `set_handler()`**

`set_handler(name, handler)` installs `handler` under `name`, first
suspending and destroying any `Observer` already stored there. Pass
`handler = NULL` to clear the slot. Returns `FALSE` invisibly if the
session is already closed.

`get_handler(name)` retrieves the stored `Observer` (or `NULL`). It
auto-registers the session if not yet registered and returns `NULL`
gracefully if the session is closed.

Three handler names are reserved for internal shidashi infrastructure
and will raise an error if passed to `set_handler`: `"event_handler"`,
`"broadcast_handler"`, and `"input_sync_handler"`.

**Built-in cross-tab sync handlers**

shidashi installs two opt-in `Observer` slots in every registered
session (both start *suspended*):

- Input broadcast (`enable_input_broadcast()` /
  `disable_input_broadcast()`):

  Continuously monitors the session's `input` values and, whenever they
  change, pushes a snapshot to the client via
  `shidashi.cache_session_input`. Other browser tabs sharing the same
  `shared_id` can read this cached snapshot to restore or compare input
  state.

- Input sync (`enable_input_sync()` / `disable_input_sync()`):

  Listens for serialized input maps broadcast by *other* sessions
  sharing the same `shared_id` via the root-session `@shidashi@` input.
  Values differing from the local `input` are written into the session's
  private `inputs` `reactiveValues`. Messages from the same session are
  ignored to prevent feedback loops.

Both observers run at priority `-100000` (after all ordinary reactive
computations have settled). Use `once = TRUE` to trigger a single cycle
without permanently resuming the observer. The `disable_*` variants
suspend the observer and are silent no-ops when the session has already
ended.

### Session life-cycle


    init_app()                       # global.R, once per app start
        |
        v
    register_session(session)        # top of each module server()
        |
        v
    ... reactive code ...
        get_handler() / set_handler() # attach user-defined session observers
        enable_input_broadcast()      # optional: push inputs to browser cache
        enable_input_sync()           # optional: receive peer-tab inputs
        |
        v
    session ends -> unregister_session()  # runs automatically

## Examples

``` r

library(shiny)

# --- Basic usage in a module server ---
server <- function(input, output, session) {
  shidashi::register_session(session)

  # opt-in to cross-tab input broadcast (suspended by default)
  shidashi::enable_input_broadcast(session)

  # opt-in to receive inputs from peer tabs
  shidashi::enable_input_sync(session)

  # get_theme must be called within a reactive context
  output$plot <- renderPlot({
    theme <- shidashi::get_theme()
    par(bg = theme$background, fg = theme$foreground)
    plot(1:10)
  })
}

# --- Named handler: attach a reusable session-scoped observer ---
server2 <- function(input, output, session) {
  shidashi::register_session(session)

  cleanup <- shiny::observe({
    # ... module-level teardown logic ...
    shidashi::set_handler("my_cleanup", NULL, session)
  }, suspended = TRUE, domain = session)

  shidashi::set_handler("my_cleanup", cleanup, session)

  # retrieve and resume the observer elsewhere in the same session
  h <- shidashi::get_handler("my_cleanup", session)
  if (!is.null(h)) h$resume()
}
```
