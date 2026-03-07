# ---- Skill script execution for Phase 4 skills ----
#
# Resolves interpreters and executes scripts via processx::run().
# Interpreter resolution: config.yaml -> interpreters -> built-in defaults.

#' Execute a skill script via processx
#'
#' Runs a script in the skill's \code{scripts/} directory. The interpreter
#' is resolved from:
#' \enumerate{
#'   \item Template-level \code{config.yaml -> interpreters} (when a Shiny
#'     session is active; see \code{template_root()}).
#'   \item Built-in defaults: \code{.R} -> \code{Rscript} (portable),
#'     \code{.sh} -> \code{/bin/sh} (non-Windows only),
#'     \code{.sh.bat} -> \code{cmd.exe /c} on Windows or \code{/bin/sh}
#'     elsewhere (dual-mode scripts that work on both platforms).
#' }
#' All other extensions require explicit \code{config.yaml} configuration.
#'
#' @param skill_dir Absolute path to the skill directory.
#' @param file_name Script filename (relative to \code{scripts/}).
#' @param args Character vector of CLI arguments.
#' @param envs Named character vector of environment variables.
#' @param timeout_seconds Timeout in seconds (default 60).
#' @return A list with \code{stdout}, \code{stderr}, \code{status} (exit code),
#'   and \code{timeout} (logical).
#' @keywords internal
#' @noRd
run_skill_script <- function(skill_dir, file_name, args = character(),
                             envs = character(), timeout_seconds = 60) {
  if (!requireNamespace("processx", quietly = TRUE)) {
    stop("Package 'processx' is required to run skill scripts. ",
         "Try other approaches or stop, and ",
         "tell user to install `processx` by themselves.")
  }

  script_path <- file.path(skill_dir, "scripts", file_name)
  if (!file.exists(script_path)) {
    stop("Script not found: ", file_name,
         "\nAvailable scripts: ",
         paste(discover_scripts(skill_dir), collapse = ", "))
  }
  script_path <- normalizePath(script_path, mustWork = TRUE)
  script_path <- gsub("[/|\\\\]+", "/", script_path)

  # ---- Resolve interpreter ----
  # Detect compound extension .sh.bat before simple extension
  is_sh_bat <- grepl("\\.sh\\.bat$", tolower(file_name))
  ext <- if (is_sh_bat) "sh.bat" else tolower(tools::file_ext(file_name))
  interpreter <- NULL

  # 1. Template config.yaml -> interpreters (when Shiny is running)
  session <- tryCatch(shiny::getDefaultReactiveDomain(),
                      error = function(e) NULL)
  if (!is.null(session)) {
    root <- tryCatch(template_root(), error = function(e) NULL)
    if (!is.null(root)) {
      config_path <- file.path(root, "config.yaml")
      if (file.exists(config_path)) {
        config <- tryCatch(yaml::read_yaml(config_path),
                           error = function(e) NULL)
        if (is.list(config) && length(config$interpreters)) {
          val <- config$interpreters[[ext]]
          if (is.character(val) && length(val)) {
            interpreter <- val
          }
        }
      }
    }
  }

  # 2. Built-in defaults
  if (is.null(interpreter)) {
    interpreter <- switch(
      ext,
      "r" = {
        rscript <- file.path(R.home("bin"),
                             if (.Platform$OS.type == "windows") "Rscript.exe"
                             else "Rscript")
        if (!file.exists(rscript)) rscript <- "Rscript"
        rscript
      },
      "sh" = {
        if (.Platform$OS.type == "windows") {
          stop("Shell scripts (.sh) are not supported on Windows. ",
               "Configure an interpreter in config.yaml -> interpreters -> sh, ",
               "or use a .sh.bat dual-mode script instead.")
        }
        "/bin/sh"
      },
      "sh.bat" = {
        if (.Platform$OS.type == "windows") {
          c("cmd.exe", "/c")
        } else {
          "/bin/sh"
        }
      },
      stop("No interpreter configured for extension '.", ext, "'.\n",
           "Add it to config.yaml under `interpreters:\n  ",
           ext, ": <command>`")
    )
  }

  # ---- Build and run command ----
  command <- interpreter[[1L]]
  cmd_args <- c(interpreter[-1L], script_path, as.character(args))

  env_vars <- NULL
  if (length(envs) && !is.null(names(envs))) {
    env_vars <- envs
  }

  result <- processx::run(
    command = command,
    args    = cmd_args,
    env     = env_vars,
    # TODO: check this against skill specs
    wd      = skill_dir,
    timeout = timeout_seconds,
    error_on_status = FALSE
  )

  list(
    stdout  = result$stdout,
    stderr  = result$stderr,
    status  = result$status,
    timeout = result$timeout
  )
}
