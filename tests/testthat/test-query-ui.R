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

# ---- render_hidden_output() -------------------------------------------------

# A session that keeps output options and flush callbacks in `state`;
# `state$flush()` runs the flush callbacks once, like shiny does.
fake_output_session <- function(options = list(plot = list())) {
  state <- new.env(parent = emptyenv())
  state$options <- options
  state$callbacks <- list()
  state$flush_requests <- 0L
  state$flush <- function() {
    callbacks <- state$callbacks
    state$callbacks <- list()
    for (callback in callbacks) callback()
  }
  impl <- list(outputOptions = function(name, ...) {
    if (!name %in% names(state$options)) {
      stop(name, " is not in list of output objects")
    }
    new_options <- list(...)
    if (!length(new_options)) {
      return(state$options[[name]])
    }
    state$options[[name]][names(new_options)] <- new_options
    invisible()
  })
  session <- list(
    output = structure(list(impl = impl, ns = function(id) id),
                       class = "shinyoutput"),
    onFlushed = function(callback, once = TRUE) {
      key <- sprintf("cb%d", length(state$callbacks) + 1L)
      state$callbacks[[key]] <- callback
      function() state$callbacks[[key]] <- NULL
    },
    requestFlush = function() state$flush_requests <- state$flush_requests + 1L,
    isClosed = function() FALSE
  )
  list(session = session, state = state)
}

test_that("render_hidden_output renders a hidden output until the next flush", {
  fake <- fake_output_session()
  render_hidden_output("plot", session = fake$session)
  expect_false(fake$state$options$plot$suspendWhenHidden)
  expect_identical(fake$state$flush_requests, 1L)

  fake$state$flush()
  expect_true(fake$state$options$plot$suspendWhenHidden)
})

test_that("render_hidden_output keeps an output that already renders when hidden", {
  fake <- fake_output_session(list(plot = list(suspendWhenHidden = FALSE)))
  restore <- render_hidden_output("plot", session = fake$session)
  fake$state$flush()
  restore()
  expect_false(fake$state$options$plot$suspendWhenHidden)
  expect_identical(fake$state$flush_requests, 1L)
})

test_that("render_hidden_output(once = FALSE) keeps rendering until restored", {
  fake <- fake_output_session()
  restore <- render_hidden_output("plot", session = fake$session, once = FALSE)
  fake$state$flush()
  expect_false(fake$state$options$plot$suspendWhenHidden)

  restore()
  expect_true(fake$state$options$plot$suspendWhenHidden)
})

test_that("restoring early cancels the restore on the next flush", {
  fake <- fake_output_session()
  restore <- render_hidden_output("plot", session = fake$session)
  restore()
  expect_true(fake$state$options$plot$suspendWhenHidden)
  expect_length(fake$state$callbacks, 0)
})

test_that("render_hidden_output errors for an output the session lacks", {
  fake <- fake_output_session()
  expect_error(render_hidden_output("nothing", session = fake$session),
               "Output `nothing` is not defined in this session")
})

test_that("render_hidden_output does nothing in a mock session", {
  session <- shiny::MockShinySession$new()
  restore <- render_hidden_output("plot", session = session)
  expect_no_error(restore())
})

# ---- shiny_output_result ----------------------------------------------------

# Tools for `session` with `outputIds` registered; returns the tools and a
# record of the custom messages sent to the browser
output_tools <- function(session, outputIds = "summary") {
  helpers <- mcp_wrapper_input_output()
  for (outputId in outputIds) {
    helpers$input_helpers$register_output_specification(
      quote(shiny::renderText("x")), outputId = outputId, quoted = TRUE
    )
  }
  sent <- new.env(parent = emptyenv())
  sent$messages <- list()
  session$sendCustomMessage <- function(type, message) {
    sent$messages[[length(sent$messages) + 1L]] <- c(list(type = type), message)
    invisible()
  }
  tools <- shiny::withReactiveDomain(session, helpers$tool_generator(session))
  list(tools = tools, sent = sent)
}

