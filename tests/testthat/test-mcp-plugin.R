# The stdio proxy shipped as a Claude plugin (inst/mcp-proxy/)

# The plugin files are left out of the built package (.Rbuildignore), so
# these tests only run from the source tree.
plugin_file <- function(...) {
  inst <- testthat::test_path("..", "..", "inst")
  if (!dir.exists(inst)) {
    testthat::skip("plugin files are not part of the built package")
  }
  file.path(inst, "mcp-proxy", ...)
}

skip_without_node <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("processx")
  testthat::skip_if(!nzchar(Sys.which("node")), "node is not installed")
}

# A copy of the proxy in a folder that is not `mcp_server/`, like the one
# Claude installs a plugin into
plugin_copy <- function() {
  dir <- tempfile("plugin-")
  dir.create(dir)
  file.copy(
    system.file("mcp-proxy", "shidashi-proxy.mjs", package = "shidashi"),
    file.path(dir, "shidashi-proxy.mjs")
  )
  file.path(dir, "shidashi-proxy.mjs")
}

# Write a proxy-meta.json whose instructions carry `marker`
write_marker_meta <- function(cache, marker) {
  dir.create(file.path(cache, "mcp_server"), recursive = TRUE,
             showWarnings = FALSE)
  writeLines(
    jsonlite::toJSON(list(
      instructions = marker,
      tools = list(list(
        name = "marker_tool",
        inputSchema = list(type = "object")
      ))
    ), auto_unbox = TRUE),
    file.path(cache, "mcp_server", "proxy-meta.json")
  )
}

# Environment for a child process: the cache variables are cleared unless
# given (an empty value counts as unset, as in R); the call log is off
# unless a test turns it on
proxy_env <- function(...) {
  env <- c(SHIDASHI_CACHE_DIR = "", R_USER_CACHE_DIR = "", XDG_CACHE_HOME = "",
           SHIDASHI_MCP_LOG = "false")
  given <- c(...)
  env[names(given)] <- given
  c("current", env)
}

# Send JSON-RPC requests to the proxy; returns the responses by id
run_proxy <- function(script, env, requests) {
  input <- tempfile(fileext = ".jsonl")
  writeLines(vapply(requests, jsonlite::toJSON, "", auto_unbox = TRUE), input)
  result <- processx::run("node", script, env = env, stdin = input,
                          timeout = 20)
  lines <- strsplit(result$stdout, "\n", fixed = TRUE)[[1]]
  messages <- lapply(lines[nzchar(lines)], jsonlite::fromJSON,
                     simplifyVector = FALSE)
  messages <- Filter(function(m) !is.null(m$id), messages)
  structure(messages, names = vapply(messages, function(m) {
    as.character(m$id)
  }, ""))
}

initialize_request <- list(jsonrpc = "2.0", id = "init",
                           method = "initialize", params = list())
tools_list_request <- list(jsonrpc = "2.0", id = "tools",
                           method = "tools/list", params = list())

tool_names <- function(response) {
  vapply(response$result$tools, `[[`, "", "name")
}

test_that("the plugin manifest names the package and its release", {
  manifest <- jsonlite::fromJSON(
    plugin_file(".claude-plugin", "plugin.json"), simplifyVector = FALSE
  )
  expect_identical(manifest$name, "shidashi")
  # The plugin and the package share major.minor.patch, but the development
  # number (the fourth part) may differ
  release <- function(version) format(package_version(version)[, 1:3])
  expect_identical(release(manifest$version),
                   release(utils::packageDescription("shidashi")$Version))
})

test_that("the plugin starts the proxy that ships next to it", {
  config <- jsonlite::fromJSON(plugin_file(".mcp.json"),
                               simplifyVector = FALSE)
  server <- config$mcpServers$shidashi
  expect_identical(server$command, "node")
  expect_identical(unlist(server$args),
                   "${CLAUDE_PLUGIN_ROOT}/shidashi-proxy.mjs")
  expect_true(file.exists(plugin_file("shidashi-proxy.mjs")))
})

test_that("the proxy uses the cache folder named by SHIDASHI_CACHE_DIR", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  write_marker_meta(cache, "from SHIDASHI_CACHE_DIR")
  writeLines(
    jsonlite::toJSON(list(saved_marker_app = list(
      root_path = tempdir(), modules = list("demo")
    )), auto_unbox = TRUE),
    file.path(cache, "launchers.json")
  )

  responses <- run_proxy(
    plugin_copy(),
    proxy_env(SHIDASHI_CACHE_DIR = cache),
    list(
      initialize_request,
      tools_list_request,
      list(jsonrpc = "2.0", id = "launchers", method = "tools/call",
           params = list(name = "shidashi_launchers",
                         arguments = structure(list(), names = character())))
    )
  )
  expect_match(responses$init$result$instructions, "from SHIDASHI_CACHE_DIR",
               fixed = TRUE)
  expect_true("marker_tool" %in% tool_names(responses$tools))
  expect_match(responses$launchers$result$content[[1]]$text,
               "saved_marker_app", fixed = TRUE)
})

