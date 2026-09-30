read_launchers_json <- function(cache) {
  jsonlite::fromJSON(file.path(cache, "launchers.json"), simplifyVector = FALSE)
}

# A mini template that also carries folders a copy should skip
make_app_with_extras <- function() {
  root <- make_mini_template()
  dir.create(file.path(root, "node_modules", "pkg"), recursive = TRUE)
  writeLines("x", file.path(root, "node_modules", "pkg", "index.js"))
  dir.create(file.path(root, ".git"))
  writeLines("x", file.path(root, ".git", "HEAD"))
  root
}

test_that("save_launcher writes launchers.json in the cache folder", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()

  entry <- save_launcher("mini", root, description = "Mini app")
  launchers <- read_launchers_json(cache)
  expect_named(launchers, "mini")
  saved <- launchers$mini
  expect_identical(saved$root_path, normalizePath(root, winslash = "/"))
  expect_identical(saved$host, "127.0.0.1")
  expect_null(saved$port)
  # default: the modules whose agents.yaml enables agents
  expect_identical(unlist(saved$modules), c("alpha", "beta"))
  expect_identical(saved$description, "Mini app")
  expect_false(saved$copied)
  expect_true(file.exists(saved$rscript))
  expect_match(saved$saved, "^\\d{4}-\\d{2}-\\d{2}T")
  expect_identical(entry$root_path, saved$root_path)

  # saving a launcher also installs the proxy
  expect_true(file.exists(file.path(cache, "mcp_server", "mcp-proxy.mjs")))
})

test_that("launchers share one file, and saving an id again replaces it", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()

  save_launcher("one", root)
  save_launcher("two", root, host = "0.0.0.0", port = 8123, modules = "gamma",
                prelaunch = "options(my_option = 1)")
  save_launcher("one", root, description = "again")

  launchers <- read_launchers_json(cache)
  expect_setequal(names(launchers), c("one", "two"))
  expect_identical(launchers$one$description, "again")
  expect_identical(launchers$two$host, "0.0.0.0")
  expect_identical(launchers$two$port, 8123L)
  expect_identical(unlist(launchers$two$modules), "gamma")
  expect_identical(launchers$two$prelaunch, "options(my_option = 1)")
})

test_that("extra arguments are stored as metadata", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()

  save_launcher("mini", root, lab = "demo", subjects = c("a", "b"), n = 3)
  metadata <- read_launchers_json(cache)$mini$metadata
  expect_identical(metadata$lab, "demo")
  expect_identical(unlist(metadata$subjects), c("a", "b"))
  expect_identical(metadata$n, 3L)

  # an unnamed value only reaches `...` after all the named parameters
  expect_error(save_launcher("mini", root, "127.0.0.1", NA, NULL, "", NULL,
                             FALSE, "unnamed"), "named")
  expect_error(save_launcher("mini", root, when = Sys.Date()), "plain")
  expect_error(save_launcher("mini", root, f = function() 1), "plain")
})

test_that("save_launcher rejects bad input", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()

  for (id in c("a.b", "a b", "../x", "", "x/y")) {
    expect_error(save_launcher(id, root), "id", info = id)
  }
  expect_error(save_launcher("mini", tempdir()), "modules.yaml")
  expect_error(save_launcher("mini", root, modules = "nope"), "nope")
  expect_error(save_launcher("mini", root, port = 0), "port")
  expect_error(save_launcher("mini", root, prelaunch = "1 +"), "prelaunch")
  expect_false(file.exists(file.path(cache, "launchers.json")))
})

