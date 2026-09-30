# The `switch_module` meta tool shows a module in the user's dashboard.
# Fake pages stand in for the browser: a test records what the tool sends
# to a page, answers the request as the dashboard JavaScript does, and
# reports focus as a module page does once the user sees it.

# The mini template, plus `delta`, which is hidden from the sidebar
use_switch_template <- function() {
  root <- make_mini_template()
  cat("  delta:\n    label: Delta\n    hidden: yes\n",
      file = file.path(root, "modules.yaml"), append = TRUE)
  use_template_root(root)
}

# A module page as the dashboard opens it: its session is scoped to the
# module, so its inputs carry the module prefix
fake_module_page <- function(module_id, focused_at = NULL) {
  session <- shiny::MockShinySession$new()
  token <- register_session(session$makeScope(module_id))
  set_activity(token, focused_at = focused_at)
  token
}

# The browser side of a page: records the custom messages the page's
# session sends
fake_browser <- function(token) {
  session <- get_session_entry(token)$shiny_session
  browser <- new.env(parent = emptyenv())
  browser$session <- session
  browser$messages <- list()
  root <- session$rootScope()
  root$sendCustomMessage <- function(type, message) {
    browser$messages[[length(browser$messages) + 1L]] <-
      c(list(type = type), message)
    invisible()
  }
  browser
}

# Answer the page's last request, as the dashboard JavaScript does
answer <- function(browser, status) {
  request <- browser$messages[[length(browser$messages)]]
  inputs <- structure(
    list(list(request_id = request$request_id, status = status)),
    names = request$input_id
  )
  do.call(browser$session$rootScope()$setInputs, inputs)
}

# A page the dashboard shows reports that the user sees it
report_focus <- function(token) {
  set_activity(token, focused_at = Sys.time())
}

set_url <- function(token, url) {
  registry <- globals_session_registry()
  entry <- registry$get(token)
  entry$url <- url
  registry$set(token, entry)
  invisible(token)
}

result_text <- function(res) {
  paste(vapply(res$content, `[[`, "", "text"), collapse = "\n")
}

test_that("switch_module is refused while any module is pinned, even the target", {
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello", pinned = TRUE)
  beta <- fake_module_session("beta", "tool__hello", focused_at = Sys.time())
  browser_alpha <- fake_browser(alpha)
  browser_beta <- fake_browser(beta)

  for (target in c("gamma", "alpha")) {
    res <- mcp_tool_switch_module(list(module_id = target))
    expect_true(res$isError, info = target)
    expect_match(result_text(res), "pinned `alpha` (Alpha)", fixed = TRUE,
                 info = target)
  }
  expect_length(browser_alpha$messages, 0)
  expect_length(browser_beta$messages, 0)
})

test_that("modules that are not in the sidebar are refused, with the sidebar's list", {
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello")
  browser <- fake_browser(alpha)

  for (arguments in list(list(module_id = "nope"), list(module_id = "delta"),
                         list())) {
    res <- mcp_tool_switch_module(arguments)
    expect_true(res$isError)
    text <- result_text(res)
    expect_match(text, "`alpha` (Alpha), `beta` (Beta), `gamma` (Gamma)",
                 fixed = TRUE)
    expect_false(grepl("(Delta)", text, fixed = TRUE))
  }
  expect_length(browser$messages, 0)
})

test_that("the request goes to the module page the user used last", {
  app_env <- local_mcp_app()
  use_switch_template()
  now <- Sys.time()
  alpha <- fake_module_page("alpha", focused_at = now - 10)
  gamma <- fake_module_page("gamma", focused_at = now - 60)
  browser_alpha <- fake_browser(alpha)
  browser_gamma <- fake_browser(gamma)

  p <- mcp_tool_switch_module(list(module_id = "beta", auto_new = FALSE))
  expect_true(promises::is.promise(p))
  expect_length(browser_gamma$messages, 0)
  expect_length(browser_alpha$messages, 1)
  request <- browser_alpha$messages[[1]]
  expect_identical(request$type, "shidashi.switch_module")
  expect_identical(request$module_id, "beta")
  expect_identical(request$auto_new, FALSE)
  expect_identical(request$input_id, "alpha-@shidashi_switch_module@")
  expect_true(is.character(request$request_id) && nzchar(request$request_id))

  answer(browser_alpha, "not_open")
  res <- wait_for_promise(p)
  expect_true(res$isError)
  expect_match(result_text(res), "`beta` (Beta) is not open", fixed = TRUE)
  expect_match(result_text(res), "auto_new", fixed = TRUE)
})

