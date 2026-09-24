test_that("MCP paths parse into an optional module", {
  expect_identical(mcp_parse_path("/mcp"), list(module = NULL))
  expect_identical(mcp_parse_path("/mcp/"), list(module = NULL))
  expect_identical(mcp_parse_path("/mcp/demo"), list(module = "demo"))
  expect_identical(mcp_parse_path("/mcp/demo@4f542d"),
                   list(module = "demo@4f542d"))
  expect_identical(mcp_parse_path("/mcp/demo%404f542d"),
                   list(module = "demo@4f542d"))
  expect_null(mcp_parse_path("/mcpx"))
  expect_null(mcp_parse_path("/other"))
  expect_null(mcp_parse_path("/mcp/a/b"))
})

test_that("app id is eight characters from the appdir and process id", {
  root <- use_template_root(make_mini_template())
  expected <- substr(digest::digest(paste(root, Sys.getpid())), 1, 8)
  expect_identical(mcp_app_id(), expected)
})

test_that("non-MCP paths fall through to the default handler", {
  app <- mcp_test_app()
  expect_identical(app$httpHandler(list(PATH_INFO = "/", REQUEST_METHOD = "GET")),
                   "not mcp")
})

test_that("initialize returns instructions and no session id", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "initialize", params = list()
  )))
  expect_identical(res$status, 200L)
  expect_null(res$headers[["Mcp-Session-Id"]])
  body <- mcp_body(res)
  expect_match(body$result$instructions, "_module")
  expect_match(body$result$instructions, "in this\\s+conversation")
  expect_identical(body$result$serverInfo$name, "shidashi")
})

test_that("extra path segments are rejected with 404", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  res <- app$httpHandler(mcp_request(
    list(jsonrpc = "2.0", id = 1, method = "ping"),
    path = "/mcp/a/b"
  ))
  expect_identical(res$status, 404L)
  expect_match(mcp_body(res)$error$message, "/mcp/{module}", fixed = TRUE)

  # one segment is a module, never an app id
  res <- app$httpHandler(mcp_request(
    list(jsonrpc = "2.0", id = 1, method = "ping"),
    path = paste0("/mcp/", mcp_app_id())
  ))
  expect_identical(res$status, 200L)
})

test_that("GET /mcp says it is a shidashi app", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  info <- mcp_body(app$httpHandler(list(PATH_INFO = "/mcp",
                                        REQUEST_METHOD = "GET")))
  expect_identical(info$server, "shidashi")
  expect_identical(info$app_id, mcp_app_id())
})

test_that("DELETE is not supported", {
  app <- mcp_test_app()
  res <- app$httpHandler(list(PATH_INFO = "/mcp", REQUEST_METHOD = "DELETE"))
  expect_identical(res$status, 405L)
})

test_that("tools/list is the same with or without open sessions", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  list_tools <- function() {
    res <- app$httpHandler(mcp_request(list(
      jsonrpc = "2.0", id = 1, method = "tools/list"
    )))
    vapply(mcp_body(res)$result$tools, `[[`, "", "name")
  }

  empty <- list_tools()
  expect_true(all(c("shidashi_sessions", "shidashi_call", "tool__hello")
                  %in% empty))
  expect_false(any(c("register_shinysession", "list_shinysessions",
                     "ask_user") %in% empty))

  fake_module_session("alpha", c("tool__hello", "tool__live_only"))
  expect_identical(list_tools(), empty)
})

test_that("tools/call runs on the resolved module and names it", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  alpha <- fake_module_session("alpha", "tool__hello")

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 7, method = "tools/call",
    params = list(name = "tool__hello",
                  arguments = list(`_module` = "alpha"))
  )))
  body <- mcp_body(res)
  expect_identical(body$id, 7L)
  expect_false(body$result$isError)
  texts <- vapply(body$result$content, `[[`, "", "text")
  expect_true("tool__hello" %in% texts)
  expect_true(any(grepl(paste("ran on", test_handle("alpha", alpha)), texts,
                        fixed = TRUE)))
})

test_that("tools/call says so when no module is open", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = "tool__hello", arguments = list())
  )))
  body <- mcp_body(res)
  expect_true(body$result$isError)
  expect_match(body$result$content[[1]]$text, "No dashboard module is open")
})

test_that("shidashi_call reaches tools that exist only in live sessions", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__live_only")

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = "shidashi_call",
                  arguments = list(tool = "tool__live_only",
                                   arguments = "{}"))
  )))
  texts <- vapply(mcp_body(res)$result$content, `[[`, "", "text")
  expect_true("tool__live_only" %in% texts)
})

