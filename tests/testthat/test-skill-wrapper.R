greet_skill_dir <- function() {
  system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
}

gate_hint <- "`skill_load__greet` (action='readme') first"

test_that("skill_wrapper creates a closure with correct class", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  wrapper <- skill_wrapper(skill_dir)
  expect_s3_class(wrapper, "shidashi_skill_wrapper")
  expect_true(is.function(wrapper))
})

test_that("skill_wrapper errors on missing SKILL.md", {
  tmp <- tempfile("empty_skill")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  expect_error(skill_wrapper(tmp), "SKILL.md not found")
})

test_that("wrapper() returns a load tool and a run tool", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()
  expect_named(tools, c("load", "run"))
  expect_true(inherits(tools$load, "ellmer::ToolDef"))
  expect_true(inherits(tools$run, "ellmer::ToolDef"))
  expect_identical(tools$load@name, "skill_load__greet")
  expect_identical(tools$run@name, "skill_run__greet")

  # reading and running take different arguments; greet has no reference
  # files, so reading takes no reference arguments
  expect_identical(names(tools$load@arguments@properties), "action")
  expect_setequal(names(tools$run@arguments@properties),
                  c("file_name", "args", "envs"))
  expect_match(tools$load@description, "skill_run__greet", fixed = TRUE)
  expect_match(tools$run@description, "skill_load__greet", fixed = TRUE)
})

test_that("a skill without scripts has no run tool", {
  skill_dir <- file.path(tempfile("skills"), "notes")
  dir.create(skill_dir, recursive = TRUE)
  on.exit(unlink(dirname(skill_dir), recursive = TRUE), add = TRUE)
  writeLines(c("---", "name: notes", "description: Notes", "---", "",
               "Read me."), file.path(skill_dir, "SKILL.md"))

  tools <- skill_wrapper(skill_dir)()
  expect_identical(tools$load@name, "skill_load__notes")
  expect_null(tools$run)
  expect_false(grepl("skill_run__", tools$load@description, fixed = TRUE))
})

test_that("the load tool reads reference files when the skill has them", {
  skill_dir <- file.path(tempfile("skills"), "notes")
  dir.create(file.path(skill_dir, "references"), recursive = TRUE)
  on.exit(unlink(dirname(skill_dir), recursive = TRUE), add = TRUE)
  writeLines(c("---", "name: notes", "description: Notes", "---", "",
               "Read me."), file.path(skill_dir, "SKILL.md"))
  writeLines(c("alpha", "beta", "gamma"),
             file.path(skill_dir, "references", "list.md"))

  tools <- skill_wrapper(skill_dir)()
  expect_setequal(names(tools$load@arguments@properties),
                  c("action", "file_name", "pattern", "line_start", "n_lines"))
  result <- tools$load(action = "reference", file_name = "list.md",
                       pattern = "^[ab]")
  expect_match(result, "alpha")
  expect_match(result, "beta")
  expect_false(grepl("gamma", result, fixed = TRUE))
})

test_that("the run tool shows each script's usage and checks arguments", {
  skill_dir <- file.path(tempfile("skills"), "pipes")
  dir.create(file.path(skill_dir, "scripts"), recursive = TRUE)
  on.exit(unlink(dirname(skill_dir), recursive = TRUE), add = TRUE)
  writeLines(c("---", "name: pipes", "description: Pipes", "---", "",
               "Read me."), file.path(skill_dir, "SKILL.md"))
  writeLines(c(
    "# Usage:",
    "#   Rscript get_results.R <module_id> --target=<name>",
    "",
    "stop('should not run')"
  ), file.path(skill_dir, "scripts", "get_results.R"))
  writeLines("# shared helpers", file.path(skill_dir, "scripts", "_common.R"))

  tools <- skill_wrapper(skill_dir)()
  file_desc <- tools$run@arguments@properties$file_name@description
  expect_match(file_desc, "get_results.R <module_id> --target=<name>",
               fixed = TRUE)
  expect_false(grepl("_common.R", file_desc, fixed = TRUE))
  expect_match(tools$load(), "get_results.R <module_id> --target=<name>",
               fixed = TRUE)

  # rejected before the script runs
  err <- tryCatch(
    tools$run(file_name = "get_results.R", args = list("power_explorer")),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "missing required arguments", fixed = TRUE)
  expect_match(err, "`get_results.R <module_id> --target=<name>`",
               fixed = TRUE)
  expect_false(grepl("should not run", err, fixed = TRUE))

  err <- tryCatch(tools$run(file_name = "_common.R"),
                  error = function(e) conditionMessage(e))
  expect_match(err, "Script not found", fixed = TRUE)
})