test_that("with no module page open, the request goes to the newest dashboard page", {
  app_env <- local_mcp_app()
  use_switch_template()
  now <- Sys.time()
  old_shell <- fake_module_session("", registered_at = now - 60)
  new_shell <- fake_module_session("", registered_at = now - 5)
  # a module page whose module has not registered yet is no dashboard
  loading <- set_url(fake_module_session("", registered_at = now - 1),
                     "?module=gamma&shared_id=abc")
  browser_old <- fake_browser(old_shell)
  browser_new <- fake_browser(new_shell)
  browser_loading <- fake_browser(loading)

  # a handle names its module
  p <- mcp_tool_switch_module(list(module_id = "beta@1a2b3c"))
  expect_length(browser_old$messages, 0)
  expect_length(browser_loading$messages, 0)
  expect_length(browser_new$messages, 1)
  request <- browser_new$messages[[1]]
  expect_identical(request$module_id, "beta")
  expect_identical(request$auto_new, TRUE)

  answer(browser_new, "opened")
  beta <- fake_module_session("beta", "tool__hello", focused_at = Sys.time())
  res <- wait_for_promise(p)
  expect_false(res$isError)
  text <- result_text(res)
  expect_match(text, "Opened `beta` (Beta) in a new tab; it has loaded.",
               fixed = TRUE)
  expect_match(text, sprintf("Tool calls now run there (`%s`).",
                             test_handle("beta", beta)), fixed = TRUE)
})

test_that("with no page open at all, switch_module says so", {
  app_env <- local_mcp_app()
  use_switch_template()
  res <- mcp_tool_switch_module(list(module_id = "beta"))
  expect_true(res$isError)
  expect_match(result_text(res), "No dashboard page is open")
})

test_that("switching to an open module waits until its page reports back", {
  app_env <- local_mcp_app()
  use_switch_template()
  now <- Sys.time()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = now - 10)
  gamma <- fake_module_session("gamma", "tool__hello", focused_at = now - 60)
  browser <- fake_browser(alpha)

  p <- mcp_tool_switch_module(list(module_id = "gamma"))
  answer(browser, "activated")
  state <- track_promise(p)
  deadline <- Sys.time() + 0.6
  while (Sys.time() < deadline) {
    later::run_now(0.05)
  }
  expect_false(state$done)

  report_focus(gamma)
  res <- wait_for_promise(p)
  expect_false(res$isError)
  text <- result_text(res)
  expect_match(text, "Switched to `gamma` (Gamma): its open tab is in front.",
               fixed = TRUE)
  expect_match(text, sprintf("Tool calls now run there (`%s`).",
                             test_handle("gamma", gamma)), fixed = TRUE)
})

test_that("answers that change nothing come back as errors", {
  cases <- c(
    no_dashboard = "(module `alpha`) is not inside a dashboard",
    not_found    = "no sidebar link for `beta`",
    something    = "Unexpected answer"
  )
  for (status in names(cases)) {
    app_env <- local_mcp_app()
    use_switch_template()
    alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
    browser <- fake_browser(alpha)

    p <- mcp_tool_switch_module(list(module_id = "beta"))
    answer(browser, status)
    res <- wait_for_promise(p)
    expect_true(res$isError, info = status)
    expect_match(result_text(res), cases[[status]], fixed = TRUE,
                 info = status)
  }
})

test_that("switch_module gives up when the browser does not answer", {
  old <- options(shidashi.switch_module_timeout = 0.3)
  on.exit(options(old), add = TRUE)
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
  fake_browser(alpha)

  res <- wait_for_promise(mcp_tool_switch_module(list(module_id = "beta")))
  expect_true(res$isError)
  expect_match(result_text(res), "did not answer within 0.3 s", fixed = TRUE)
})

test_that("the answer to an earlier request is not taken for a new one", {
  old <- options(shidashi.switch_module_timeout = 0.3)
  on.exit(options(old), add = TRUE)
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
  browser <- fake_browser(alpha)

  first <- mcp_tool_switch_module(list(module_id = "beta", auto_new = FALSE))
  answer(browser, "not_open")
  expect_true(wait_for_promise(first)$isError)

  # the page's input still holds the first answer
  res <- wait_for_promise(mcp_tool_switch_module(list(module_id = "beta")))
  expect_true(res$isError)
  expect_match(result_text(res), "did not answer", fixed = TRUE)
})

