test_that("sanitize_skill_name works", {
  expect_equal(sanitize_skill_name("greet"), "greet")
  expect_equal(sanitize_skill_name("My Cool-Skill"), "my_cool_skill")
  expect_equal(sanitize_skill_name("  Hello World  "), "hello_world")
  expect_equal(sanitize_skill_name("a__b--c"), "a_b_c")
  expect_equal(sanitize_skill_name("123"), "123")
  expect_error(sanitize_skill_name("---"), "empty after sanitization")
})

test_that("parse_skill_md parses frontmatter and body", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  parsed <- parse_skill_md(file.path(skill_dir, "SKILL.md"))

  expect_type(parsed, "list")
  expect_named(parsed,
    c("name", "description", "body", "frontmatter", "skill_dir"),
    ignore.order = TRUE
  )
  expect_equal(parsed$name, "greet")
  expect_match(parsed$description, "Greets", ignore.case = TRUE)
  expect_match(parsed$body, "Instructions")
  expect_true(dir.exists(parsed$skill_dir))
})

test_that("parse_skill_md handles missing frontmatter", {
  tmp <- tempfile("skill")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines(c("# My Skill", "", "Some instructions"), file.path(tmp, "SKILL.md"))

  parsed <- parse_skill_md(file.path(tmp, "SKILL.md"))
  # Name falls back to directory basename
  expect_equal(parsed$name, basename(tmp))
  # Description falls back to first non-empty line
  expect_equal(parsed$description, "My Skill")
  expect_match(parsed$body, "My Skill")
})

test_that("discover_scripts finds scripts/", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  scripts <- discover_scripts(skill_dir)
  expect_true("greet.R" %in% scripts)
})

test_that("discover_scripts returns empty for missing scripts/", {
  tmp <- tempfile("skill")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  expect_length(discover_scripts(tmp), 0)
})

test_that("discover_references excludes SKILL.md and scripts/", {
  tmp <- tempfile("skill")
  dir.create(file.path(tmp, "scripts"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  writeLines("---\nname: test\n---\nBody", file.path(tmp, "SKILL.md"))
  writeLines("ref content", file.path(tmp, "notes.md"))
  writeLines("data", file.path(tmp, "data.csv"))
  writeLines("#!/bin/sh", file.path(tmp, "scripts", "run.sh"))

  refs <- discover_references(tmp)
  expect_true("notes.md" %in% refs)
  expect_true("data.csv" %in% refs)
  expect_false(any(grepl("SKILL.md", refs, ignore.case = TRUE)))
  expect_false(any(grepl("^scripts/", refs)))
})

test_that("build_condensed_summary produces expected structure", {
  skill_dir <- system.file(
    "builtin-templates/bslib-bare/agents/skills/greet",
    package = "shidashi"
  )
  skip_if(!nzchar(skill_dir), "greet skill not installed")

  parsed <- parse_skill_md(file.path(skill_dir, "SKILL.md"))
  scripts <- discover_scripts(skill_dir)
  refs <- discover_references(skill_dir)

  summ <- build_condensed_summary(parsed, refs, scripts)
  expect_type(summ, "character")
  expect_match(summ, "action='readme'", fixed = TRUE)
  expect_match(summ, "greet", fixed = TRUE)
})