test_that("the load tool returns the readme by default", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()
  result <- tools$load()
  expect_type(result, "character")
  expect_match(result, "Instructions")
  expect_match(result, "greet\\.R")
  expect_match(result, "skill_run__greet", fixed = TRUE)
  expect_identical(tools$load(action = "readme"), result)
})

test_that("soft gate augments errors before readme", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()

  err <- tryCatch(
    tools$run(file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "Script not found")
  expect_match(err, gate_hint, fixed = TRUE)

  # a missing script name is explained, not an R error about arguments
  err <- tryCatch(tools$run(), error = function(e) conditionMessage(e))
  expect_match(err, "file_name is required")
})

test_that("soft gate allows successful calls before readme", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()

  # Valid script call should succeed even without readme
  result <- tools$run(file_name = "greet.R", args = list("TestUser"))
  expect_match(result, "Hello, TestUser!")
})

test_that("reading the readme unlocks the run tool of the same pair", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()
  tools$load(action = "readme")  # unlock

  err <- tryCatch(
    tools$run(file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "Script not found")
  expect_false(grepl(gate_hint, err, fixed = TRUE))
})

test_that("the run tool runs greet.R via processx", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tools <- skill_wrapper(skill_dir)()
  tools$load(action = "readme")  # unlock
  result <- tools$run(file_name = "greet.R", args = list("Copilot"))
  expect_match(result, "Hello, Copilot!")
  expect_match(result, "Exit code: 0", fixed = TRUE)
})

test_that("each wrapper() call gets independent gate state", {
  skill_dir <- greet_skill_dir()
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  wrapper <- skill_wrapper(skill_dir)
  tools1 <- wrapper()
  tools2 <- wrapper()

  # Unlock the first pair
  tools1$load(action = "readme")

  # The second pair should still have gate active (error augmented on failure)
  err <- tryCatch(
    tools2$run(file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, gate_hint, fixed = TRUE)

  # The first pair is unlocked — error not augmented
  err1 <- tryCatch(
    tools1$run(file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl(gate_hint, err1, fixed = TRUE))
})

test_that("the chat asks before a destructive script, not before others", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  app_env <- local_mcp_app()
  root <- make_mini_template()
  add_mini_skill(root, "tidy",
                 scripts = c(peek.R = "exploratory", wipe.R = "destructive"))

  tools <- compile_tools_and_scripts(root, "alpha", env = new.env())(NULL)
  globals_set_agent_mode("alpha", "Executing")
  globals_set_confirmation_policy("alpha", "ask")

  asked <- character()
  local_mocked_bindings(mcp_tool_ask_user = function(arguments, ...) {
    asked <<- c(asked, arguments$tool_name)
    list(content = list(list(type = "text", text = "Stop and revise")))
  })

  load_tool <- tools$get("skill_load__tidy")
  expect_match(load_tool(), "Nothing to see")
  expect_length(asked, 0L)

  run_tool <- tools$get("skill_run__tidy")
  expect_match(run_tool(file_name = "peek.R"), "peek.R ran")
  expect_length(asked, 0L)

  res <- run_tool(file_name = "wipe.R")
  expect_true(promises::is.promise(res))
  promises::catch(res, function(e) NULL)
  expect_identical(asked, "tidy")
})
