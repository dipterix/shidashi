test_that("harvesting a module returns its tool schemas without a browser", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())

  harvested <- mcp_harvest_module("alpha", root_path = root)
  expect_true(harvested$ok)
  expect_named(harvested$tools, "tool__hello")
  schema <- harvested$tools$tool__hello
  expect_identical(schema$name, "tool__hello")
  expect_true(all(c("name", "_intent") %in% names(schema$inputSchema$properties)))
})

test_that("a module that fails to load reports an error instead of stopping", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())

  harvested <- mcp_harvest_module("beta", root_path = root)
  expect_false(harvested$ok)
  expect_match(harvested$error, "beta is broken")
})

test_that("catalog merges modules, skips disabled ones, and adds _module", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())

  catalog <- mcp_catalog(root_path = root)
  expect_named(catalog$tools, "tool__hello")
  hello <- catalog$tools$tool__hello
  expect_identical(hello$live_name, "tool__hello")
  # beta failed to harvest, but agents.yaml says it offers `hello`
  expect_setequal(hello$modules, c("alpha", "beta"))
  expect_false("gamma" %in% hello$modules)
  expect_true("_module" %in% names(hello$schema$inputSchema$properties))
  expect_named(catalog$errors, "beta")
})

test_that("catalog does not depend on which sessions are open", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())

  before <- mcp_catalog(root_path = root, refresh = TRUE)
  fake_module_session("alpha", c("tool__hello", "tool__live_only"))
  after <- mcp_catalog(root_path = root, refresh = TRUE)
  expect_identical(names(after$tools), names(before$tools))
  expect_identical(after$tools, before$tools)
})

test_that("catalog is cached until a template file changes", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())

  first <- mcp_catalog(root_path = root)
  expect_identical(mcp_catalog(root_path = root)$fingerprint, first$fingerprint)

  writeLines(c(
    "bye <- ellmer::tool(function() 'bye', name = 'bye', description = 'Bye')"
  ), file.path(root, "agents", "tools", "bye.R"))
  cat("- name: bye\n  enabled: yes\n",
      file = file.path(root, "modules", "alpha", "agents.yaml"), append = TRUE)

  second <- mcp_catalog(root_path = root)
  expect_false(identical(second$fingerprint, first$fingerprint))
  expect_true("tool__bye" %in% names(second$tools))
})

test_that("tools that disagree across modules get module-qualified names", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  # make beta load, with its own `hello` that has different arguments
  unlink(file.path(root, "modules", "beta", "R", "broken.R"))
  writeLines(c(
    "hello <- ellmer::tool(",
    "  function(times = 1) 'hi',",
    "  name = 'hello',",
    "  description = 'Say hi several times',",
    "  arguments = list(times = ellmer::type_integer('How many times'))",
    ")"
  ), file.path(root, "modules", "beta", "R", "hello.R"))

  catalog <- suppressWarnings(mcp_catalog(root_path = root))
  expect_setequal(names(catalog$tools),
                  c("tool__alpha__hello", "tool__beta__hello"))
  expect_identical(catalog$tools$tool__beta__hello$live_name, "tool__hello")
  expect_identical(catalog$tools$tool__beta__hello$modules, "beta")
})

test_that("the bundled template harvests the built-in shiny tools", {
  app_env <- local_mcp_app()
  root <- use_template_root(normalizePath(
    system.file("builtin-templates", "bslib-bare", package = "shidashi")
  ))

  harvested <- mcp_harvest_module("aiagent", root_path = root)
  expect_true(harvested$ok)
  expect_true(all(c(
    "tool__shiny_input_info", "tool__shiny_input_update",
    "tool__shiny_query_ui", "tool__hello_world", "skill_load__greet",
    "skill_run__greet"
  ) %in% names(harvested$tools)))
})

test_that("one failing tool generator does not hide the other tools", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  writeLines(
    "bad <- shidashi::mcp_wrapper(function(session) stop('bad generator'))",
    file.path(root, "agents", "tools", "bad.R")
  )

  harvested <- suppressWarnings(mcp_harvest_module("alpha", root_path = root))
  expect_true(harvested$ok)
  expect_named(harvested$tools, "tool__hello")
  expect_warning(mcp_harvest_module("alpha", root_path = root), "bad generator")
})

test_that("catalog marks read-only and destructive tools", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_tool(root, "wipe", category = c("executing", "destructive"),
                enabled = '["Executing"]')

  catalog <- mcp_catalog(root_path = root)
  hello <- catalog$tools$tool__hello$schema
  expect_identical(hello$annotations,
                   list(readOnlyHint = TRUE, destructiveHint = FALSE))
  expect_false(grepl("Ask the user", hello$description))

  wipe <- catalog$tools$tool__wipe$schema
  expect_identical(wipe$annotations,
                   list(readOnlyHint = FALSE, destructiveHint = TRUE))
  expect_match(wipe$description,
               "Ask the user in this conversation before calling it",
               fixed = TRUE)
})

