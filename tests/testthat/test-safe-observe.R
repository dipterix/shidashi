test_that("an error in a safe observer is a warning, not a crash", {
  session <- shiny::MockShinySession$new()
  ran <- FALSE
  safe_observe({
    ran <<- TRUE
    stop("boom")
  }, domain = session, label = "test observer")

  expect_warning(session$flushReact(), "test observer failed: boom")
  expect_true(ran)
  expect_false(session$isClosed())
})

test_that("req() in a safe observer stays silent", {
  session <- shiny::MockShinySession$new()
  safe_observe({
    shiny::req(FALSE)
    stop("not reached")
  }, domain = session, label = "quiet observer")

  expect_no_warning(session$flushReact())
})

test_that("safe observers work with bindEvent", {
  session <- shiny::MockShinySession$new()
  seen <- c()
  shiny::bindEvent(
    safe_observe({
      seen <<- c(seen, session$input$x)
    }, domain = session),
    session$input$x
  )

  session$setInputs(x = 1)
  session$setInputs(x = 2)
  expect_identical(seen, c(1, 2))
})

test_that("safe observers accept quoted expressions", {
  session <- shiny::MockShinySession$new()
  env <- new.env()
  env$count <- 0
  # the body runs inside a function whose enclosure is `env`
  safe_observe(quote(count <<- count + 1), env = env, quoted = TRUE,
               domain = session)

  session$flushReact()
  expect_identical(env$count, 1)
})
