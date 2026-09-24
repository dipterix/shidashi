# ---- Skill wrapper for Phase 4 skills ----
#
# Turns an Anthropic-compliant skill directory (SKILL.md + optional
# scripts/ + reference files) into two MCP tools via closure: one that
# reads the instructions and references (never changes anything), and one
# that runs the scripts (may change the user's work). Mirrors the
# mcp_wrapper() pattern from Phase 3 but with progressive disclosure and a
# gate mechanism.

#' Wrap a Skill Directory as \verb{MCP} Tool Generators
#'
#' @description
#' Creates a closure that produces two \code{ellmer::tool} objects for a
#' skill:
#' \describe{
#'   \item{\code{skill_load__<name>}}{Reads the skill. Its \code{action}
#'     argument is \code{readme} (the full \verb{SKILL.md} instructions, the
#'     default) or \code{reference} (content from a reference file in the
#'     skill directory). It never changes anything.}
#'   \item{\code{skill_run__<name>}}{Executes a script in the
#'     \code{scripts/} subdirectory via \code{processx::run()}. Only created
#'     when the skill has scripts.}
#' }
#'
#' @param skill_path Path to the skill directory containing \code{SKILL.md}.
#'   Can be absolute or relative to the project root.
#'
#' @return A function with class \code{c("shidashi_skill_wrapper", "function")}
#'   that returns a list with elements \code{load} (an
#'   \code{ellmer::ToolDef}) and \code{run} (an \code{ellmer::ToolDef}, or
#'   \code{NULL} when the skill has no scripts).
#'
#' @details
#'   The two tools share a soft gate: reading a reference or running a
#'   script before the \code{readme} is allowed, but if the call errors the
#'   message is augmented with a condensed summary (~200 tokens) instructing
#'   the AI to read the full instructions first. This minimizes token waste
#'   (the summary is only sent on failure).
#'
#'   The gate state is per-instance: each call to the wrapper produces
#'   a pair of tools with an independent \code{readme_unlocked} flag.
#'
#' @examples
#' skill_dir <- system.file(
#'   "builtin-templates/bslib-bare/agents/skills/greet",
#'   package = "shidashi"
#' )
#' wrapper <- skill_wrapper(skill_dir)
#' tools <- wrapper()
#' cat(tools$load(action = "readme"))
#'
#' @export
skill_wrapper <- function(skill_path) {

  # Validate skill directory at definition time
  skill_md_path <- file.path(skill_path, "SKILL.md")
  if (!file.exists(skill_md_path)) {
    stop("SKILL.md not found in: ", skill_path)
  }

  # Parse once at definition time (immutable metadata)
  parsed <- parse_skill_md(skill_md_path)
  ref_files <- discover_references(parsed$skill_dir)
  script_files <- discover_scripts(parsed$skill_dir)

  # Per Anthropic spec, the canonical skill name is the folder name
  canonical_name <- basename(normalizePath(skill_path))
  load_name <- sprintf("skill_load__%s", canonical_name)
  run_name <- sprintf("skill_run__%s", canonical_name)

  # Pre-build condensed summary for gate errors (use folder name)
  parsed$name <- canonical_name
  condensed <- build_condensed_summary(parsed, ref_files, script_files,
                                       load_name = load_name)

  has_references <- length(ref_files) > 0
  has_scripts <- length(script_files) > 0

  load_actions <- "readme"
  if (has_references) {
    load_actions <- c(load_actions, "reference")
  }

  # Build short descriptions for tools/list (Tier 1: ~30 tokens)
  load_description <- paste0(
    parsed$description,
    " [Skill: read its instructions (action='readme') before anything else",
    if (has_scripts) {
      sprintf("; run its scripts with `%s`", run_name)
    },
    "]"
  )
  run_description <- paste0(
    parsed$description,
    " [Skill scripts: ", paste(script_files, collapse = ", "),
    sprintf("; read the instructions with `%s` first]", load_name)
  )

  ref_desc <- if (has_references) {
    paste0("Available: ", paste(ref_files, collapse = ", "))
  } else {
    "No reference files available for this skill"
  }

  # ellmer::tool requires the argument names to match the function formals
  load_args <- list(
    action = ellmer::type_enum(
      values = load_actions,
      description = paste0(
        "What to read. Default: 'readme', the full instructions; read them ",
        "before anything else. Available: ",
        paste(load_actions, collapse = ", ")
      ),
      required = FALSE
    ),
    file_name = ellmer::type_string(
      description = paste0("Reference file for action='reference'. ", ref_desc),
      required = FALSE
    ),
    pattern = ellmer::type_string(
      description = "For action='reference': optional grep pattern to filter lines.", # nolint: line_length_linter.
      required = FALSE
    ),
    line_start = ellmer::type_integer(
      description = "For action='reference': start line (1-based). Default: 1.",
      required = FALSE
    ),
    n_lines = ellmer::type_integer(
      description = "For action='reference': max lines to return. Default: 200.", # nolint: line_length_linter.
      required = FALSE
    )
  )
  run_args <- list(
    file_name = ellmer::type_string(
      description = paste0(
        "Script to run. Available: ", paste(script_files, collapse = ", ")
      )
    ),
    args = ellmer::type_array(
      items = ellmer::type_string(),
      description = "CLI arguments to pass to the script.",
      required = FALSE
    ),
    envs = ellmer::type_array(
      items = ellmer::type_string(),
      description = "Environment variables as KEY=VALUE strings.",
      required = FALSE
    )
  )

  # Build the generator function (closure factory)
  structure(
    function() {

      # Per-instance gate state, shared by both tools
      readme_unlocked <- FALSE
      skill_dir <- parsed$skill_dir

      # Run `f`; when it errors before the readme was read, point the AI
      # to the instructions
      with_gate <- function(f) {
        tryCatch(
          f(),
          error = function(e) {
            if (!readme_unlocked) {
              stop(
                conditionMessage(e),
                "\n\n---\nYou need to read the skill instructions with `",
                load_name, "` (action='readme') first.",
                "\n\n", condensed,
                call. = FALSE
              )
            }
            stop(e)
          }
        )
      }

      read_readme <- function() {
        readme_unlocked <<- TRUE
        info_parts <- parsed$body

        if (has_references) {
          info_parts <- c(info_parts, "",
            "## Available reference files",
            sprintf("Read them with `%s` (action='reference').", load_name),
            paste("-", ref_files)
          )
        }
        if (has_scripts) {
          info_parts <- c(info_parts, "",
            "## Available scripts",
            sprintf("Run them with `%s`.", run_name),
            paste("-", script_files)
          )
        }

        paste(info_parts, collapse = "\n")
      }

      read_reference <- function(file_name, pattern, line_start, n_lines) {
        if (!length(file_name) || !nzchar(file_name)) {
          stop("file_name is required for action='reference'. ",
               "Available: ", paste(ref_files, collapse = ", "),
               call. = FALSE)
        }
        # Fuzzy match: case-insensitive and supports "references/file"
        matched_file <- fuzzy_match_reference(file_name, ref_files)
        if (is.null(matched_file)) {
          stop("Reference file not found: ", file_name,
               "\nAvailable: ", paste(ref_files, collapse = ", "),
               call. = FALSE)
        }
        file_name <- matched_file

        ref_path <- file.path(skill_dir, file_name)
        all_lines <- readLines(ref_path, warn = FALSE)

        # Apply pattern filter if given
        if (length(pattern) && nzchar(pattern)) {
          matched <- grep(pattern, all_lines)
          if (!length(matched)) {
            return(paste0("No lines matching pattern '", pattern,
                          "' in ", file_name,
                          " (", length(all_lines), " total lines)"))
          }
          all_lines <- all_lines[matched]
        }

        # Paginate
        start <- max(1L, as.integer(line_start %||% 1L))
        max_n <- as.integer(n_lines %||% 200L)
        end <- min(length(all_lines), start + max_n - 1L)

        result_lines <- all_lines[start:end]
        header <- sprintf(
          "## %s (lines %d-%d of %d)\n",
          file_name, start, end, length(all_lines)
        )
        paste0(header, paste(result_lines, collapse = "\n"))
      }

      run_script <- function(file_name, args, envs) {
        if (!length(file_name) || !nzchar(file_name)) {
          stop("file_name is required. ",
               "Available: ", paste(script_files, collapse = ", "),
               call. = FALSE)
        }
        if (!file_name %in% script_files) {
          stop("Script not found: ", file_name,
               "\nAvailable: ", paste(script_files, collapse = ", "),
               call. = FALSE)
        }

        # Parse envs from KEY=VALUE strings to named character vector
        env_vec <- character()
        if (is.character(envs) && length(envs)) {
          # Split on first '=' only
          parts <- regmatches(envs, regexpr("=", envs), invert = TRUE)
          valid <- vapply(parts, length, integer(1L)) == 2L
          if (any(valid)) {
            keys <- vapply(parts[valid], `[[`, character(1L), 1L)
            vals <- vapply(parts[valid], `[[`, character(1L), 2L)
            env_vec <- structure(vals, names = keys)
          }
        } else if (is.list(envs) && length(envs)) {
          env_vec <- vapply(envs, as.character, character(1L))
        }

        result <- run_skill_script(
          skill_dir = skill_dir,
          file_name = file_name,
          args = as.character(args %||% character()),
          envs = env_vec,
          timeout_seconds = 60
        )

        # Format output
        parts <- character()
        if (nzchar(result$stdout)) {
          parts <- c(parts, "## stdout", result$stdout)
        }
        if (nzchar(result$stderr)) {
          parts <- c(parts, "## stderr", result$stderr)
        }
        parts <- c(parts, paste0("\nExit code: ", result$status))
        if (isTRUE(result$timeout)) {
          parts <- c(parts, "WARNING: Script timed out after 60 seconds.")
        }
        paste(parts, collapse = "\n")
      }

      load_fn <- function(action = "readme", file_name = NULL, pattern = NULL,
                          line_start = NULL, n_lines = NULL) {
        if (identical(action, "readme")) {
          return(read_readme())
        }
        with_gate(function() {
          switch(
            action,
            "reference" = read_reference(file_name, pattern, line_start,
                                         n_lines),
            stop("Unknown action: ", action,
                 "\nAvailable: ", paste(load_actions, collapse = ", "),
                 call. = FALSE)
          )
        })
      }

      run_fn <- function(file_name, args = NULL, envs = NULL) {
        if (missing(file_name)) {
          file_name <- NULL
        }
        with_gate(function() {
          run_script(file_name, args, envs)
        })
      }

      list(
        load = ellmer::tool(
          fun         = load_fn,
          name        = load_name,
          description = load_description,
          arguments   = load_args
        ),
        run = if (has_scripts) {
          ellmer::tool(
            fun         = run_fn,
            name        = run_name,
            description = run_description,
            arguments   = run_args
          )
        }
      )
    },
    class = c("shidashi_skill_wrapper", "function")
  )
}