test_that("tools turned off in agents.yaml are not listed", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_tool(root, "off_tool", enabled = "no")

  expect_false("tool__off_tool" %in% names(mcp_catalog(root_path = root)$tools))
})

test_that("a tool marked destructive in any module is destructive", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  # beta (which fails to load) marks `hello` destructive
  writeLines(c(
    "tools:",
    "- name: hello",
    "  category:",
    "  - destructive",
    "  enabled: yes"
  ), file.path(root, "modules", "beta", "agents.yaml"))

  catalog <- mcp_catalog(root_path = root)
  expect_named(catalog$tools, "tool__hello")
  expect_setequal(catalog$tools$tool__hello$modules, c("alpha", "beta"))
  expect_true(catalog$tools$tool__hello$schema$annotations$destructiveHint)
})

test_that("skills with destructive scripts name those scripts", {
  # loads every bundled module, and the demo module attaches ggplot2,
  # ggExtra, and plyr
  skip_on_cran()
  app_env <- local_mcp_app()
  root <- use_template_root(normalizePath(
    system.file("builtin-templates", "bslib-bare", package = "shidashi")
  ))

  # the bundled modules each define their own `trigger_refresh`, which the
  # catalog reports as a conflict when every module loads
  catalog <- suppressWarnings(mcp_catalog(root_path = root, refresh = TRUE))
  greet <- catalog$tools$skill_run__greet$schema
  expect_true(greet$annotations$destructiveHint)
  expect_match(greet$description, "`greet.R`", fixed = TRUE)
  # reading the skill is never destructive
  expect_identical(catalog$tools$skill_load__greet$schema$annotations,
                   list(readOnlyHint = TRUE, destructiveHint = FALSE))
  expect_true(
    catalog$tools$tool__shiny_input_update$schema$annotations$destructiveHint
  )
  expect_true(
    catalog$tools$tool__shiny_input_info$schema$annotations$readOnlyHint
  )
})

test_that("catalog is built once and then served from the cache", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  builds <- 0L
  real_build <- mcp_build_catalog
  local_mocked_bindings(mcp_build_catalog = function(...) {
    builds <<- builds + 1L
    real_build(...)
  })

  mcp_catalog(root_path = root)
  mcp_catalog(root_path = root)
  mcp_catalog(root_path = root)
  expect_identical(builds, 1L)

  writeLines("# changed", file.path(root, "agents", "tools", "extra.R"))
  mcp_catalog(root_path = root)
  expect_identical(builds, 2L)
})

test_that("skill load tools are read-only; run tools follow their scripts", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  # alpha marks wipe.R destructive; beta (which fails to load) does not
  # offer it at all
  add_mini_skill(root, "tidy",
                 scripts = c(peek.R = "exploratory", wipe.R = "destructive"),
                 modules = "alpha")
  add_mini_skill(root, "tidy", scripts = c(peek.R = "exploratory"),
                 modules = "beta")

  catalog <- mcp_catalog(root_path = root)
  load <- catalog$tools$skill_load__tidy
  expect_setequal(load$modules, c("alpha", "beta"))
  expect_identical(load$schema$annotations,
                   list(readOnlyHint = TRUE, destructiveHint = FALSE))
  expect_false(grepl("Ask the user", load$schema$description, fixed = TRUE))
  expect_false("args" %in% names(load$schema$inputSchema$properties))

  run <- catalog$tools$skill_run__tidy
  expect_setequal(run$modules, c("alpha", "beta"))
  expect_identical(run$schema$annotations,
                   list(readOnlyHint = FALSE, destructiveHint = TRUE))
  expect_match(run$schema$description, "before running them: `wipe.R`.",
               fixed = TRUE)
  expect_false("action" %in% names(run$schema$inputSchema$properties))
})

test_that("a skill without scripts lists only its load tool", {
  app_env <- local_mcp_app()
  root <- use_template_root(make_mini_template())
  add_mini_skill(root, "notes", modules = c("alpha", "beta"))

  catalog <- mcp_catalog(root_path = root)
  expect_true("skill_load__notes" %in% names(catalog$tools))
  expect_false("skill_run__notes" %in% names(catalog$tools))
})

test_that("module-qualified names keep the tool type", {
  expect_identical(mcp_qualified_tool_name("tool__hello", "beta"),
                   "tool__beta__hello")
  expect_identical(mcp_qualified_tool_name("skill_load__greet", "beta"),
                   "skill_load__beta__greet")
  expect_identical(mcp_qualified_tool_name("skill_run__greet", "beta"),
                   "skill_run__beta__greet")
})
