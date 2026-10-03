# `colormapSelectInput()`: a single-select whose value never leaves the choices
# while there are choices (see the roxygen `@details`).

test_colormaps <- list(
  A = c("#000000", "#ffffff"),
  B = c("#ff0000", "#00ff00")
)

selected_option <- function(html) {
  m <- regmatches(html, regexpr('<option value="[^"]*" selected', html))
  if (!length(m)) return(NA_character_)
  sub('<option value="([^"]*)" selected', "\\1", m)
}

test_that("colormapSelectInput cannot be emptied by the keyboard or by an empty update", {
  html <- as.character(colormapSelectInput("cm", "L", colormaps = test_colormaps))
  # selectize hooks: `onDelete` vetoes Backspace/Delete, `onChange` restores a
  # value that an update emptied
  expect_match(html, "onDelete", fixed = TRUE)
  expect_match(html, "onInitialize", fixed = TRUE)
  expect_match(html, "onChange", fixed = TRUE)
})

test_that("colormapSelectInput keeps `selected` within the choices", {
  # a valid name is honoured
  html <- as.character(colormapSelectInput("cm", "L", test_colormaps, selected = "B"))
  expect_identical(selected_option(html), "B")

  # an unknown name falls back to the first colormap
  html <- as.character(colormapSelectInput("cm", "L", test_colormaps, selected = "foo"))
  expect_identical(selected_option(html), "A")

  # so does an empty selection
  html <- as.character(colormapSelectInput("cm", "L", test_colormaps, selected = character(0)))
  expect_identical(selected_option(html), "A")
  html <- as.character(colormapSelectInput("cm", "L", test_colormaps, selected = ""))
  expect_identical(selected_option(html), "A")
})

test_that("colormapSelectInput renders an empty selector without colormaps", {
  html <- as.character(colormapSelectInput("cm", "L", colormaps = list()))
  expect_false(grepl("<option", html, fixed = TRUE))
})
