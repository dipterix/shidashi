# Helpers shared by the MCP tests

# Fresh per-app globals (session registry etc.). Keep the returned
# environment referenced for the duration of the test: the globals are
# held through a weak reference. `init_app()` sets the option
# `shidashi.shared_id`; it is restored when the test ends.
local_mcp_app <- function(env = parent.frame()) {
  withr::local_options(list(shidashi.shared_id = NULL), .local_envir = env)
  app_env <- new.env()
  init_app(app_env)
  app_env
}

# The handle `shidashi_sessions` and the run notes use for a fake session
test_handle <- function(module_id, token) {
  paste0(module_id, "@", substr(token, 1L, 6L))
}

# Register a fake open module in the session registry and return its
# token. `tools` are tool names; each fake tool returns its own name.
fake_module_session <- function(
    module_id,
    tools = character(),
    focused_at = NULL,
    pinned = FALSE,
    registered_at = Sys.time()) {
  session <- shiny::MockShinySession$new()
  tool_map <- new_fastmap()
  lapply(tools, function(tool_name) {
    tool_map$set(tool_name, ellmer::tool(
      function() tool_name,
      name = tool_name,
      description = tool_name
    ))
  })
  activity <- new_fastmap(missing_default = NULL)
  activity$set("focused_at", focused_at)
  activity$set("pinned", pinned)
  globals_session_registry()$set(session$token, list(
    shiny_session = session,
    namespace     = module_id,
    tools         = tool_map,
    activity      = activity,
    registered_at = registered_at
  ))
  session$token
}

# Change the focus/pin state of a fake open module
set_activity <- function(token, ...) {
  activity <- globals_session_registry()$get(token)$activity
  activity$mset(...)
  invisible(token)
}

# A tiny template on disk:
#   alpha - agents enabled, offers `hello`
#   beta  - agents enabled, offers `hello`, but its R code fails to load
#   gamma - no agents.yaml (agents disabled)
make_mini_template <- function() {
  root <- tempfile("mini-template-")
  dir.create(file.path(root, "agents", "tools"), recursive = TRUE)
  for (mid in c("alpha", "beta", "gamma")) {
    dir.create(file.path(root, "modules", mid, "R"), recursive = TRUE)
  }
  writeLines(c(
    "modules:",
    "  alpha:",
    "    label: Alpha",
    "  beta:",
    "    label: Beta",
    "  gamma:",
    "    label: Gamma"
  ), file.path(root, "modules.yaml"))
  writeLines(c(
    "hello <- shidashi::mcp_wrapper(function(session) {",
    "  ellmer::tool(",
    "    function(name = 'world') paste('hi', name),",
    "    name = 'hello',",
    "    description = 'Say hi',",
    "    arguments = list(",
    "      name = ellmer::type_string('Who to greet', required = FALSE)",
    "    )",
    "  )",
    "})"
  ), file.path(root, "agents", "tools", "hello.R"))
  agents_yaml <- c(
    "tools:",
    "- name: hello",
    "  category:",
    "  - exploratory",
    "  enabled: yes"
  )
  writeLines(agents_yaml, file.path(root, "modules", "alpha", "agents.yaml"))
  writeLines(agents_yaml, file.path(root, "modules", "beta", "agents.yaml"))
  writeLines("stop('beta is broken')",
             file.path(root, "modules", "beta", "R", "broken.R"))
  normalizePath(root)
}

# Add a tool to the mini template: its definition in agents/tools, and an
# entry in the agents.yaml of `modules`. `enabled` is written as-is, e.g.
# "yes", "no", or '["Executing"]'. The tool returns "<name> ran".
add_mini_tool <- function(root, name, category = "exploratory",
                          enabled = "yes", modules = "alpha") {
  writeLines(
    sprintf(
      "%s <- ellmer::tool(function() '%s ran', name = '%s', description = '%s tool')",
      name, name, name, name
    ),
    file.path(root, "agents", "tools", paste0(name, ".R"))
  )
  entry <- c(
    sprintf("- name: %s", name),
    "  category:",
    sprintf("  - %s", category),
    sprintf("  enabled: %s", enabled)
  )
  for (module_id in modules) {
    cat(entry, sep = "\n", append = TRUE,
        file = file.path(root, "modules", module_id, "agents.yaml"))
  }
  invisible(root)
}

