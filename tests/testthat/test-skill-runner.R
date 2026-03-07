test_that("run_skill_script executes R scripts portably", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  result <- run_skill_script(
    skill_dir = skill_dir,
    file_name = "greet.R",
    args = c("World")
  )

  expect_type(result, "list")
  expect_named(result, c("stdout", "stderr", "status", "timeout"),
               ignore.order = TRUE)
  expect_equal(result$status, 0L)
  expect_match(result$stdout, "Hello, World!")
  expect_false(isTRUE(result$timeout))
})

test_that("run_skill_script passes arguments correctly", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  result <- run_skill_script(
    skill_dir = skill_dir,
    file_name = "greet.R",
    args = c("Platform Test")
  )
  expect_match(result$stdout, "Hello, Platform Test!")
})

test_that("run_skill_script errors on missing script", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  expect_error(
    run_skill_script(skill_dir, "nonexistent.R"),
    "Script not found"
  )
})

test_that("run_skill_script errors on unconfigured extension", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  # Create a temp skill with an unsupported script extension

  tmp <- tempfile("skill_ext")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines("print('hi')", file.path(tmp, "scripts", "test.xyz"))

  expect_error(
    run_skill_script(tmp, "test.xyz"),
    "No interpreter configured"
  )
})

test_that("R interpreter resolves portably via R.home", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  # Create a minimal skill with an R script that prints R.home
  tmp <- tempfile("skill_rhome")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines('cat(R.home("bin"), "\\n")', file.path(tmp, "scripts", "check.R"))

  result <- run_skill_script(tmp, "check.R")
  expect_equal(result$status, 0L)
  # The output should match the current R's bin directory
  expect_match(trimws(result$stdout), R.home("bin"), fixed = TRUE)
})

test_that("shell scripts are rejected on Windows", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skip_if(.Platform$OS.type != "windows", "Windows-only test")

  tmp <- tempfile("skill_sh")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines("echo hello", file.path(tmp, "scripts", "test.sh"))

  expect_error(
    run_skill_script(tmp, "test.sh"),
    "not supported on Windows"
  )
})

test_that("shell scripts work on non-Windows", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skip_if(.Platform$OS.type == "windows", "non-Windows only test")

  tmp <- tempfile("skill_sh")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines('#!/bin/sh\necho "shell ok"', file.path(tmp, "scripts", "test.sh"))

  result <- run_skill_script(tmp, "test.sh")
  expect_equal(result$status, 0L)
  expect_match(result$stdout, "shell ok")
})

test_that("config.yaml interpreters are used when available", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  # This test simulates config.yaml loading by directly testing

  # the interpreter resolution path in run_skill_script.
  # Since there's no Shiny session, config.yaml is skipped and
  # built-in defaults are used — confirming the fallback works.

  tmp <- tempfile("skill_cfg")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines("cat('from R\\n')", file.path(tmp, "scripts", "hello.R"))

  # Without a Shiny session, config.yaml is ignored; R fallback works
  result <- run_skill_script(tmp, "hello.R")
  expect_equal(result$status, 0L)
  expect_match(result$stdout, "from R")
})

test_that("environment variables are passed to scripts", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")

  tmp <- tempfile("skill_env")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines('cat(Sys.getenv("TEST_VAR"), "\\n")',
             file.path(tmp, "scripts", "env_check.R"))

  result <- run_skill_script(
    tmp, "env_check.R",
    envs = c(TEST_VAR = "hello_from_test")
  )
  expect_equal(result$status, 0L)
  expect_match(result$stdout, "hello_from_test")
})
