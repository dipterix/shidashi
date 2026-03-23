test_that("skill_wrapper creates a closure with correct class", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
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

test_that("wrapper() returns an ellmer::ToolDef", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  wrapper <- skill_wrapper(skill_dir)
  tool_def <- wrapper()
  expect_true(inherits(tool_def, "ellmer::ToolDef"))
  expect_equal(tool_def@name, "greet")
})

test_that("action='readme' returns SKILL.md body with script listing", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tool_def <- skill_wrapper(skill_dir)()
  result <- tool_def(action = "readme")
  expect_type(result, "character")
  expect_match(result, "Instructions")
  expect_match(result, "greet\\.R")
})

test_that("soft gate augments errors before readme", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tool_def <- skill_wrapper(skill_dir)()

  # Requesting a nonexistent reference triggers error + readme hint
  err <- tryCatch(
    tool_def(action = "script", file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "action='readme' first", fixed = TRUE)
})

test_that("soft gate allows successful calls before readme", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tool_def <- skill_wrapper(skill_dir)()

  # Valid script call should succeed even without readme

  result <- tool_def(action = "script", file_name = "greet.R",
                     args = list("TestUser"))
  expect_match(result, "Hello, TestUser!")
})

test_that("after readme, errors are not augmented", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tool_def <- skill_wrapper(skill_dir)()
  tool_def(action = "readme")  # unlock

  err <- tryCatch(
    tool_def(action = "script", file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "Script not found")
  expect_false(grepl("action='readme' first", err, fixed = TRUE))
})

test_that("action='script' runs greet.R via processx", {
  skip_if(!requireNamespace("processx", quietly = TRUE), "processx not installed")
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  tool_def <- skill_wrapper(skill_dir)()
  tool_def(action = "readme")  # unlock
  result <- tool_def(action = "script", file_name = "greet.R",
                     args = list("Copilot"))
  expect_match(result, "Hello, Copilot!")
  expect_match(result, "Exit code: 0", fixed = TRUE)
})

test_that("each wrapper() call gets independent gate state", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  wrapper <- skill_wrapper(skill_dir)
  tool1 <- wrapper()
  tool2 <- wrapper()

  # Unlock tool1

  tool1(action = "readme")

  # tool2 should still have gate active (error augmented on failure)
  err <- tryCatch(
    tool2(action = "script", file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "action='readme' first", fixed = TRUE)

  # tool1 gate is unlocked — error not augmented
  err1 <- tryCatch(
    tool1(action = "script", file_name = "nonexistent.R"),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl("action='readme' first", err1, fixed = TRUE))
})