# Add a skill to the mini template: its folder in agents/skills, and a
# `skills:` section in the agents.yaml of `modules` (call it once per
# module). `scripts` maps script names to their category; each script
# prints "<script> ran".
add_mini_skill <- function(root, name, scripts = character(),
                           modules = "alpha") {
  skill_dir <- file.path(root, "agents", "skills", name)
  dir.create(file.path(skill_dir, "scripts"), recursive = TRUE,
             showWarnings = FALSE)
  writeLines(c(
    "---", sprintf("name: %s", name),
    sprintf("description: %s skill", name), "---", "",
    "## Instructions", "", "Nothing to see."
  ), file.path(skill_dir, "SKILL.md"))
  entry <- c("skills:", sprintf("- name: %s", name), "  enabled: yes")
  if (length(scripts)) {
    entry <- c(entry, "  scripts:")
  }
  for (script in names(scripts)) {
    writeLines(sprintf("cat('%s ran')", script),
               file.path(skill_dir, "scripts", script))
    entry <- c(entry,
               sprintf("  - name: %s", script),
               "    category:",
               sprintf("    - %s", scripts[[script]]),
               "    enabled: yes")
  }
  for (module_id in modules) {
    cat(entry, sep = "\n", append = TRUE,
        file = file.path(root, "modules", module_id, "agents.yaml"))
  }
  invisible(root)
}

# Open a module the way the dashboard does: a (mock) session registered in
# the session registry, holding the module's real permission-wrapped tools.
# Returns the session token.
open_real_module <- function(root, module_id) {
  res <- load_module_resource(root, module_id, new.env(parent = globalenv()))
  session <- shiny::MockShinySession$new()
  register_session(session$makeScope(module_id))
  tools <- res$environment$.mcptools_maker(session)
  get_session_entry(session$token)$tools$mset(.list = tools$as_list())
  session$token
}

# Point template_root() at `root`. Every test that needs a template sets
# its own root, so the value is not restored afterwards.
use_template_root <- function(root) {
  template_settings$set(root_path = root)
  invisible(root)
}

# Follow a promise: an environment whose `done` turns TRUE when it
# settles, with its `value` or `error`
track_promise <- function(p) {
  state <- new.env(parent = emptyenv())
  state$done <- FALSE
  promises::then(
    p,
    onFulfilled = function(value) {
      state$value <- value
      state$done <- TRUE
    },
    onRejected = function(error) {
      state$error <- error
      state$done <- TRUE
    }
  )
  state
}

# Run the event loop until a promise settles; return its value or throw
wait_for_promise <- function(p, timeout = 5) {
  state <- track_promise(p)
  deadline <- Sys.time() + timeout
  while (!state$done && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  if (!state$done) stop("the promise did not settle")
  if (!is.null(state$error)) stop(state$error)
  state$value
}

# Build a Rook-like POST request for the MCP handler
mcp_request <- function(body, path = "/mcp", method = "POST") {
  body_raw <- charToRaw(as.character(
    jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
  ))
  list(
    PATH_INFO      = path,
    REQUEST_METHOD = method,
    rook.input     = list(read = function(...) body_raw)
  )
}

# An app object whose HTTP handler has the MCP route in front
mcp_test_app <- function() {
  register_mcp_route(list(
    httpHandler = function(req) "not mcp",
    staticPaths = list()
  ))
}

mcp_body <- function(response) {
  jsonlite::fromJSON(response$content, simplifyVector = FALSE)
}