test_that("a module that does not report back in time is still shown, with a note", {
  old <- options(shidashi.switch_module_wait = 0.3)
  on.exit(options(old), add = TRUE)
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
  browser <- fake_browser(alpha)

  p <- mcp_tool_switch_module(list(module_id = "beta"))
  answer(browser, "opened")
  res <- wait_for_promise(p)
  expect_false(res$isError)
  text <- result_text(res)
  expect_match(text, paste(
    "Opened `beta` (Beta) in a new tab, but it has not finished loading",
    "within 0.3 s."
  ), fixed = TRUE)
  expect_match(text, "wait until `beta` is the `default_module`", fixed = TRUE)
})

test_that("a module without agent tools is shown, and tool calls stay where they were", {
  app_env <- local_mcp_app()
  use_switch_template()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = Sys.time())
  browser <- fake_browser(alpha)

  p <- mcp_tool_switch_module(list(module_id = "gamma"))
  answer(browser, "opened")
  fake_module_session("gamma", focused_at = Sys.time())
  res <- wait_for_promise(p)
  expect_false(res$isError)
  text <- result_text(res)
  expect_match(text, paste(
    "It has no agent tools, so tool calls keep running in the module used",
    "before."
  ), fixed = TRUE)
  expect_false(grepl("Tool calls now run there", text, fixed = TRUE))
})

test_that("a connection limited to one module can only switch to that module", {
  app_env <- local_mcp_app()
  use_switch_template()
  now <- Sys.time()
  alpha <- fake_module_session("alpha", "tool__hello", focused_at = now - 60)
  beta <- fake_module_session("beta", "tool__hello", focused_at = now - 5)
  browser_alpha <- fake_browser(alpha)
  browser_beta <- fake_browser(beta)

  res <- mcp_tool_switch_module(list(module_id = "beta"),
                                scope = list(module = "alpha"))
  expect_true(res$isError)
  expect_match(result_text(res), "limited to module `alpha`", fixed = TRUE)

  # its own module: the request goes to that module's page
  p <- mcp_tool_switch_module(list(module_id = "alpha"),
                              scope = list(module = test_handle("alpha", alpha)))
  expect_length(browser_beta$messages, 0)
  expect_length(browser_alpha$messages, 1)
  answer(browser_alpha, "activated")
  report_focus(alpha)
  expect_false(wait_for_promise(p)$isError)
})

test_that("switch_module is listed, and tools/call always answers with a result", {
  app_env <- local_mcp_app()
  use_switch_template()
  app <- mcp_test_app()
  listed <- mcp_body(app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 1, method = "tools/list"
  ))))$result$tools
  schema <- listed[[match("switch_module", vapply(listed, `[[`, "", "name"))]]
  expect_identical(schema$inputSchema$required, list("module_id"))

  alpha <- fake_module_session("alpha", "tool__hello",
                               focused_at = Sys.time() - 5)
  browser <- fake_browser(alpha)
  call_switch <- function(arguments) {
    app$httpHandler(mcp_request(list(
      jsonrpc = "2.0", id = 7, method = "tools/call",
      params = list(name = "switch_module", arguments = arguments)
    )))
  }

  # an error found before asking the browser
  body <- mcp_body(call_switch(list(module_id = "nope")))
  expect_null(body$error)
  expect_true(body$result$isError)

  # an error in the browser's answer is a result too, not a JSON-RPC error
  res <- call_switch(list(module_id = "beta", auto_new = FALSE))
  expect_true(promises::is.promise(res))
  answer(browser, "not_open")
  body <- mcp_body(wait_for_promise(res))
  expect_identical(body$id, 7L)
  expect_null(body$error)
  expect_true(body$result$isError)

  res <- call_switch(list(module_id = "alpha"))
  answer(browser, "activated")
  report_focus(alpha)
  body <- mcp_body(wait_for_promise(res))
  expect_false(body$result$isError)
  expect_match(body$result$content[[1]]$text, "Switched to `alpha` (Alpha)",
               fixed = TRUE)
})
