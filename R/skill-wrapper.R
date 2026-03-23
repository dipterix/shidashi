# ---- Skill wrapper for Phase 4 skills ----
#
# Turns an Anthropic-compliant skill directory (SKILL.md + optional
# scripts/ + reference files) into a single MCP tool via closure.
# Mirrors the mcp_wrapper() pattern from Phase 3 but with progressive
# disclosure and a gate mechanism.

#' Wrap a Skill Directory as an \verb{MCP} Tool Generator
#'
#' @description
#' Creates a closure that produces an
#' \code{ellmer::tool} dispatching on an \code{action} enumerator:
#' \describe{
#'   \item{\code{readme}}{Returns the full \verb{SKILL.md} instructions. Must be
#'     called first to unlock other actions.}
#'   \item{\code{reference}}{Returns content from a reference file in the
#'     skill directory (gated behind \code{readme}).}
#'   \item{\code{script}}{Executes a script in the \code{scripts/}
#'     subdirectory via \code{processx::run()} (gated behind \code{readme}).}
#' }
#'
#' @param skill_path Path to the skill directory containing \code{SKILL.md}.
#'   Can be absolute or relative to the project root.
#'
#' @return A function with class \code{c("shidashi_skill_wrapper", "function")}
#'   that returns an \code{ellmer::ToolDef} object.
#'
#' @details
#'   The returned tool enforces a soft gate: calling \code{reference} or
#'   \code{script} before \code{readme} is allowed, but if the call
#'   errors the message is augmented with a condensed summary (~200
#'   tokens) instructing the AI to read the full instructions first.
#'   This minimizes token waste (the summary is only sent on failure).
#'
#'   The gate state is per-instance: each call to the wrapper produces
#'   a closure with an independent \code{readme_unlocked} flag.
#'
#' @examples
#' skill_dir <- system.file(
#'   "builtin-templates/bslib-bare/agents/skills/greet",
#'   package = "shidashi"
#' )
#' wrapper  <- skill_wrapper(skill_dir)
#' tool_def <- wrapper()
#' cat(tool_def(action = "readme"))
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

  # Pre-build condensed summary for gate errors (use folder name)
  parsed$name <- canonical_name
  condensed <- build_condensed_summary(parsed, ref_files, script_files)

  # Determine available actions
  available_actions <- "readme"
  if (length(ref_files)) {
    available_actions <- c(available_actions, "reference")
  }
  if (length(script_files)) {
    available_actions <- c(available_actions, "script")
  }

  # Build short description for tools/list (Tier 1: ~30 tokens)
  tool_description <- paste0(
    parsed$description,
    " [Skill: call action='readme' first",
    if (length(script_files)) {
      paste0("; scripts: ", paste(script_files, collapse = ", "))
    },
    "]"
  )

  # Tool name derived from folder name (used as @name on the ToolDef)
  tool_name <- canonical_name

  # Build the argument schema — always include all params so formals match
  # (ellmer::tool requires arguments names to match function formals)
  has_references <- length(ref_files) > 0
  has_scripts <- length(script_files) > 0

  ref_desc <- if (has_references) {
    paste0("Available: ", paste(ref_files, collapse = ", "))
  } else {
    "No reference files available for this skill"
  }
  script_desc <- if (has_scripts) {
    paste0("Available: ", paste(script_files, collapse = ", "))
  } else {
    "No scripts available for this skill"
  }

  arg_list <- list(
    action = ellmer::type_enum(
      values = available_actions,
      description = paste0(
        "Action to perform. IMPORTANT: You must call 'readme' first before ",
        "any other action. Available: ",
        paste(available_actions, collapse = ", ")
      )
    ),
    file_name = ellmer::type_string(
      description = paste0(
        "File name for action='reference' or action='script'. ",
        "References: ", ref_desc, ". Scripts: ", script_desc
      ),
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
    ),
    args = ellmer::type_array(
      items = ellmer::type_string(),
      description = "For action='script': CLI arguments to pass to the script.",
      required = FALSE
    ),
    envs = ellmer::type_array(
      items = ellmer::type_string(),
      description = "For action='script': environment variables as KEY=VALUE strings.", # nolint: line_length_linter.
      required = FALSE
    )
  )

  # Build the generator function (closure factory)
  structure(
    function() {

      # Per-instance gate state
      readme_unlocked <- FALSE
      skill_dir <- parsed$skill_dir

      # The tool function that dispatches on action
      tool_fn <- function(action, file_name = NULL, pattern = NULL,
                          line_start = NULL, n_lines = NULL,
                          args = NULL, envs = NULL) {

        # ---- Wrap dispatch: augment errors when readme not yet read ----
        result <- tryCatch(
          {
            # ---- Dispatch ----
            switch(
          action,
          "readme" = {
            readme_unlocked <<- TRUE
            # Build runtime context
            info_parts <- character()
            info_parts <- c(info_parts, parsed$body)

            if (length(ref_files)) {
              info_parts <- c(info_parts, "",
                "## Available reference files",
                paste("-", ref_files)
              )
            }
            if (length(script_files)) {
              info_parts <- c(info_parts, "",
                "## Available scripts",
                paste("-", script_files)
              )
            }

            paste(info_parts, collapse = "\n")
          },

          "reference" = {
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
          },

          "script" = {
            if (!length(file_name) || !nzchar(file_name)) {
              stop("file_name is required for action='script'. ",
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
          },

          stop("Unknown action: ", action,
               "\nAvailable: ", paste(available_actions, collapse = ", "),
               call. = FALSE)
            )
          },
          error = function(e) {
            if (!readme_unlocked && action != "readme") {
              stop(
                conditionMessage(e),
                "\n\n---\nYou need to read the skill instructions with ",
                "action='readme' first.",
                "\n\n", condensed,
                call. = FALSE
              )
            }
            stop(e)
          }
        )
        result
      }

      # Return an ellmer::tool with the skill's metadata
      ellmer::tool(
        fun         = tool_fn,
        name        = tool_name,
        description = tool_description,
        arguments   = arg_list
      )
    },
    class = c("shidashi_skill_wrapper", "function")
  )
}