test_that("shidashi_sessions lists open modules and the default", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  alpha <- fake_module_session("alpha", "tool__hello", pinned = TRUE)

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = "shidashi_sessions", arguments = list())
  )))
  info <- jsonlite::fromJSON(mcp_body(res)$result$content[[1]]$text,
                             simplifyVector = FALSE)
  expect_identical(info$app$app_id, mcp_app_id())
  expect_identical(info$default_module$handle, test_handle("alpha", alpha))
  expect_identical(info$default_module$reason, "pinned")
  expect_identical(info$open_modules[[1]]$module_id, "alpha")
  expect_null(info$open_modules[[1]]$mode)
  expect_true("beta" %in% unlist(info$modules_not_open))
})

mcp_call <- function(app, name, arguments = structure(list(), names = character(0))) {
  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/call",
    params = list(name = name, arguments = arguments)
  )))
  # a promise would mean the call is waiting on the browser
  expect_false(promises::is.promise(res))
  body <- mcp_body(res)
  list(isError = body$result$isError,
       texts = vapply(body$result$content, `[[`, "", "text"))
}

test_that("agent mode and confirmation policy do not apply to MCP calls", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_tool(root, "wipe", category = c("executing", "destructive"),
                enabled = '["Executing"]')
  app <- mcp_test_app()
  open_real_module(root, "alpha")

  globals_set_agent_mode(module_id = "alpha", mode = "None")
  res <- mcp_call(app, "tool__hello")
  expect_false(res$isError)
  expect_true("hi world" %in% res$texts)

  for (policy in c("ask", "auto_reject")) {
    globals_set_confirmation_policy(module_id = "alpha", policy = policy)
    res <- mcp_call(app, "tool__wipe")
    expect_false(res$isError)
    expect_true("wipe ran" %in% res$texts)
  }
})

test_that("tools turned off in agents.yaml refuse over MCP", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_tool(root, "off_tool", enabled = "no")
  app <- mcp_test_app()
  open_real_module(root, "alpha")

  res <- mcp_call(app, "shidashi_call", list(tool = "tool__off_tool"))
  expect_true(res$isError)
  expect_match(res$texts[[1]], "turned off")
})

test_that("the in-dashboard chat still follows mode and policy", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_tool(root, "wipe", category = c("executing", "destructive"),
                enabled = '["Executing"]')
  token <- open_real_module(root, "alpha")
  tools <- get_session_entry(token)$tools

  # the chat calls the tools directly, not through MCP
  globals_set_agent_mode(module_id = "alpha", mode = "None")
  expect_error(tools$get("tool__hello")(), "Agent mode is [None]", fixed = TRUE)

  globals_set_agent_mode(module_id = "alpha", mode = "Executing")
  globals_set_confirmation_policy(module_id = "alpha", policy = "auto_reject")
  expect_error(tools$get("tool__wipe")(), "rejected by policy")
})

test_that("app record names the app, its directory, port, and process", {
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")
  on.exit(template_settings$set(mcp_app_id = NULL), add = TRUE)

  path <- mcp_write_app_record(port = 8123, appdir = root,
                               records_dir = records_dir)
  record <- jsonlite::fromJSON(path)
  expect_identical(record$app_id, mcp_app_id())
  expect_identical(basename(path), paste0(record$app_id, ".json"))
  expect_identical(record$appdir, normalizePath(root, winslash = "/"))
  expect_identical(record$port, 8123L)
  expect_identical(record$pid, Sys.getpid())
  expect_match(record$started, "^\\d{4}-\\d{2}-\\d{2}T")
})

test_that("register_mcp_route writes an app record when given a port", {
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")
  on.exit(template_settings$set(mcp_app_id = NULL), add = TRUE)

  register_mcp_route(
    list(httpHandler = function(req) NULL, staticPaths = list()),
    port = 8124, appdir = root, records_dir = records_dir
  )
  expect_true(file.exists(file.path(records_dir, paste0(mcp_app_id(), ".json"))))
})

test_that("a module in the URL limits every call to that module", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  alpha <- fake_module_session("alpha", "tool__hello", pinned = TRUE)
  beta <- fake_module_session("beta", "tool__hello")
  beta_note <- paste("ran on", test_handle("beta", beta))

  call_hello <- function(path) {
    res <- app$httpHandler(mcp_request(list(
      jsonrpc = "2.0", id = 1, method = "tools/call",
      params = list(name = "tool__hello", arguments = list())
    ), path = path))
    vapply(mcp_body(res)$result$content, `[[`, "", "text")
  }

  texts <- call_hello("/mcp/beta")
  expect_true(any(grepl(beta_note, texts, fixed = TRUE)))
  texts <- call_hello(paste0("/mcp/", substr(beta, 1, 8)))   # token prefix
  expect_true(any(grepl(beta_note, texts, fixed = TRUE)))
  texts <- call_hello("/mcp")
  expect_true(any(grepl(
    sprintf("ran on %s (pinned)", test_handle("alpha", alpha)),
    texts, fixed = TRUE
  )))
})

