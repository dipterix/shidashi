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

test_that("discover_scripts hides helper files and folders", {
  tmp <- tempfile("skill")
  dir.create(file.path(tmp, "scripts", "lib"), recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines("# helpers", file.path(tmp, "scripts", "_common.R"))
  writeLines("# run", file.path(tmp, "scripts", "run.R"))

  expect_identical(discover_scripts(tmp), "run.R")
})

test_that("parse_script_usage reads block and one-line usage headers", {
  tmp <- tempfile("scripts")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  block <- file.path(tmp, "get_results.R")
  writeLines(c(
    "#!/usr/bin/env Rscript",
    "# get_results.R - Read a target",
    "#",
    "# Usage:",
    "#   Rscript get_results.R <module_id> --target=<name>",
    "#   Rscript get_results.R <module_id> --list",
    "#",
    "# Example:",
    "#   Rscript get_results.R notch_filter --target=apply_notch",
    "",
    "args <- commandArgs(trailingOnly = TRUE)"
  ), block)
  expect_identical(parse_script_usage(block),
                   c("<module_id> --target=<name>", "<module_id> --list"))

  one_line <- file.path(tmp, "greet.R")
  writeLines(c(
    "#!/usr/bin/env Rscript",
    "# Usage: Rscript greet.R [name]",
    "# Output: Hello, <name>!"
  ), one_line)
  expect_identical(parse_script_usage(one_line), "[name]")

  none <- file.path(tmp, "plain.R")
  writeLines(c("# nothing to see", "cat('hi')"), none)
  expect_identical(parse_script_usage(none), character())
})

test_that("script_usage_satisfied checks required positionals and options", {
  usage <- "<module_id> --target=<name> [--n=5]"
  expect_false(script_usage_satisfied(usage, character()))
  expect_false(script_usage_satisfied(usage, "power_explorer"))
  expect_false(script_usage_satisfied(usage, "--target=x"))
  expect_true(script_usage_satisfied(usage, c("power_explorer", "--target=x")))
  expect_true(script_usage_satisfied(
    usage, c("--target=x", "power_explorer", "--n=2")
  ))

  # optional JSON argument; any of several patterns; no documented usage
  expect_true(script_usage_satisfied("<module_id> ['JSON']", "notch_filter"))
  expect_true(script_usage_satisfied(
    c("<id> --target=<name>", "<id> --list"), c("a", "--list")
  ))
  expect_true(script_usage_satisfied(character(), character()))
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
  expect_match(summ, "`skill_load__greet`", fixed = TRUE)
  expect_match(summ, "greet", fixed = TRUE)
})


test_that("fuzzy_match_reference matches case-insensitively", {
  ref_files <- c("references/doc_A.md", "config.yaml", "notes/data.txt")

  # Exact match

  expect_equal(fuzzy_match_reference("references/doc_A.md", ref_files),
               "references/doc_A.md")

  # Case-insensitive full path
  expect_equal(fuzzy_match_reference("REFERENCES/DOC_A.MD", ref_files),
               "references/doc_A.md")
  expect_equal(fuzzy_match_reference("References/Doc_A.Md", ref_files),
               "references/doc_A.md")

  # Without prefix (just filename)
  expect_equal(fuzzy_match_reference("doc_A.md", ref_files),
               "references/doc_A.md")
  expect_equal(fuzzy_match_reference("DOC_A.MD", ref_files),
               "references/doc_A.md")

  # reference/ vs references/ prefix handling
  expect_equal(fuzzy_match_reference("reference/doc_A.md", ref_files),
               "references/doc_A.md")

  # Top-level file
  expect_equal(fuzzy_match_reference("config.yaml", ref_files),
               "config.yaml")
  expect_equal(fuzzy_match_reference("CONFIG.YAML", ref_files),
               "config.yaml")

  # Nested file by basename
  expect_equal(fuzzy_match_reference("data.txt", ref_files),
               "notes/data.txt")

  # No match returns NULL
  expect_null(fuzzy_match_reference("nonexistent.md", ref_files))
  expect_null(fuzzy_match_reference("", ref_files))
  expect_null(fuzzy_match_reference(NULL, ref_files))
  expect_null(fuzzy_match_reference("doc_A.md", character(0)))
})
