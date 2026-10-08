# `<app>/logs/server-info.log`: where a running app answers. It is written
# with the app record and removed, with the record, when the app stops.

local_server_info_cache <- function(env = parent.frame()) {
  withr::local_options(
    list(shidashi.cache_dir = tempfile("shidashi-cache-"),
         shidashi.mcp_log = NULL),
    .local_envir = env
  )
  withr::local_envvar(c(SHIDASHI_MCP_LOG = ""), .local_envir = env)
}

# `key: value` lines as a named list
read_server_info <- function(path) {
  lines <- readLines(path, warn = FALSE)
  keys <- sub(":.*$", "", lines)
  values <- sub("^[^:]+:[[:space:]]*", "", lines)
  structure(as.list(values), names = keys)
}

result_text <- function(result) {
  paste(vapply(result$content, `[[`, "", "text"), collapse = "\n")
}

# A dashboard page without a module, as the registry holds it
fake_dashboard_page <- function() {
  session <- shiny::MockShinySession$new()
  activity <- new_fastmap(missing_default = NULL)
  globals_session_registry()$set(session$token, list(
    shiny_session = session,
    namespace     = "",
    tools         = new_fastmap(),
    activity      = activity,
    registered_at = Sys.time()
  ))
  session$token
}

test_that("the app record comes with logs/server-info.log", {
  local_server_info_cache()
  root <- use_template_root(make_mini_template())

  mcp_write_app_record(port = 8124, appdir = root,
                       records_dir = tempfile("apps-"))

  info <- read_server_info(file.path(root, "logs", "server-info.log"))
  expect_identical(names(info), c("app_id", "pid", "started", "host", "port",
                                  "url", "mcp", "mcp_log"))
  expect_identical(info$app_id, mcp_app_id())
  expect_identical(info$pid, as.character(Sys.getpid()))
  expect_match(info$started, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}")
  expect_identical(info$host, "127.0.0.1")
  expect_identical(info$port, "8124")
  expect_identical(info$url, "http://127.0.0.1:8124/")
  expect_identical(info$mcp, "http://127.0.0.1:8124/mcp")
  expect_identical(info$mcp_log, mcp_log_dir())
})

test_that("a wildcard host is written as an address on this computer", {
  local_server_info_cache()
  withr::local_options(list(shidashi.mcp_log = FALSE))
  root <- use_template_root(make_mini_template())

  mcp_write_app_record(port = 8125, appdir = root, host = "0.0.0.0",
                       records_dir = tempfile("apps-"))

  info <- read_server_info(file.path(root, "logs", "server-info.log"))
  expect_identical(info$host, "0.0.0.0")
  expect_identical(info$url, "http://127.0.0.1:8125/")
  expect_null(info$mcp_log)
})

test_that("removing the app files leaves another process's files alone", {
  local_server_info_cache()
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")
  record_path <- mcp_write_app_record(port = 8124, appdir = root,
                                      records_dir = records_dir)
  info_path <- file.path(root, "logs", "server-info.log")

  # another process has taken over the same app folder since
  other_pid <- Sys.getpid() + 1L
  record <- jsonlite::read_json(record_path)
  record$pid <- other_pid
  writeLines(jsonlite::toJSON(record, auto_unbox = TRUE), record_path)
  info <- readLines(info_path)
  info[startsWith(info, "pid:")] <- paste("pid:", other_pid)
  writeLines(info, info_path)

  mcp_remove_app_files(record_path, info_path)
  expect_true(file.exists(record_path))
  expect_true(file.exists(info_path))

  # this process's files go
  record_path <- mcp_write_app_record(port = 8124, appdir = root,
                                      records_dir = records_dir)
  mcp_remove_app_files(record_path, info_path)
  expect_false(file.exists(record_path))
  expect_false(file.exists(info_path))
})

test_that("stopping the app removes its record and server info", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  local_server_info_cache()
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")
  port <- httpuv::randomPort()

  app <- register_mcp_route(
    shiny::shinyApp(shiny::fluidPage(), function(input, output, session) {}),
    port = port, appdir = root, records_dir = records_dir
  )
  record_path <- file.path(records_dir, paste0(mcp_app_id(), ".json"))
  info_path <- file.path(root, "logs", "server-info.log")
  expect_true(file.exists(record_path))
  expect_true(file.exists(info_path))

  later::later(function() shiny::stopApp(), 0.5)
  shiny::runApp(app, port = port, launch.browser = FALSE, quiet = TRUE)

  expect_false(file.exists(record_path))
  expect_false(file.exists(info_path))
})

test_that("with no page open, switch_module and tool calls give the app link", {
  local_server_info_cache()
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  mcp_write_app_record(port = 8124, appdir = root,
                       records_dir = tempfile("apps-"))
  link <- "[Open the dashboard](http://127.0.0.1:8124/)"

  switched <- mcp_tool_switch_module(list(module_id = "alpha"))
  expect_true(switched$isError)
  expect_match(result_text(switched), "No dashboard page is open", fixed = TRUE)
  expect_match(result_text(switched), link, fixed = TRUE)
  expect_match(result_text(switched), "GET http://127.0.0.1:8124/mcp",
               fixed = TRUE)
  expect_match(result_text(switched), "utils::browseURL()", fixed = TRUE)

  app <- mcp_test_app()
  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = "tool__hello", arguments = list())
  )))
  text <- mcp_body(res)$result$content[[1]]$text
  expect_match(text, "No dashboard module is open", fixed = TRUE)
  expect_match(text, link, fixed = TRUE)
})

test_that("with only the dashboard open, a tool call points to switch_module", {
  local_server_info_cache()
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  mcp_write_app_record(port = 8124, appdir = root,
                       records_dir = tempfile("apps-"))
  fake_dashboard_page()

  app <- mcp_test_app()
  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = "tool__hello", arguments = list())
  )))
  text <- mcp_body(res)$result$content[[1]]$text
  expect_match(text, "No dashboard module is open", fixed = TRUE)
  expect_match(text, "switch_module", fixed = TRUE)
  expect_false(grepl("[Open the dashboard]", text, fixed = TRUE))
})
