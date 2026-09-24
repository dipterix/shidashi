#' Save and start 'shidashi' apps for AI agents
#'
#' @description
#' \code{save_launcher} saves how to start a 'shidashi' app, so that an AI
#' agent connected through the \verb{MCP} proxy can list it and, after asking
#' the user, start it and open one of its modules in the browser. Nothing is
#' started automatically: the agent only launches a saved app when the user
#' picks it.
#'
#' \code{run_launcher} starts a saved app. The \verb{MCP} proxy calls it when
#' the agent launches an app; it can also be called from R.
#'
#' @details
#' All launchers are kept in one file, \file{launchers.json}, in the
#' 'shidashi' cache folder (\code{tools::R_user_dir("shidashi", "cache")}).
#' Saving again with the same \code{id} replaces that launcher. Saving a
#' launcher also installs or updates the \verb{MCP} proxy script.
#'
#' With \code{copy_app = TRUE}, the app folder is copied to
#' \file{saved_apps/<id>/} in the cache folder (without \file{.git} and
#' \file{node_modules}), and the launcher starts the copy. The folder is
#' cleared before each copy. Without \code{copy_app}, a copy left from an
#' earlier save of the same \code{id} is removed.
#'
#' @param id a short name for the app, made of letters, digits, \code{"-"},
#'   and \code{"_"}. The agent and the user refer to the app by this name.
#' @param root_path the app directory; it must contain \file{modules.yaml}
#' @param host the host to listen on
#' @param port the port to listen on; \code{NA} picks a free port at launch
#' @param modules the module identifiers the agent may open; default is the
#'   modules that have AI agents enabled (an \file{agents.yaml} file)
#' @param description a short description shown to the agent
#' @param prelaunch optional R code, as a character string, to run before
#'   the app starts
#' @param copy_app whether to start a copy of the app, kept in the cache
#'   folder, instead of the app directory itself
#' @param ... for \code{save_launcher}, named metadata about the app
#'   (character, numeric, or logical values), shown to the agent but not
#'   used to start the app; for \code{run_launcher}, extra arguments passed
#'   to \code{\link{render}}, which override the defaults
#'   (\code{launch_browser = FALSE}, \code{as_job = FALSE})
#' @returns \code{save_launcher} returns the saved launcher, invisibly.
#'   \code{run_launcher} runs the app; see \code{\link{render}}.
#'
#' @examples
#'
#' # This example saves into a temporary folder; by default launchers are
#' # saved in the user's cache folder
#' old_opt <- options(shidashi.cache_dir = tempfile())
#'
#' root <- system.file("builtin-templates", "bslib-bare", package = "shidashi")
#' save_launcher(
#'   "demo-app", root,
#'   description = "Demo dashboard shipped with shidashi",
#'   lab = "example"
#' )
#'
#' if (interactive()) {
#'   run_launcher("demo-app", launch_browser = TRUE)
#' }
#'
#' options(old_opt)
#'
#' @export
save_launcher <- function(id, root_path, host = "127.0.0.1", port = NA,
                          modules = NULL, description = "", prelaunch = NULL,
                          copy_app = FALSE, ...) {
  check_launcher_id(id)

  if (!is.character(root_path) || length(root_path) != 1L ||
      is.na(root_path) || !nzchar(root_path)) {
    stop("`root_path` must be the app directory.")
  }
  if (!file.exists(file.path(root_path, "modules.yaml"))) {
    stop("`root_path` must be a shidashi app directory containing ",
         "modules.yaml: ", root_path)
  }
  root_path <- normalizePath(root_path, winslash = "/", mustWork = TRUE)

  all_modules <- module_info(root_path = root_path)$id
  if (is.null(modules)) {
    modules <- mcp_agent_modules(root_path = root_path)
  }
  modules <- as.character(unlist(modules))
  unknown_modules <- setdiff(modules, all_modules)
  if (length(unknown_modules)) {
    stop("Unknown modules: ", paste(unknown_modules, collapse = ", "),
         ". Modules in modules.yaml: ", paste(all_modules, collapse = ", "),
         ".")
  }

  if (!is.character(host) || length(host) != 1L || is.na(host) ||
      !nzchar(host)) {
    stop("`host` must be a single host name or address.")
  }

  if (length(port) != 1L ||
      (!is.na(port) && (!is.numeric(port) || port < 1 || port > 65535 ||
                        port != round(port)))) {
    stop("`port` must be `NA` (pick a port at launch) or a port number ",
         "between 1 and 65535.")
  }

  if (!is.null(prelaunch)) {
    prelaunch <- paste(as.character(prelaunch), collapse = "\n")
    parsed <- tryCatch(parse(text = prelaunch), error = function(e) e)
    if (inherits(parsed, "error")) {
      stop("`prelaunch` is not valid R code: ", conditionMessage(parsed))
    }
  }

  metadata <- check_launcher_metadata(list(...))

  # Checks are done; now touch the disk
  copy_dir <- file.path(shidashi_cache_dir(), "saved_apps", id)
  if (isTRUE(copy_app)) {
    copy_app_dir(root_path, copy_dir)
    root_path <- normalizePath(copy_dir, winslash = "/", mustWork = TRUE)
  } else if (dir.exists(copy_dir) && !path_is_within(root_path, copy_dir)) {
    unlink(copy_dir, recursive = TRUE)
  }

  entry <- list(
    root_path   = root_path,
    host        = host,
    port        = if (!is.na(port)) as.integer(port),
    modules     = as.list(modules),
    description = paste(as.character(description), collapse = "\n"),
    prelaunch   = prelaunch,
    metadata    = metadata,
    copied      = isTRUE(copy_app),
    rscript     = file.path(
      R.home("bin"),
      if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    ),
    saved       = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  )

  launchers <- read_launchers()
  launchers[[id]] <- entry
  write_launchers(launchers)
  setup_mcp_proxy(verbose = FALSE)

  invisible(entry)
}