# Run `later` until `n` custom messages were sent: a query goes to the
# browser after a short pause (option `shidashi.query_ui_delay`)
wait_sent <- function(sent, n = 1L, timeout = 5) {
  deadline <- Sys.time() + timeout
  while (length(sent$messages) < n && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  expect_length(sent$messages, n)
}

local_request_ids <- function(ids = c("req1", "req2"), env = parent.frame()) {
  i <- 0L
  local_mocked_bindings(rand_string = function(...) {
    i <<- i + 1L
    ids[[i]]
  }, .env = env)
}

test_that("a query goes to the browser after a short pause", {
  local_mocked_bindings(rand_string = function(...) "req1")
  old <- options(shidashi.query_ui_delay = 0.2)
  on.exit(options(old), add = TRUE)
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_query_ui(css_selector = "#plot")
  # a change sent at about the same time reaches the page first
  later::run_now()
  expect_length(x$sent$messages, 0)
  wait_sent(x$sent, 1)
  expect_identical(x$sent$messages[[1]]$type, "shidashi.query_ui")
  expect_identical(x$sent$messages[[1]]$request_id, "req1")

  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "<b>hi</b>"
  ))
  expect_identical(wait_for_promise(p), "<b>hi</b>")
})

test_that("a query that timed out during the pause is not sent", {
  local_mocked_bindings(rand_string = function(...) "req1")
  old <- options(shidashi.query_ui_delay = 0.3, shidashi.query_ui_timeout = 0.1)
  on.exit(options(old), add = TRUE)
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_query_ui(css_selector = "#plot")
  expect_error(wait_for_promise(p), "did not answer")
  Sys.sleep(0.3)
  later::run_now(0.1)
  expect_length(x$sent$messages, 0)
})

test_that("shiny_output_result lists the registered IDs for an unknown ID", {
  session <- shiny::MockShinySession$new()
  x <- output_tools(session, c("summary", "plot"))
  err <- tryCatch(x$tools$shiny_output_result(outputId = "nothing"),
                  error = conditionMessage)
  expect_match(err, "summary")
  expect_match(err, "plot")
  expect_length(x$sent$messages, 0)
})

test_that("shiny_output_result says when a module registers no outputs", {
  session <- shiny::MockShinySession$new()
  x <- output_tools(session, character())
  expect_error(x$tools$shiny_output_result(outputId = "nothing"),
               "registers no outputs")
})

test_that("shiny_output_result reads the output only after it is flushed", {
  local_request_ids()
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_output_result(outputId = "summary")
  expect_true(promises::is.promise(p))
  wait_sent(x$sent, 1)
  expect_identical(x$sent$messages[[1]]$type, "shidashi.prepare_output")
  expect_identical(x$sent$messages[[1]]$selector,
                   paste0("#", session$ns("summary")))

  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "prepared"
  ))
  later::run_now()
  # the value is not sent yet, so asking now could read a stale element
  expect_length(x$sent$messages, 1)

  session$flushReact()
  expect_length(x$sent$messages, 2)
  query <- x$sent$messages[[2]]
  expect_identical(query$type, "shidashi.query_ui")
  expect_identical(query$request_id, "req2")
  expect_gt(query$wait_ms, 0)
  # the browser's note then says the output was just rendered
  expect_true(query$rendered)

  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req2", html = "<pre>x</pre>"
  ))
  expect_identical(wait_for_promise(p), "<pre>x</pre>")
})

test_that("shiny_output_result stops when the page has no such element", {
  local_request_ids()
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_output_result(outputId = "summary")
  wait_sent(x$sent, 1)
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "not_found",
    note = "No element matched selector: '#summary'"
  ))
  expect_error(wait_for_promise(p), "No element matched selector")
  session$flushReact()
  expect_length(x$sent$messages, 1)
})

test_that("shiny_output_result says when a fallback size was used", {
  local_request_ids()
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_output_result(outputId = "summary")
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "prepared",
    fallback_size = list(width = 640, height = 400)
  ))
  later::run_now()
  session$flushReact()
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req2", html = "<img>"
  ))
  expect_match(wait_for_promise(p), "fallback size of 640x400")
})

test_that("shiny_output_result gives up in time and restores the option", {
  local_request_ids()
  old <- options(shidashi.output_result_timeout = 0.3)
  on.exit(options(old), add = TRUE)
  restored <- FALSE
  local_mocked_bindings(render_hidden_output = function(...) {
    function() restored <<- TRUE
  })
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_output_result(outputId = "summary")
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "prepared"
  ))
  # no flush: the session is busy, so the output never arrives
  expect_error(wait_for_promise(p), "did not finish rendering")
  expect_true(restored)
})

