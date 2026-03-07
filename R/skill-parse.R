# ---- Skill directory parsing for Phase 4 skills ----
#
# Parses Anthropic-compliant SKILL.md files and discovers companion
# reference/script assets in the skill directory.

#' Sanitize a skill name for use as an MCP tool identifier
#'
#' Converts a human-readable skill name to a valid identifier: lowercase,
#' non-alphanumeric characters replaced with underscores, leading/trailing
#' underscores stripped, consecutive underscores collapsed.
#'
#' @param name Character string; the skill name from SKILL.md frontmatter
#'   or directory name.
#' @return A single sanitized string suitable for tool naming.
#' @keywords internal
#' @noRd
sanitize_skill_name <- function(name) {
  name <- tolower(trimws(name))
  name <- gsub("[^a-z0-9]+", "_", name)
  name <- gsub("^_+|_+$", "", name)
  name <- gsub("_+", "_", name)
  if (!nzchar(name)) {
    stop("Skill name is empty after sanitization")
  }
  name
}


#' Parse a SKILL.md file
#'
#' Reads the YAML frontmatter and markdown body from an Anthropic-compliant
#' SKILL.md file.
#'
#' @param skill_md_path Absolute path to the SKILL.md file.
#' @return A named list with:
#'   \describe{
#'     \item{name}{Character; skill name (from frontmatter or dir name)}
#'     \item{description}{Character; one-line description from frontmatter}
#'     \item{body}{Character; full markdown body (instructions) after frontmatter}
#'     \item{frontmatter}{List; all parsed frontmatter fields}
#'     \item{skill_dir}{Character; absolute path to the skill directory}
#'   }
#' @keywords internal
#' @noRd
parse_skill_md <- function(skill_md_path) {
  skill_md_path <- normalizePath(skill_md_path, mustWork = TRUE)
  skill_dir <- dirname(skill_md_path)

  lines <- readLines(skill_md_path, warn = FALSE)

  # Parse YAML frontmatter (between --- delimiters)
  frontmatter <- list()
  body_start <- 1L

  if (length(lines) >= 3L && trimws(lines[[1L]]) == "---") {
    # Find closing ---
    end_idx <- which(trimws(lines[-1L]) == "---")
    if (length(end_idx)) {
      end_idx <- end_idx[[1L]] + 1L  # adjust for skipping line 1
      fm_text <- paste(lines[2L:(end_idx - 1L)], collapse = "\n")
      frontmatter <- tryCatch(
        yaml::read_yaml(text = fm_text),
        error = function(e) {
          warning("Failed to parse SKILL.md frontmatter: ",
                  conditionMessage(e))
          list()
        }
      )
      body_start <- end_idx + 1L
    }
  }

  # Body is everything after frontmatter
  body <- ""
  if (body_start <= length(lines)) {
    body <- trimws(paste(lines[body_start:length(lines)], collapse = "\n"))
  }

  # Name: frontmatter > directory name
  name <- frontmatter$name
  if (!length(name) || !nzchar(trimws(name))) {
    name <- basename(skill_dir)
  }

  # Description: frontmatter or first non-empty line of body
  description <- frontmatter$description
  if (!length(description) || !nzchar(trimws(description))) {
    non_empty <- lines[body_start:length(lines)]
    non_empty <- non_empty[nzchar(trimws(non_empty))]
    description <- if (length(non_empty)) {
      # Strip leading markdown heading markers
      sub("^#+\\s*", "", non_empty[[1L]])
    } else {
      paste("Skill:", name)
    }
  }

  list(
    name        = trimws(name),
    description = trimws(description),
    body        = body,
    frontmatter = frontmatter,
    skill_dir   = skill_dir
  )
}


#' Discover reference files in a skill directory
#'
#' Looks for markdown, text, and data files outside of \code{scripts/}.
#'
#' @param skill_dir Absolute path to the skill directory.
#' @return Character vector of file paths relative to skill_dir, or
#'   \code{character(0)} if none found.
#' @keywords internal
#' @noRd
discover_references <- function(skill_dir) {
  all_files <- list.files(
    skill_dir,
    recursive = TRUE,
    full.names = FALSE,
    include.dirs = FALSE,
    no.. = TRUE
  )
  # Exclude SKILL.md itself and scripts/ directory
  all_files <- all_files[!grepl("^SKILL\\.md$", all_files, ignore.case = TRUE)]
  all_files <- all_files[!grepl("^scripts/", all_files, ignore.case = TRUE)]

  # Keep reference-like extensions
  ref_exts <- "\\.(md|txt|csv|json|yaml|yml|html|xml|r|R|py|sql)$"
  all_files[grepl(ref_exts, all_files)]
}


#' Discover executable scripts in a skill directory
#'
#' Looks for files under the \code{scripts/} subdirectory.
#'
#' @param skill_dir Absolute path to the skill directory.
#' @return Character vector of file names relative to \code{scripts/}, or
#'   \code{character(0)} if none found.
#' @keywords internal
#' @noRd
discover_scripts <- function(skill_dir) {
  scripts_dir <- file.path(skill_dir, "scripts")
  if (!dir.exists(scripts_dir)) {
    return(character(0L))
  }
  list.files(
    scripts_dir,
    recursive = FALSE,
    full.names = FALSE,
    include.dirs = FALSE,
    no.. = TRUE
  )
}


#' Build condensed summary for gate error messages
#'
#' Auto-generates a short summary (~150-200 tokens) from skill metadata,
#' suitable for embedding in a gate rejection error.
#'
#' @param parsed Output of \code{parse_skill_md()}.
#' @param ref_files Character vector from \code{discover_references()}.
#' @param script_files Character vector from \code{discover_scripts()}.
#' @return A single character string with the condensed summary.
#' @keywords internal
#' @noRd
build_condensed_summary <- function(parsed, ref_files, script_files) {
  parts <- character()

  parts <- c(parts, paste0("## ", parsed$name))
  parts <- c(parts, parsed$description)
  parts <- c(parts, "")

  if (length(script_files)) {
    parts <- c(parts, paste0(
      "Available scripts: ",
      paste(script_files, collapse = ", ")
    ))
  }

  if (length(ref_files)) {
    parts <- c(parts, paste0(
      "Reference files: ",
      paste(ref_files, collapse = ", ")
    ))
  }

  parts <- c(parts, "")
  parts <- c(parts, "You MUST call action='readme' first to read the full instructions, then retry your intended action.")

  paste(parts, collapse = "\n")
}
