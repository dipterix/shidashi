# Input hints (what an agent asks the user, keeps, or leaves alone) and the
# session state that `shiny_input_info` reports next to the inputs

# Register text inputs `ids` with `hints` (NULL: no hint given)
register_text_inputs <- function(input_helpers, ids, hints = NULL) {
  for (ii in seq_along(ids)) {
    args <- list(
      expr = quote(shiny::textInput("x", "X")),
      inputId = ids[[ii]],
      update = "shiny::updateTextInput",
      description = paste("Input", ids[[ii]]),
      quoted = TRUE
    )
    if (length(hints) && !is.na(hints[[ii]])) {
      args$hint <- hints[[ii]]
    }
    do.call(input_helpers$register_input_specification, args)
  }
}

hint_tools <- function(session, ids, hints = NULL) {
  helpers <- mcp_wrapper_input_output()
  register_text_inputs(helpers$input_helpers, ids, hints)
  tools <- shiny::withReactiveDomain(session, helpers$tool_generator(session))
  list(helpers = helpers, tools = tools)
}

test_that("inputs carry a hint, `no_hint` unless one is given", {
  session <- shiny::MockShinySession$new()
  x <- hint_tools(session, c("project", "threshold"),
                  c("loader_mandatory", NA))

  info <- x$tools$shiny_input_info()
  expect_identical(info$project$hint, "loader_mandatory")
  expect_identical(info$threshold$hint, "no_hint")

  spec <- x$helpers$input_helpers$get_input_specification()
  expect_identical(spec$hint[match(c("project", "threshold"), spec$inputId)],
                   c("loader_mandatory", "no_hint"))
})

test_that("an unknown hint is an error", {
  helpers <- mcp_wrapper_input_output()
  expect_error(
    register_text_inputs(helpers$input_helpers, "x", "loader_maybe"),
    "hint"
  )
  # also without a registry in scope
  expect_error(
    register_input(shiny::textInput("x", "X"), inputId = "x",
                   update = "shiny::updateTextInput", hint = "bogus"),
    "hint"
  )
})

test_that("register_input passes the hint to the module's registry", {
  helpers <- mcp_wrapper_input_output()
  .register_input <- helpers$input_helpers$register_input_specification

  register_input(shiny::textInput("x", "X"), inputId = "x",
                 update = "shiny::updateTextInput", description = "An input",
                 hint = "analysis_optional")

  spec <- helpers$input_helpers$get_input_specification()
  expect_identical(spec$hint, "analysis_optional")
})

test_that("update_input_specification changes the hint", {
  helpers <- mcp_wrapper_input_output()
  register_text_inputs(helpers$input_helpers, "x")

  helpers$input_helpers$update_input_specification("x", hint = "loader_forbidden")
  expect_identical(helpers$input_helpers$get_input_specification()$hint,
                   "loader_forbidden")
  expect_error(
    helpers$input_helpers$update_input_specification("x", hint = "nope"),
    "hint"
  )
})

test_that("an empty input registry still has the hint column", {
  spec <- mcp_wrapper_input_output()$input_helpers$get_input_specification()
  expect_true("hint" %in% names(spec))
})

test_that("shiny_input_info lists only the hint classes asked for", {
  session <- shiny::MockShinySession$new()
  x <- hint_tools(
    session,
    c("project", "electrodes", "baseline", "color"),
    c("loader_mandatory", "loader_optional", "analysis_mandatory", NA)
  )

  loader <- x$tools$shiny_input_info(
    hints = c("loader_mandatory", "loader_optional")
  )
  expect_setequal(names(loader), c("project", "electrodes"))

  unhinted <- x$tools$shiny_input_info(hints = "no_hint")
  expect_identical(names(unhinted), "color")
})

test_that("shiny_input_info reports the state the app registers", {
  session <- shiny::MockShinySession$new()
  x <- hint_tools(session, "project", "loader_mandatory")
  opened <- shiny::reactiveVal(TRUE)

  register_input_state(
    "loader_opened",
    function() structure(opened(), timestamp = 123),
    description = "Whether the data loader is open",
    session = session
  )

  info <- x$tools$shiny_input_info()
  expect_identical(info[["@state"]]$loader_opened$value, TRUE)
  expect_identical(info[["@state"]]$loader_opened$description,
                   "Whether the data loader is open")
  expect_identical(info$project$hint, "loader_mandatory")

  opened(FALSE)
  info <- x$tools$shiny_input_info(inputIds = "project")
  expect_identical(info[["@state"]]$loader_opened$value, FALSE)
  expect_identical(names(info), c("project", "@state"))
})

test_that("a failing state getter does not break shiny_input_info", {
  session <- shiny::MockShinySession$new()
  x <- hint_tools(session, "project", "loader_mandatory")
  register_input_state("broken", function() stop("nope"), session = session)

  info <- x$tools$shiny_input_info()
  expect_null(info[["@state"]]$broken$value)
  expect_match(info[["@state"]]$broken$error, "nope")
  expect_identical(info$project$hint, "loader_mandatory")
})

test_that("shiny_input_info has no @state when the app registers none", {
  session <- shiny::MockShinySession$new()
  x <- hint_tools(session, "project", "loader_mandatory")
  expect_null(x$tools$shiny_input_info()[["@state"]])
})
