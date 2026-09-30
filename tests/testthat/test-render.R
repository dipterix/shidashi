test_that("include_view() renders a view without touching the global environment", {
  root <- tempfile("views-")
  dir.create(file.path(root, "views"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("<p>{{ greeting }}</p>", file.path(root, "views", "hello.html"))
  had_env <- exists(".env", envir = globalenv(), inherits = FALSE)

  greeting <- "hi there"
  html <- as.character(include_view("hello.html", .root_path = root))
  expect_match(html, "<p>hi there</p>", fixed = TRUE)
  if (!had_env) {
    expect_false(exists(".env", envir = globalenv(), inherits = FALSE))
  }

  expect_error(include_view("nothing.html", .root_path = root),
               "Cannot find views/nothing.html", fixed = TRUE)
})