test_that("_module pointing away from the pinned module is refused", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  pinned <- fake_module_session("alpha", "tool__hello", pinned = TRUE)
  other <- fake_module_session("alpha", "tool__hello")
  pinned_handle <- paste0("alpha@", substr(pinned, 1, 6))
  other_handle <- paste0("alpha@", substr(other, 1, 6))

  res <- mcp_call(app, "tool__hello", list(`_module` = other_handle))
  expect_true(res$isError)
  expect_false("tool__hello" %in% res$texts)   # the tool did not run
  expect_match(res$texts[[1]], pinned_handle, fixed = TRUE)
  expect_match(res$texts[[1]], "pinned", fixed = TRUE)
  expect_match(res$texts[[1]], "without `_module`", fixed = TRUE)

  res <- mcp_call(app, "tool__hello", list(`_module` = pinned_handle))
  expect_false(res$isError)
  expect_true(any(grepl(sprintf("ran on %s (requested)", pinned_handle),
                        res$texts, fixed = TRUE)))
})

test_that("_module pointing away from the last-used module runs with a warning", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
  beta <- fake_module_session("beta", "tool__hello")

  res <- mcp_call(app, "tool__hello", list(`_module` = "beta"))
  expect_false(res$isError)
  expect_true("tool__hello" %in% res$texts)
  expect_true(any(grepl(sprintf(
    paste(
      "ran on %s (requested handle is different from the current active",
      "handle %s, last used"
    ),
    test_handle("beta", beta), test_handle("alpha", alpha)
  ), res$texts, fixed = TRUE)))

  res <- mcp_call(app, "tool__hello")
  expect_true(any(grepl(
    sprintf("ran on %s (last used)", test_handle("alpha", alpha)),
    res$texts, fixed = TRUE
  )))
})

test_that("a module-qualified tool runs in its module even when another is pinned", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  # beta loads, with its own `hello` that has different arguments
  unlink(file.path(root, "modules", "beta", "R", "broken.R"))
  writeLines(c(
    "hello <- ellmer::tool(",
    "  function(times = 1) 'hi',",
    "  name = 'hello',",
    "  description = 'Say hi several times',",
    "  arguments = list(times = ellmer::type_integer('How many times'))",
    ")"
  ), file.path(root, "modules", "beta", "R", "hello.R"))
  app <- mcp_test_app()
  fake_module_session("alpha", "tool__hello", pinned = TRUE)
  beta <- fake_module_session("beta", "tool__hello")

  res <- suppressWarnings(mcp_call(app, "tool__beta__hello"))
  expect_false(res$isError)
  expect_true(any(grepl(
    sprintf("ran on %s (most recently opened)", test_handle("beta", beta)),
    res$texts, fixed = TRUE
  )))
})

test_that("shidashi_sessions shows the app's welcome text and no paths", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  app <- mcp_test_app()
  sessions_text <- function() {
    res <- mcp_call(app, "shidashi_sessions")
    res$texts[[1]]
  }

  text <- sessions_text()
  expect_identical(names(jsonlite::fromJSON(text)$app), "app_id")
  expect_false(grepl(root, text, fixed = TRUE))

  writeLines(c("welcome: |", "  Mini app used by the tests."),
             file.path(root, "agents", "tool-schema.yaml"))
  info <- jsonlite::fromJSON(sessions_text())
  expect_match(info$app$welcome, "Mini app used by the tests.", fixed = TRUE)
})

test_that("agents are told to stay in the default module", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  instructions <- mcp_body(app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "initialize", params = list()
  ))))$result$instructions
  expect_match(instructions, "default module")
  expect_match(instructions, "do not reuse a handle", ignore.case = TRUE)

  tools <- mcp_body(app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/list"
  ))))$result$tools
  hello <- Filter(function(t) identical(t$name, "tool__hello"), tools)[[1]]
  expect_match(hello$inputSchema$properties[["_module"]]$description,
               "usually leave it out")
})

test_that("shidashi_tools lists the app's tools with their schemas", {
  app_env <- local_mcp_app()
  use_template_root(make_mini_template())
  app <- mcp_test_app()

  listed <- mcp_body(app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/list"
  ))))$result$tools
  listed_names <- vapply(listed, `[[`, "", "name")
  expect_true("shidashi_tools" %in% listed_names)

  res <- mcp_call(app, "shidashi_tools")
  expect_false(res$isError)
  app_tools <- jsonlite::fromJSON(res$texts[[1]], simplifyVector = FALSE)
  app_names <- vapply(app_tools, `[[`, "", "name")
  expect_identical(app_names, setdiff(listed_names, c(
    "shidashi_sessions", "shidashi_tools", "shidashi_call"
  )))
  hello <- listed[[match("tool__hello", listed_names)]]
  expect_identical(app_tools[[match("tool__hello", app_names)]], hello)
})

test_that("mcp_call_active() is on only while an MCP tool call runs", {
  expect_false(mcp_call_active())
  mcp_call_active(TRUE)
  expect_true(mcp_call_active())
  mcp_call_active(FALSE)
  expect_false(mcp_call_active())
})
