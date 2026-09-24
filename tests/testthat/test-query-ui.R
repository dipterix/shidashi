# Run the event loop until a promise settles; return its value or throw
wait_for_promise <- function(p, timeout = 5) {
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
  deadline <- Sys.time() + timeout
  while (!state$done && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  if (!state$done) stop("the promise did not settle")
  if (!is.null(state$error)) stop(state$error)
  state$value
}

query_tools <- function(session) {
  shiny::withReactiveDomain(session, {
    mcp_wrapper_input_output()$tool_generator(session)
  })
}

test_that("shiny_query_ui returns the browser's answer in one call", {
  local_mocked_bindings(rand_string = function(...) "req1")
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)
  expect_false("shiny_query_ui_result" %in% names(tools))

  p <- tools$shiny_query_ui(css_selector = "#plot")
  expect_true(promises::is.promise(p))   # R is not blocked

  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "<b>hi</b>"
  ))
  expect_identical(wait_for_promise(p), "<b>hi</b>")
})

test_that("shiny_query_ui returns images, with the note", {
  local_mocked_bindings(rand_string = function(...) "req1")
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)

  p <- tools$shiny_query_ui(css_selector = "canvas")
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", image_data = "iVBORw0KGgo=", image_type = "image/png",
    note = "a canvas"
  ))
  result <- wait_for_promise(p)
  expect_true(inherits(result[[1]], "ellmer::ContentImageInline"))
  expect_identical(result[[2]]@text, "a canvas")
})

test_that("shiny_query_ui gives up when the browser does not answer", {
  local_mocked_bindings(rand_string = function(...) "req1")
  old <- options(shidashi.query_ui_timeout = 0.3)
  on.exit(options(old), add = TRUE)
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)

  p <- tools$shiny_query_ui(css_selector = "#nothing")
  expect_error(wait_for_promise(p), "did not answer")

  # a reply that arrives after the timeout is ignored
  expect_no_error(session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "late"
  )))
})

test_that("an MCP call to shiny_query_ui is held until the browser answers", {
  local_mocked_bindings(rand_string = function(...) "req1")
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  cat("- name: shiny_query_ui\n  category:\n  - exploratory\n  enabled: yes\n",
      file = file.path(root, "modules", "alpha", "agents.yaml"), append = TRUE)
  app <- mcp_test_app()
  token <- open_real_module(root, "alpha")
  session <- get_session_entry(token)$shiny_session$rootScope()

  res <- app$httpHandler(mcp_request(list(
    jsonrpc = "2.0", id = 5, method = "tools/call",
    params = list(name = "tool__shiny_query_ui",
                  arguments = list(css_selector = "body"))
  )))
  expect_true(promises::is.promise(res))

  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "<p>page</p>"
  ))
  body <- mcp_body(wait_for_promise(res))
  expect_identical(body$id, 5L)
  expect_false(body$result$isError)
  expect_identical(body$result$content[[1]]$text, "<p>page</p>")
})

test_that("mcp_trim_html shortens data URIs and drops script bodies", {
  image <- paste0('<img src="data:image/png;base64,', strrep("A", 5000), '">')
  trimmed <- mcp_trim_html(image, max_chars = 10000)
  expect_match(trimmed, "data:image/png;base64,...(5000 characters omitted)",
               fixed = TRUE)
  expect_lt(nchar(trimmed), 100)

  trimmed <- mcp_trim_html(
    "<div><script>var x = 1; alert(x);</script><style>p { color: red; }</style></div>",
    max_chars = 10000
  )
  expect_identical(trimmed,
                   "<div><script>...(omitted)</script><style>...(omitted)</style></div>")
})

test_that("mcp_trim_html removes whitespace between tags", {
  expect_identical(mcp_trim_html("<div>\n   <p>a   b</p>\n</div>", 10000),
                   "<div><p>a b</p></div>")
})

test_that("mcp_trim_html cuts long HTML at a tag and says so", {
  html <- paste(rep("<p>0123456789</p>", 100), collapse = "")   # 1700 chars
  trimmed <- mcp_trim_html(html, max_chars = 500)
  body <- trimws(sub("<!--.*$", "", trimmed))
  expect_lte(nchar(body), 500)
  expect_match(body, ">$")   # never cut inside a tag
  expect_match(trimmed, "trimmed: showing \\d+ of 1700 characters")

  expect_identical(mcp_trim_html("<b>short</b>", 500), "<b>short</b>")
  expect_identical(mcp_trim_html("", 500), "")
})

test_that("transform_image = FALSE returns HTML even when an image comes back", {
  local_mocked_bindings(rand_string = function(...) "req1")
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)

  p <- tools$shiny_query_ui(css_selector = "#plot", transform_image = FALSE)
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "<img alt=\"plot\">",
    image_data = "iVBORw0KGgo=", image_type = "image/png"
  ))
  expect_identical(wait_for_promise(p), "<img alt=\"plot\">")
})

test_that("shiny_query_ui trims long HTML and long notes", {
  local_mocked_bindings(rand_string = function(...) "req1")
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)

  p <- tools$shiny_query_ui(css_selector = "body", max_chars = 200)
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1",
    html = paste(rep("<p>0123456789</p>", 100), collapse = ""),
    note = paste0("<div class=\"", strrep("x", 2000), "\">")
  ))
  result <- wait_for_promise(p)
  expect_match(result, "trimmed: showing \\d+ of 1700 characters")
  expect_lt(nchar(result), 200 + 500 + 300)
})

test_that("a selector that matches nothing is a tool error", {
  local_mocked_bindings(rand_string = function(...) "req1")
  session <- shiny::MockShinySession$new()
  tools <- query_tools(session)

  p <- tools$shiny_query_ui(css_selector = "#nothing")
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "not_found", html = "",
    note = "No element matched selector: '#nothing'"
  ))
  expect_error(wait_for_promise(p), "No element matched selector")
})