# Runs `shiny_output_result` for `summary`, stored with `renderer` in the
# session registry, until the browser answers with `answer`
output_result_with <- function(renderer, answer = list(html = "<p>page 1</p>"),
                               max_chars = NULL, env = parent.frame()) {
  renderers <- new_fastmap()
  renderers$set("summary", renderer)
  local_mocked_bindings(
    get_session_entry = function(token) list(output_renderers = renderers),
    .env = env
  )
  local_request_ids(env = env)
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_output_result(outputId = "summary", max_chars = max_chars)
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", type = "prepared"
  ))
  later::run_now()
  session$flushReact()
  session$setInputs(`@shiny_query_ui_result@` = c(list(request_id = "req2"),
                                                   answer))
  wait_for_promise(p)
}

fake_widget_renderer <- function(render_expr) {
  list(render_expr = render_expr, render_env = globalenv(),
       download_type = "htmlwidget")
}

test_that("shiny_output_result adds a widget's full data", {
  result <- output_result_with(fake_widget_renderer(quote(structure(
    list(x = list(data = data.frame(a = 1:30))),
    class = c("mywidget", "htmlwidget")
  ))))
  expect_length(result, 2)
  expect_identical(result[[1]]@text, "<p>page 1</p>")
  data_text <- result[[2]]@text
  expect_match(data_text, "Full data of this widget")
  expect_match(data_text, "mywidget")
  expect_match(data_text, "30 +30")   # all rows, not one page
})

test_that("shiny_output_result adds a widget's data after its picture", {
  result <- output_result_with(
    fake_widget_renderer(quote(data.frame(a = 1:3))),
    answer = list(image_data = "iVBORw0KGgo=", image_type = "image/png")
  )
  expect_length(result, 2)
  expect_true(inherits(result[[1]], "ellmer::ContentImageInline"))
  expect_match(result[[2]]@text, "data.frame")
})

test_that("shiny_output_result still answers when the widget data fails", {
  result <- output_result_with(fake_widget_renderer(
    quote(shiny::validate(shiny::need(FALSE, "Build the table first")))
  ))
  expect_identical(result[[1]]@text, "<p>page 1</p>")
  expect_match(result[[2]]@text,
               "Could not get the data: Build the table first")
})

test_that("shiny_output_result trims long widget data at a line break", {
  result <- output_result_with(
    fake_widget_renderer(quote(data.frame(a = 1:500))),
    max_chars = 300
  )
  data_text <- result[[2]]@text
  expect_match(data_text, "trimmed: showing \\d+ of \\d+ characters")
  kept <- sub("^[^\n]*\n", "", sub("\n\\[shidashi\\] trimmed.*$", "", data_text))
  expect_lte(nchar(kept), 300)
  expect_match(kept, "[0-9]$")   # ends with a whole row
})

test_that("shiny_output_result adds what a data output downloads", {
  written_to <- NULL
  result <- output_result_with(list(
    download_type = "data", extension = "csv",
    download_function = function(con) {
      written_to <<- con
      utils::write.csv(data.frame(a = 1:3), con, row.names = FALSE)
    }
  ))
  expect_match(written_to, "\\.csv$")
  expect_false(file.exists(written_to))
  expect_identical(result[[1]]@text, "<p>page 1</p>")
  expect_match(result[[2]]@text, "as its download button saves it")
  expect_match(result[[2]]@text, "\"a\"\r?\n1\r?\n2\r?\n3")
})

test_that("shiny_output_result does not show binary downloads", {
  result <- output_result_with(list(
    download_type = "data",
    download_function = function(con) writeBin(as.raw(c(1, 0, 2)), con)
  ))
  expect_match(result[[2]]@text, "binary file of 3 bytes")
})

test_that("shiny_output_result adds nothing for other download types", {
  result <- output_result_with(list(
    download_type = "no-download", render_expr = quote(stop("not evaluated")),
    render_env = globalenv()
  ))
  expect_identical(result, "<p>page 1</p>")
})

test_that("shiny_query_ui points to shiny_output_result for an unshown element", {
  local_request_ids()
  session <- shiny::MockShinySession$new()
  x <- output_tools(session)

  p <- x$tools$shiny_query_ui(css_selector = "#summary")
  session$setInputs(`@shiny_query_ui_result@` = list(
    request_id = "req1", html = "", laid_out = FALSE,
    note = "The element is not shown on the page."
  ))
  expect_match(wait_for_promise(p), "shiny_output_result")
})