test_that("the proxy finds the cache folder the way tools::R_user_dir does", {
  skip_without_node()
  home <- tempfile("home-")
  dir.create(home)
  cases <- list(
    list(R_USER_CACHE_DIR = tempfile("r-user-cache-")),
    list(XDG_CACHE_HOME = tempfile("xdg-cache-")),
    # the platform default under the user's home folder
    list(HOME = home, LOCALAPPDATA = file.path(home, "AppData", "Local"))
  )
  for (case in cases) {
    env <- do.call(proxy_env, case)
    expected <- processx::run(
      file.path(R.home("bin"), "Rscript"),
      c("--vanilla", "-e", "cat(tools::R_user_dir('shidashi', 'cache'))"),
      env = env
    )$stdout
    marker <- paste("R_user_dir", names(case)[[1]])
    write_marker_meta(expected, marker)

    responses <- run_proxy(plugin_copy(), env, list(initialize_request))
    expect_match(responses$init$result$instructions, marker, fixed = TRUE)
  }
})

test_that("a proxy copied into mcp_server/ uses the folder it sits in", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  script <- setup_mcp_proxy(verbose = FALSE)

  responses <- run_proxy(script, proxy_env(),
                         list(initialize_request, tools_list_request))
  expect_match(responses$init$result$instructions, "_module", fixed = TRUE)
  expect_true("shidashi_sessions" %in% tool_names(responses$tools))
})

test_that("the proxy finishes a long last reply before it exits", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  write_marker_meta(cache, strrep("long instructions ", 20000))

  responses <- run_proxy(plugin_copy(),
                         proxy_env(SHIDASHI_CACHE_DIR = cache),
                         list(initialize_request))
  expect_gt(nchar(responses$init$result$instructions), 300000)
})

test_that("the proxy reads meta tools written after it started", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  dir.create(cache)
  proc <- processx::process$new(
    "node", plugin_copy(),
    env = proxy_env(SHIDASHI_CACHE_DIR = cache),
    stdin = "|", stdout = "|", stderr = "|"
  )
  on.exit(proc$kill(), add = TRUE)

  ask <- function(request) {
    proc$write_input(paste0(jsonlite::toJSON(request, auto_unbox = TRUE), "\n"))
    deadline <- Sys.time() + 10
    while (Sys.time() < deadline) {
      proc$poll_io(500)
      line <- proc$read_output_lines(n = 1)
      if (length(line)) {
        message <- jsonlite::fromJSON(line, simplifyVector = FALSE)
        if (identical(message$id, request$id)) return(message)
      }
    }
    stop("the proxy did not answer ", request$id)
  }

  before <- ask(tools_list_request)
  expect_false("marker_tool" %in% tool_names(before))

  write_marker_meta(cache, "written later")
  after <- ask(tools_list_request)
  expect_true("marker_tool" %in% tool_names(after))
  expect_match(ask(initialize_request)$result$instructions, "written later",
               fixed = TRUE)
})

# ---- app records, stale apps, and the call log ----------------------------

# A stand-in for a running app on a free port: it answers every JSON-RPC
# request with a text result `text`, and `GET /mcp` with status ok
start_fake_app <- function(text, app_id = "fake0001") {
  testthat::skip_if_not_installed("httpuv")
  port <- httpuv::randomPort()
  code <- sprintf(paste(
    "httpuv::runServer('127.0.0.1', %d, list(call = function(req) {",
    "  if (!identical(req$REQUEST_METHOD, 'POST')) {",
    sprintf(paste0("    return(list(status = 200L, body = '{\"status\":\"ok\",",
                   "\"server\":\"shidashi\",\"app_id\":\"%s\"}',"), app_id),
    "                headers = list('Content-Type' = 'application/json')))",
    "  }",
    "  msg <- jsonlite::fromJSON(rawToChar(req$rook.input$read()),",
    "                            simplifyVector = FALSE)",
    "  reply <- list(jsonrpc = '2.0', id = msg$id, result = list(",
    "    content = list(list(type = 'text', text = %s)), isError = FALSE))",
    "  list(status = 200L, headers = list('Content-Type' = 'application/json'),",
    "       body = as.character(jsonlite::toJSON(reply, auto_unbox = TRUE)))",
    "}))",
    sep = "\n"
  ), port, deparse(text))
  proc <- processx::process$new(
    file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", code),
    stdout = NULL, stderr = NULL
  )
  deadline <- Sys.time() + 20
  repeat {
    answered <- tryCatch({
      httr2::req_perform(httr2::request(sprintf("http://127.0.0.1:%d/mcp", port)))
      TRUE
    }, error = function(e) FALSE)
    if (answered) break
    if (Sys.time() > deadline || !proc$is_alive()) {
      proc$kill()
      stop("the fake app did not start")
    }
    Sys.sleep(0.2)
  }
  list(proc = proc, port = port)
}