test_that("copy_app copies the app, without .git and node_modules", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_app_with_extras()

  entry <- save_launcher("mini", root, copy_app = TRUE)
  copy <- normalizePath(file.path(cache, "saved_apps", "mini"), winslash = "/")
  expect_identical(entry$root_path, copy)
  expect_true(read_launchers_json(cache)$mini$copied)
  expect_true(file.exists(file.path(copy, "modules.yaml")))
  expect_true(file.exists(file.path(copy, "agents", "tools", "hello.R")))
  expect_false(dir.exists(file.path(copy, "node_modules")))
  expect_false(dir.exists(file.path(copy, ".git")))

  # saving again starts from a clean folder
  writeLines("stale", file.path(copy, "stale.txt"))
  save_launcher("mini", root, copy_app = TRUE)
  expect_false(file.exists(file.path(copy, "stale.txt")))

  # saving from the copy itself keeps the app
  save_launcher("mini", copy, copy_app = TRUE)
  expect_true(file.exists(file.path(copy, "modules.yaml")))
})

test_that("without copy_app, an old copy is removed unless it is the app", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()
  copy <- file.path(cache, "saved_apps", "mini")

  save_launcher("mini", root, copy_app = TRUE)
  save_launcher("mini", copy)                    # the app is the copy: keep it
  expect_true(file.exists(file.path(copy, "modules.yaml")))

  save_launcher("mini", root)                    # back to the original: drop it
  expect_false(dir.exists(copy))
})

test_that("run_launcher starts the saved app, with extra render() arguments", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  root <- make_mini_template()
  save_launcher("mini", root, port = 8123, prelaunch = "options(my_option = 1)")
  save_launcher("noport", root)

  captured <- NULL
  local_mocked_bindings(render = function(...) {
    captured <<- list(...)
    invisible()
  })

  run_launcher("mini")
  expect_identical(captured$root_path, normalizePath(root, winslash = "/"))
  expect_identical(captured$host, "127.0.0.1")
  expect_identical(captured$port, 8123L)
  expect_false(captured$launch_browser)
  expect_false(captured$as_job)
  expect_true(captured$prelaunch_quoted)
  expect_identical(deparse(captured$prelaunch[[1]]), "options(my_option = 1)")

  run_launcher("mini", launch_browser = TRUE, test_mode = TRUE)
  expect_true(captured$launch_browser)
  expect_true(captured$test_mode)

  run_launcher("noport")
  expect_false("port" %in% names(captured))
  expect_null(captured$prelaunch)

  expect_error(run_launcher("nope"), "mini")
  expect_error(run_launcher("mini", TRUE), "named")
})

test_that("the cache folder follows the option, then SHIDASHI_CACHE_DIR", {
  old_env <- Sys.getenv("SHIDASHI_CACHE_DIR", unset = NA)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("SHIDASHI_CACHE_DIR")
    else Sys.setenv(SHIDASHI_CACHE_DIR = old_env)
  }, add = TRUE)
  old <- options(shidashi.cache_dir = NULL)
  on.exit(options(old), add = TRUE)

  Sys.setenv(SHIDASHI_CACHE_DIR = "/from/env")
  expect_identical(shidashi_cache_dir(), "/from/env")
  expect_identical(mcp_server_dir(), file.path("/from/env", "mcp_server"))

  options(shidashi.cache_dir = "/from/option")
  expect_identical(shidashi_cache_dir(), "/from/option")
})

test_that("setup_mcp_proxy writes the meta tools for the offline proxy", {
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)

  setup_mcp_proxy(verbose = FALSE)
  meta <- jsonlite::fromJSON(file.path(cache, "mcp_server", "proxy-meta.json"),
                             simplifyVector = FALSE)
  expect_setequal(vapply(meta$tools, `[[`, "", "name"),
                  c("shidashi_sessions", "shidashi_tools", "shidashi_call",
                    "switch_module"))
  expect_match(meta$instructions, "_module")
  expect_false(grepl("app `", meta$instructions, fixed = TRUE))
})

test_that("app records include the host", {
  root <- use_template_root(make_mini_template())
  records_dir <- tempfile("apps-")
  on.exit(template_settings$set(mcp_app_id = NULL), add = TRUE)

  path <- mcp_write_app_record(port = 8123, appdir = root, host = "0.0.0.0",
                               records_dir = records_dir)
  expect_identical(jsonlite::fromJSON(path)$host, "0.0.0.0")
})
