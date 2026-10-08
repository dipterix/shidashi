# The MCP call log:
# <cache>/MCP-logs/date-<yymmddTHHMMSS>_app-<app_id>/mcp-calls.log

# A fresh cache folder for one test, with logging on
local_log_cache <- function(env = parent.frame()) {
  cache <- tempfile("shidashi-cache-")
  withr::local_options(list(shidashi.cache_dir = cache, shidashi.mcp_log = NULL),
                       .local_envir = env)
  withr::local_envvar(c(SHIDASHI_MCP_LOG = ""), .local_envir = env)
  cache
}

# The lines of this app's call log
log_lines <- function() {
  path <- file.path(mcp_log_dir(), "mcp-calls.log")
  if (!file.exists(path)) {
    return(character(0))
  }
  readLines(path, encoding = "UTF-8", warn = FALSE)
}

call_tool <- function(app, name,
                      arguments = structure(list(), names = character(0)),
                      id = 1) {
  app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = id, method = "tools/call",
    params = list(name = name, arguments = arguments)
  )))
}

# A request whose body is the raw text `body`
raw_mcp_request <- function(body) {
  list(
    PATH_INFO      = "/mcp",
    REQUEST_METHOD = "POST",
    rook.input     = list(read = function(...) charToRaw(body))
  )
}

log_time <- "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3} "

test_that("the call log folder is named by the app's start time and id", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())

  dir <- mcp_log_dir()
  expect_identical(dirname(dir), file.path(shidashi_cache_dir(), "MCP-logs"))
  expect_match(basename(dir),
               sprintf("^date-\\d{6}T\\d{6}_app-%s$", mcp_app_id()))
})

test_that("a tool call writes a request line and a response line", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__hello")

  call_tool(app, "tool__hello", list(`_module` = "alpha"), id = 7)

  lines <- log_lines()
  expect_length(lines, 2L)
  expect_match(lines[[1]], paste0(
    log_time, "\\[request\\] \\[tool__hello\\] id=7 \\{\"_module\":\"alpha\"\\}$"
  ))
  expect_match(lines[[2]], paste0(
    log_time, "\\[response\\] \\[tool__hello\\] id=7 \\d+\\.\\d{2}s \"tool__hello"
  ))
})

test_that("a tool error is logged as failed, with its reason", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  call_tool(app, "tool__hello")

  lines <- log_lines()
  expect_length(lines, 2L)
  expect_match(lines[[2]], paste0(
    log_time, "\\[failed\\] \\[tool__hello\\] id=1 \\d+\\.\\d{2}s ",
    "\\{reason: \"No dashboard module is open"
  ))
})

test_that("JSON-RPC errors and unreadable requests are logged as failed", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  app$httpHandler(mcp_request(list(jsonrpc = "2.0", id = 3,
                                   method = "foo/bar")))
  app$httpHandler(raw_mcp_request("{oops"))
  app$httpHandler(raw_mcp_request(""))

  lines <- log_lines()
  expect_length(lines, 4L)
  expect_match(lines[[1]], "\\[request\\] \\[foo/bar\\] id=3 \\{\\}$")
  expect_match(lines[[2]], paste0(
    "\\[failed\\] \\[foo/bar\\] id=3 \\d+\\.\\d{2}s ",
    "\\{reason: \"Method not found: foo/bar\"\\}$"
  ))
  expect_match(lines[[3]], "\\[failed\\] \\[\\?\\] .*Parse error: invalid JSON")
  expect_match(lines[[4]], "\\[failed\\] \\[\\?\\] .*Parse error: empty body")
})

test_that("shidashi_call is logged with the tool it calls", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__live_only")

  call_tool(app, "shidashi_call",
            list(tool = "tool__live_only", arguments = "{}"))

  lines <- log_lines()
  expect_match(lines[[1]], "\\[request\\] \\[shidashi_call:tool__live_only\\]")
  expect_match(lines[[2]], "\\[response\\] \\[shidashi_call:tool__live_only\\]")
})

test_that("tools/list replies are logged as a tool count", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  res <- app$httpHandler(mcp_request(list(jsonrpc = "2.0", id = 2,
                                          method = "tools/list")))
  n_tools <- length(mcp_body(res)$result$tools)

  lines <- log_lines()
  expect_length(lines, 2L)
  expect_match(lines[[2]], sprintf(
    "\\[response\\] \\[tools/list\\] id=2 \\d+\\.\\d{2}s \\{\"tools\":%d\\}$",
    n_tools
  ))
})

test_that("notifications get a request line only", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", method = "notifications/initialized"
  )))
  expect_identical(res$status, 202L)

  lines <- log_lines()
  expect_length(lines, 1L)
  expect_match(lines[[1]],
               paste0(log_time, "\\[request\\] \\[notifications/initialized\\] \\{\\}$"))
})