# Write an app record the way R does (`mcp_write_app_record()`)
write_app_record <- function(cache, app_id, port, pid, started,
                             log_dir = NULL) {
  appdir <- tempfile(paste0("app-", app_id, "-"))
  dir.create(appdir)
  record <- list(app_id = app_id,
                 appdir = normalizePath(appdir, winslash = "/"),
                 host = "127.0.0.1", port = port, pid = pid,
                 started = started)
  if (!is.null(log_dir)) {
    record$log_dir <- log_dir
  }
  records_dir <- file.path(cache, "mcp_server", "apps")
  dir.create(records_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(records_dir, paste0(app_id, ".json"))
  writeLines(jsonlite::toJSON(record, auto_unbox = TRUE), path)
  path
}

tool_call_request <- function(id, name,
                              arguments = structure(list(), names = character())) {
  list(jsonrpc = "2.0", id = id, method = "tools/call",
       params = list(name = name, arguments = arguments))
}

test_that("the proxy skips app records whose port does not answer", {
  skip_without_node()
  skip_on_cran()
  cache <- tempfile("shidashi-cache-")
  app <- start_fake_app("from the live app")
  on.exit(app$proc$kill(), add = TRUE)
  write_app_record(cache, "live0001", port = app$port,
                   pid = app$proc$get_pid(),
                   started = "2000-01-01T00:00:00.000Z")
  # newer, and its process is alive, but nothing listens on its port
  stale <- write_app_record(cache, "stale001", port = httpuv::randomPort(),
                            pid = Sys.getpid(),
                            started = "2099-01-01T00:00:00.000Z")

  responses <- run_proxy(
    plugin_copy(), proxy_env(SHIDASHI_CACHE_DIR = cache),
    list(initialize_request, tool_call_request("sessions", "shidashi_sessions"))
  )
  expect_identical(responses$sessions$result$content[[1]]$text,
                   "from the live app")
  expect_true(file.exists(stale))
})

test_that("the proxy logs the calls it answers itself", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")

  run_proxy(
    plugin_copy(),
    proxy_env(SHIDASHI_CACHE_DIR = cache, SHIDASHI_MCP_LOG = "true"),
    list(
      initialize_request,
      tool_call_request("launchers", "shidashi_launchers"),
      tool_call_request("info", "shiny_input_info",
                        list(inputIds = list("x"))),
      list(jsonrpc = "2.0", method = "notifications/cancelled",
           params = list(requestId = "info", reason = "timeout"))
    )
  )

  folders <- list.files(file.path(cache, "MCP-logs"), full.names = TRUE)
  expect_length(folders, 1L)
  expect_match(basename(folders), "^date-\\d{6}T\\d{6}_app-none$")
  lines <- readLines(file.path(folders, "mcp-calls.log"))
  expect_length(lines, 5L)
  expect_true(all(grepl("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3} ",
                        lines)))
  expect_true(all(grepl(" (proxy) ", lines, fixed = TRUE)))
  expect_true(all(nchar(lines) <= 300L))
  has_line <- function(pattern) any(grepl(pattern, lines))
  expect_true(has_line(
    "\\[request\\] \\[shidashi_launchers\\] id=launchers \\(proxy\\) \\{\\}$"
  ))
  expect_true(has_line(
    "\\[response\\] \\[shidashi_launchers\\] id=launchers \\d+\\.\\d{2}s \\(proxy\\) "
  ))
  expect_true(has_line(
    "\\[request\\] \\[shiny_input_info\\] id=info \\(proxy\\) \\{\"inputIds\":\\[\"x\"\\]\\}$"
  ))
  expect_true(has_line(paste0(
    "\\[failed\\] \\[shiny_input_info\\] id=info \\d+\\.\\d{2}s \\(proxy\\) ",
    "\\{reason: \"No shidashi app is running"
  )))
  expect_true(has_line(paste0(
    "\\[request\\] \\[notifications/cancelled\\] \\(proxy\\) ",
    "\\{\"requestId\":\"info\",\"reason\":\"timeout\"\\}$"
  )))
})

