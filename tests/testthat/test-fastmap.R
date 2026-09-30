test_that("new_fastmap() is a working fastmap with its own class", {
  map <- new_fastmap()
  expect_true(is_shidashi_fastmap(map))
  expect_s3_class(map, "shidashi-fastmap")

  map$set("a", 1)
  map$mset(b = 2, c = 3)
  expect_identical(map$get("a"), 1)
  expect_null(map$get("zzz"))
  expect_setequal(names(map$as_list()), c("a", "b", "c"))

  expect_false(is_shidashi_fastmap(fastmap::fastmap()))
  expect_false(is_shidashi_fastmap(list()))

  expect_identical(new_fastmap(missing_default = 0)$get("nothing"), 0)
})

test_that("init_app() keeps the registries it already created", {
  withr::local_options(list(shidashi.shared_id = NULL))
  app_env <- new.env()
  init_app(app_env)
  registry <- globals_session_registry()
  registry$set("token", "entry")

  init_app(app_env)
  expect_identical(globals_session_registry()$get("token"), "entry")
})
