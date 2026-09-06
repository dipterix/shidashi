rendered <- function(...) {
  as.character(htmltools::renderTags(objectListInput(...))$html)
}

dependency_names <- function(...) {
  vapply(htmltools::renderTags(objectListInput(...))$dependencies,
         function(d) { d$name }, character(1L))
}

# Pulls the selectize configuration that shiny writes into the `<script>` tag
config <- function(...) {
  html <- rendered(...)
  json <- regmatches(html, regexpr("(?s)<script type=\"application/json\"[^>]*>.*?</script>",
                                   html, perl = TRUE))
  json <- sub("(?s)^<script[^>]*>(.*?)</script>$", "\\1", json, perl = TRUE)
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}

test_that("objectListInput renders a multiple selectize input", {
  html <- rendered("objects", "Objects",
                   choices = c("Label A" = "a", "Label B" = "b"))

  expect_true(grepl("shidashi-object-list", html, fixed = TRUE))
  expect_true(grepl('multiple="multiple"', html, fixed = TRUE))
  expect_true(grepl('<option value="a" selected>Label A</option>', html, fixed = TRUE))
  expect_true(grepl('<option value="b" selected>Label B</option>', html, fixed = TRUE))
})

test_that("all choices are selected unless `selected` says otherwise", {
  all_selected <- rendered("objects", choices = c("Label A" = "a", "Label B" = "b"))
  expect_equal(
    lengths(regmatches(all_selected, gregexpr("<option[^>]* selected>", all_selected))),
    2L
  )

  one_selected <- rendered("objects", choices = c("Label A" = "a", "Label B" = "b"),
                           selected = "b")
  expect_true(grepl('<option value="a">Label A</option>', one_selected, fixed = TRUE))
  expect_true(grepl('<option value="b" selected>Label B</option>', one_selected, fixed = TRUE))
})

test_that("jQuery UI is attached only when the list is sortable", {
  expect_true("jqueryui" %in% dependency_names("objects", choices = "a", sortable = TRUE))
  expect_false("jqueryui" %in% dependency_names("objects", choices = "a", sortable = FALSE))
})

test_that("plugins and evaluated options follow the sortable/removable flags", {
  # shiny appends its own accessibility plugin, so only ours are asserted
  plugins <- function(...) { unlist(config(...)$plugins) }

  both <- plugins("objects", choices = "a")
  expect_true(all(c("remove_button", "drag_drop") %in% both))
  expect_true(is.character(config("objects", choices = "a")$onInitialize))

  no_drag <- plugins("objects", choices = "a", sortable = FALSE)
  expect_true("remove_button" %in% no_drag)
  expect_false("drag_drop" %in% no_drag)
  # without `drag_drop` there is no `sortable` to configure
  expect_null(config("objects", choices = "a", sortable = FALSE)$onInitialize)

  no_remove <- plugins("objects", choices = "a", removable = FALSE)
  expect_true("drag_drop" %in% no_remove)
  expect_false("remove_button" %in% no_remove)

  neither <- plugins("objects", choices = "a", sortable = FALSE, removable = FALSE)
  expect_false(any(c("remove_button", "drag_drop") %in% neither))
})

test_that("the dropdown is suppressed and the row renderer is evaluated", {
  opts <- config("objects", choices = "a", allow_readd = FALSE)
  expect_false(opts$openOnFocus)
  expect_false(opts$create)
  expect_true(grepl("object-list-label", opts$render, fixed = TRUE))

  html <- rendered("objects", choices = "a", allow_readd = FALSE)
  expect_true(grepl('data-eval="[&quot;render&quot;,&quot;onInitialize&quot;]"',
                    html, fixed = TRUE))
})

test_that("allow_readd switches between the list-only and drop-down modes", {
  list_only <- rendered("objects", choices = "a", allow_readd = FALSE)
  expect_true(grepl('class="shidashi-object-list list-only"', list_only, fixed = TRUE))
  expect_false(config("objects", choices = "a", allow_readd = FALSE)$openOnFocus)
  expect_null(config("objects", choices = "a", allow_readd = FALSE)$onDropdownOpen)

  readd <- rendered("objects", choices = "a", allow_readd = TRUE)
  expect_true(grepl('class="shidashi-object-list"', readd, fixed = TRUE))
  # the stylesheet spells the modifier `.shidashi-object-list.list-only`, so a
  # space between the two only occurs in a container's class attribute
  expect_false(grepl("shidashi-object-list list-only", readd, fixed = TRUE))

  opts <- config("objects", choices = "a", allow_readd = TRUE)
  expect_true(opts$openOnFocus)
  # a re-selected entry has to join the list at the end
  expect_true(grepl("setCaret", opts$onDropdownOpen, fixed = TRUE))
  # a removed entry must stay in the menu to be re-addable
  expect_true(opts$persist)
})

test_that("the drop-down mode is the default", {
  # the tests above spell `allow_readd` out, so the default is pinned here
  expect_true(config("objects", choices = "a")$openOnFocus)
  # only a container's class attribute separates the two with a space; the
  # stylesheet always spells the modifier `.shidashi-object-list.list-only`
  expect_false(grepl("shidashi-object-list list-only",
                     rendered("objects", choices = "a"), fixed = TRUE))
})

test_that("the placeholder is drawn without touching the inner text field", {
  # list-only mode collapses the text field, so the placeholder travels as a
  # custom property that the stylesheet renders through `content`
  html <- rendered("objects", placeholder = "Nothing here", allow_readd = FALSE)
  expect_true(grepl("--object-list-placeholder:&#39;Nothing here&#39;;",
                    html, fixed = TRUE))
  expect_null(config("objects", allow_readd = FALSE)$placeholder)

  # the drop-down mode keeps the field, so selectize can draw it natively
  expect_equal(config("objects", placeholder = "Nothing here",
                      allow_readd = TRUE)$placeholder, "Nothing here")
  # the trailing colon matches only the declaration on the container, not the
  # `var()` reference in the stylesheet
  expect_false(grepl("--object-list-placeholder:",
                     rendered("objects", placeholder = "Nothing here",
                              allow_readd = TRUE), fixed = TRUE))

  # quotes and newlines must not break out of the CSS string
  tricky <- rendered("objects", placeholder = "It's\nempty", allow_readd = FALSE)
  expect_true(grepl("--object-list-placeholder:&#39;It\\&#39;s empty&#39;;",
                    tricky, fixed = TRUE))

  expect_false(grepl("--object-list-placeholder:",
                     rendered("objects", placeholder = NULL,
                              allow_readd = FALSE), fixed = TRUE))
})

test_that("unnamed choices fall back to their value as the label", {
  html <- rendered("objects", choices = c("a", "b"))
  expect_true(grepl('<option value="a" selected>a</option>', html, fixed = TRUE))
  expect_true(grepl('<option value="b" selected>b</option>', html, fixed = TRUE))
})

test_that("empty choices render an empty list", {
  html <- rendered("objects", choices = NULL)
  expect_true(grepl("shidashi-object-list", html, fixed = TRUE))
  expect_false(grepl("<option", html, fixed = TRUE))
})