test_that("each event stays on one line of at most 300 characters", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__hello")

  long_text <- paste(rep("line one\nline two", 100), collapse = "\n")
  call_tool(app, "tool__hello", list(`_module` = "alpha", note = long_text))

  lines <- log_lines()
  expect_length(lines, 2L)
  expect_true(all(nchar(lines) <= 300L))
  expect_match(lines[[1]], "\\.\\.\\.$")
  expect_match(lines[[1]], "line one\\\\nline two", fixed = FALSE)
})

test_that("an async reply is logged once it settles", {
  local_log_cache()
  withr::local_options(list(shidashi.switch_module_timeout = 0.3))
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__hello")

  res <- call_tool(app, "switch_module", list(module_id = "alpha"), id = 9)
  expect_true(promises::is.promise(res))
  expect_length(log_lines(), 1L)

  wait_for_promise(res)
  lines <- log_lines()
  expect_length(lines, 2L)
  expect_match(lines[[2]], paste0(
    "\\[failed\\] \\[switch_module\\] id=9 \\d+\\.\\d{2}s ",
    "\\{reason: \"The browser did not answer"
  ))
})

test_that("a rejected reply is logged as failed and still rejects", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())

  call <- mcp_log_new_call()
  mcp_log_request(call, method = "tools/call", id = 4,
                  params = list(name = "tool__slow", arguments = list()))
  res <- mcp_log_finish(call, promises::promise_reject(simpleError("boom")))

  expect_error(wait_for_promise(res), "boom")
  lines <- log_lines()
  expect_length(lines, 2L)
  expect_match(lines[[2]],
               "\\[failed\\] \\[tool__slow\\] id=4 \\d+\\.\\d{2}s \\{reason: \"boom\"\\}$")
})

test_that("skill scripts that exit with an error are logged as failed", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())

  reply <- function(text) {
    mcp_json_result(5, list(
      content = list(list(type = "text", text = text)),
      isError = FALSE
    ))
  }
  run <- function(text) {
    call <- mcp_log_new_call()
    mcp_log_request(call, method = "tools/call", id = 5,
                    params = list(name = "skill_run", arguments = list()))
    mcp_log_finish(call, reply(text))
  }

  run("## stdout\nfine\n\nExit code: 0")
  run("## stderr\nError: no such file\n\nExit code: 1")
  run("## stdout\nstill going\n\nExit code: -9\nWARNING: Script timed out after 60 seconds.")

  lines <- log_lines()
  expect_length(lines, 6L)
  expect_match(lines[[2]], "\\[response\\] \\[skill_run\\]")
  expect_match(lines[[4]],
               "\\[failed\\] \\[skill_run\\] .*\\{reason: \"Exit code: 1; ")
  expect_match(lines[[6]], "\\[failed\\] \\[skill_run\\] .*timed out")
})

test_that("logging can be turned off with the option or the variable", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  off <- list(
    list(options = list(shidashi.mcp_log = FALSE), env = c(SHIDASHI_MCP_LOG = "")),
    list(options = list(shidashi.mcp_log = NULL), env = c(SHIDASHI_MCP_LOG = "FALSE")),
    list(options = list(shidashi.mcp_log = NULL), env = c(SHIDASHI_MCP_LOG = "false")),
    list(options = list(shidashi.mcp_log = NULL), env = c(SHIDASHI_MCP_LOG = "0"))
  )
  for (setting in off) {
    withr::with_options(
      c(list(shidashi.cache_dir = tempfile("shidashi-cache-")), setting$options),
      withr::with_envvar(setting$env, {
        app$httpHandler(mcp_request(list(jsonrpc = "2.0", id = 1,
                                         method = "ping")))
        expect_false(dir.exists(file.path(shidashi_cache_dir(), "MCP-logs")))
      })
    )
  }
})

test_that("app records name the log folder, and old log folders are pruned", {
  cache <- local_log_cache()
  withr::local_options(list(shidashi.mcp_log_keep = 3))
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")

  log_root <- file.path(cache, "MCP-logs")
  old <- sprintf("date-0%d0101T000000_app-old%d", 1:5, 1:5)
  for (name in old) {
    dir.create(file.path(log_root, name), recursive = TRUE)
  }

  path <- mcp_write_app_record(port = 8124, appdir = root,
                               records_dir = records_dir)
  record <- jsonlite::read_json(path)
  expect_identical(record$log_dir, mcp_log_dir())
  expect_match(basename(record$log_dir), "^date-\\d{6}T\\d{6}_app-")

  # the newest three folders stay
  expect_setequal(list.files(log_root), old[3:5])

  # with logging off, the record names no folder
  withr::local_options(list(shidashi.mcp_log = FALSE))
  path <- mcp_write_app_record(port = 8124, appdir = root,
                               records_dir = records_dir)
  expect_null(jsonlite::read_json(path)$log_dir)
})

test_that("the request line keeps the arguments as the client sent them", {
  local_log_cache()
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__hello")

  call_tool(app, "tool__hello", list(`_module` = "alpha", ids = list("x"), n = 1))

  # a one-element array stays an array: `"ids":"x"` would hide a wrong type
  expect_match(log_lines()[[1]],
               '\\{"_module":"alpha","ids":\\["x"\\],"n":1\\}$')
})
