# No `.register_input` registry is in scope here, so `register_input()`
# only evaluates `expr` and adds the hover tip
title_of <- function(ui) {
  htmltools::tagGetAttribute(ui, "title")
}

test_that("as_tooltip returns the first sentence of the description", {
  expect_equal(as_tooltip("Plot threshold. Agents set it first."), "Plot threshold.")
  expect_equal(as_tooltip("Is it on? Read by `run_analysis`."), "Is it on?")
  expect_equal(as_tooltip("No sentence end"), "No sentence end")
  expect_equal(as_tooltip("Ends with a dot."), "Ends with a dot.")
})

test_that("as_tooltip does not end a sentence at abbreviations or decimals", {
  expect_equal(
    as_tooltip("Trials, e.g. '3,17'. Agents may set it."),
    "Trials, e.g. '3,17'."
  )
  expect_equal(
    as_tooltip("Mode, i.e. volume or surface, etc. and more. Second."),
    "Mode, i.e. volume or surface, etc. and more."
  )
  expect_equal(as_tooltip("Plot threshold, e.g. 0.5. Agents set it first."),
               "Plot threshold, e.g. 0.5.")
})

test_that("as_tooltip collapses vectors and white space", {
  expect_equal(as_tooltip(c("First part", "  of the\nsentence.", "Second.")),
               "First part of the sentence.")
  expect_equal(as_tooltip(""), "")
  expect_equal(as_tooltip("   "), "")
  expect_equal(as_tooltip(NULL), "")
})

test_that("register_input adds the first sentence to an input container", {
  ui <- register_input(
    shiny::selectInput("sel", "Select", choices = c("a", "b")),
    inputId = "sel",
    update = "shiny::updateSelectInput(value=selected)",
    description = c("Which letter to use.", "Agents run script `x` instead.")
  )
  expect_s3_class(ui, "shiny.tag")
  expect_equal(title_of(ui), "Which letter to use.")
})

test_that("register_input adds the hover tip to buttons and links", {
  button <- register_input(
    shiny::actionButton("btn", "Go"),
    inputId = "btn",
    update = "shiny::updateActionButton",
    description = "Runs the analysis. Agents use the script."
  )
  expect_equal(button$name, "button")
  expect_equal(title_of(button), "Runs the analysis.")

  link <- register_input(
    shiny::actionLink("lnk", "Go"),
    inputId = "lnk",
    update = "shiny::updateActionLink",
    tooltip = "Opens the details"
  )
  expect_equal(title_of(link), "Opens the details")
})

test_that("tooltip = NULL and blank descriptions add no hover tip", {
  no_tip <- register_input(
    shiny::textInput("txt", "Text"),
    inputId = "txt",
    update = "shiny::updateTextInput",
    description = "A text input.",
    tooltip = NULL
  )
  expect_null(title_of(no_tip))

  blank <- register_input(
    shiny::textInput("txt", "Text"),
    inputId = "txt",
    update = "shiny::updateTextInput"
  )
  expect_null(title_of(blank))
  expect_false(grepl("title=", as.character(blank), fixed = TRUE))
})

test_that("register_input keeps an existing title", {
  ui <- register_input(
    shiny::actionButton("btn", "Go", title = "Mine"),
    inputId = "btn",
    update = "shiny::updateActionButton",
    description = "Runs the analysis."
  )
  expect_equal(title_of(ui), "Mine")
})

test_that("register_input leaves elements that are not inputs unchanged", {
  card <- htmltools::div(class = "card", htmltools::div(class = "card-body"))
  ui <- register_input(
    card,
    inputId = "tabset",
    update = "shidashi::card_tabset_activate(value=title)",
    description = "Active tab of the card.",
    tooltip = "Even an explicit hover tip is not added"
  )
  expect_identical(ui, card)
})

test_that("register_input adds the hover tip to the only tag of a tag list", {
  ui <- register_input(
    htmltools::tagList(
      shiny::actionButton("btn", "Go"),
      htmltools::htmlDependency("dep", "1.0", src = c(href = "dep"))
    ),
    inputId = "btn",
    update = "shiny::updateActionButton",
    description = "Runs the analysis."
  )
  expect_s3_class(ui, "shiny.tag.list")
  expect_equal(title_of(ui[[1]]), "Runs the analysis.")

  # Several tags: no single input to describe
  two <- register_input(
    htmltools::tagList(shiny::actionButton("a", "A"), shiny::actionButton("b", "B")),
    inputId = "a",
    update = "shiny::updateActionButton",
    description = "Runs the analysis."
  )
  expect_null(title_of(two[[1]]))
  expect_null(title_of(two[[2]]))
})