test_that("a call that never reached the app is logged in that app's folder", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  log_dir <- file.path(cache, "MCP-logs", "date-260101T000000_app-stale001")
  write_app_record(cache, "stale001", port = httpuv::randomPort(),
                   pid = Sys.getpid(), started = "2099-01-01T00:00:00.000Z",
                   log_dir = log_dir)

  run_proxy(
    plugin_copy(),
    proxy_env(SHIDASHI_CACHE_DIR = cache, SHIDASHI_MCP_LOG = "true"),
    list(initialize_request, tool_call_request("info", "shiny_input_info"))
  )

  lines <- readLines(file.path(log_dir, "mcp-calls.log"))
  expect_true(any(grepl(
    "\\[failed\\] \\[shiny_input_info\\] id=info \\d+\\.\\d{2}s \\(proxy\\)", lines
  )))
})

test_that("SHIDASHI_MCP_LOG turns the proxy's log off, in any case", {
  skip_without_node()
  for (value in c("FALSE", "false", "0")) {
    cache <- tempfile("shidashi-cache-")
    run_proxy(
      plugin_copy(),
      proxy_env(SHIDASHI_CACHE_DIR = cache, SHIDASHI_MCP_LOG = value),
      list(initialize_request, tool_call_request("launchers", "shidashi_launchers"))
    )
    expect_false(dir.exists(file.path(cache, "MCP-logs")))
  }
})

# ---- the RAVE skill's find-rave.R ------------------------------------------

run_find_rave <- function(args, env = character()) {
  processx::run(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", plugin_file("skills", "rave", "scripts", "find-rave.R"), args),
    env = c("current", env), error_on_status = FALSE, timeout = 60
  )
}

# A RAVE session folder under `root`; with `port`, its server info names
# that port (as shidashi writes it while the app runs)
fake_rave_session <- function(root, session_id, port = NULL) {
  dir <- file.path(root, session_id)
  dir.create(file.path(dir, "logs"), recursive = TRUE)
  writeLines("INFO session started", file.path(dir, "logs", "base.log"))
  if (!is.null(port)) {
    url <- sprintf("http://127.0.0.1:%d/", port)
    writeLines(c(
      "app_id: fake0001", paste("pid:", Sys.getpid()),
      "started: 2026-10-07 15:06:31 EDT", "host: 127.0.0.1",
      paste("port:", port), paste("url:", url), paste0("mcp: ", url, "mcp"),
      "mcp_log: /logs/date-261007T150631_app-fake0001"
    ), file.path(dir, "logs", "server-info.log"))
  }
  normalizePath(dir)
}

test_that("find-rave.R lists RAVE sessions and which ones answer", {
  skip_on_cran()
  skip_if_not_installed("ravedash")
  app <- start_fake_app("x", app_id = "fake0001")
  on.exit(app$proc$kill(), add = TRUE)
  root <- tempfile("rave-sessions-")
  dir.create(root)
  running <- fake_rave_session(root, "session-261008-101500-EDT-BBBB", app$port)
  stopped <- fake_rave_session(root, "session-261007-150628-EDT-SPH8",
                               httpuv::randomPort())
  old <- fake_rave_session(root, "session-261001-090000-EDT-CCCC")

  res <- run_find_rave(c(paste0("--root=", root), "--testing-port=0"))
  expect_identical(res$status, 0L)
  out <- res$stdout
  # newest first
  expect_lt(regexpr("BBBB", out), regexpr("SPH8", out))
  expect_lt(regexpr("SPH8", out), regexpr("CCCC", out))
  expect_match(out, sprintf("answers at http://127.0.0.1:%d/", app$port),
               fixed = TRUE)
  expect_match(out, "does not answer", fixed = TRUE)
  expect_match(out, "no logs/server-info.log", fixed = TRUE)
  expect_match(out, file.path(running, "logs", "base.log"), fixed = TRUE)
  expect_match(out, "date-261007T150631_app-fake0001", fixed = TRUE)
})

test_that("find-rave.R --open opens an app only when it answers", {
  skip_on_cran()
  skip_on_os("windows")
  app <- start_fake_app("x")
  on.exit(app$proc$kill(), add = TRUE)
  opened <- tempfile("opened-")
  browser <- tempfile("browser-")
  writeLines(c("#!/bin/sh", sprintf("echo \"$@\" >> '%s'", opened)), browser)
  Sys.chmod(browser, "0755")

  res <- run_find_rave(sprintf("--open=%d", httpuv::randomPort()),
                       env = c(R_BROWSER = browser))
  expect_identical(res$status, 1L)
  expect_match(res$stdout, "nothing was opened", fixed = TRUE)

  res <- run_find_rave(sprintf("--open=%d", app$port),
                       env = c(R_BROWSER = browser))
  expect_identical(res$status, 0L)
  deadline <- Sys.time() + 10
  while (!file.exists(opened) && Sys.time() < deadline) Sys.sleep(0.1)
  expect_identical(readLines(opened),
                   sprintf("http://127.0.0.1:%d/", app$port))
})