#' @rdname save_launcher
#' @export
run_launcher <- function(id, ...) {
  check_launcher_id(id)
  launchers <- read_launchers()
  launcher <- launchers[[id]]
  if (is.null(launcher)) {
    saved <- if (length(launchers)) {
      paste(names(launchers), collapse = ", ")
    } else {
      "none"
    }
    stop("There is no saved launcher `", id, "`. Saved launchers: ", saved, ".")
  }

  extra <- list(...)
  if (length(extra) &&
      (is.null(names(extra)) || !all(nzchar(names(extra))))) {
    stop("Extra arguments to `run_launcher()` must be named; they are ",
         "passed to `render()`.")
  }

  prelaunch <- NULL
  if (length(launcher$prelaunch) == 1L && nzchar(launcher$prelaunch)) {
    prelaunch <- parse(text = launcher$prelaunch)
  }

  args <- list(
    root_path        = launcher$root_path,
    host             = launcher$host %||% "127.0.0.1",
    prelaunch        = prelaunch,
    prelaunch_quoted = TRUE,
    launch_browser   = FALSE,
    as_job           = FALSE
  )
  if (length(launcher$port) == 1L && !is.na(launcher$port)) {
    args$port <- as.integer(launcher$port)
  }
  nms <- names(extra)
  nms <- nms[!nms %in% c("root_path", "host", "prelaunch", "prelaunch_quoted")]
  if (length(nms)) {
    args[nms] <- extra[nms]
  }
  do.call(render, args)
}

# ---- helpers --------------------------------------------------------------

# Where all launchers are saved
launchers_path <- function() {
  file.path(shidashi_cache_dir(), "launchers.json")
}

# All saved launchers, as a named list keyed by id
read_launchers <- function() {
  path <- launchers_path()
  if (!file.exists(path)) {
    return(structure(list(), names = character(0)))
  }
  launchers <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!length(launchers)) {
    return(structure(list(), names = character(0)))
  }
  launchers
}

write_launchers <- function(launchers) {
  path <- launchers_path()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    jsonlite::toJSON(launchers, auto_unbox = TRUE, null = "null",
                     pretty = TRUE),
    path
  )
  invisible(path)
}

check_launcher_id <- function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) ||
      !grepl("^[A-Za-z0-9_-]+$", id)) {
    stop("`id` must be a single name made of letters, digits, `-`, or `_`.")
  }
  invisible(id)
}

# Metadata from `...`: named, plain values that JSON can hold
check_launcher_metadata <- function(metadata) {
  if (!length(metadata)) {
    return(structure(list(), names = character(0)))
  }
  metadata_names <- names(metadata)
  if (is.null(metadata_names) || !all(nzchar(metadata_names)) ||
      anyDuplicated(metadata_names)) {
    stop("Extra arguments to `save_launcher()` are metadata and must be ",
         "named, with unique names.")
  }
  plain <- vapply(metadata, function(value) {
    is.null(value) ||
      (!is.object(value) &&
         (is.character(value) || is.numeric(value) || is.logical(value)))
  }, FALSE)
  if (!all(plain)) {
    stop("Metadata must be plain character, numeric, or logical values: ",
         paste(metadata_names[!plain], collapse = ", "), ".")
  }
  metadata
}

# Whether `path` is `dir` or lies inside it
path_is_within <- function(path, dir) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  dir <- normalizePath(dir, winslash = "/", mustWork = FALSE)
  identical(path, dir) || startsWith(path, paste0(dir, "/"))
}

# Copy an app folder to `to`, without `.git` and `node_modules`. The copy is
# made in a temporary folder first, so `from` may be `to` itself.
copy_app_dir <- function(from, to) {
  staging <- tempfile("shidashi-app-copy-")
  dir.create(staging, recursive = TRUE)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)

  entries <- list.files(from, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  entries <- entries[!basename(entries) %in% c(".git", "node_modules")]
  copied <- file.copy(entries, staging, recursive = TRUE, copy.date = TRUE)
  if (!all(copied)) {
    stop("Cannot copy the app to the cache folder: ",
         paste(basename(entries[!copied]), collapse = ", "))
  }

  unlink(to, recursive = TRUE)
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  staged <- list.files(staging, all.files = TRUE, no.. = TRUE,
                       full.names = TRUE)
  moved <- file.copy(staged, to, recursive = TRUE, copy.date = TRUE)
  if (!all(moved)) {
    stop("Cannot copy the app to ", to)
  }
  invisible(to)
}
