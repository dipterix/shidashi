#' Wrap an \verb{MCP} Tool Generator Function
#'
#' @description
#' Creates a wrapper around a generator function to ensure it returns valid
#' Model Context Protocol (\verb{MCP}) tool definitions. The wrapper validates
#' input and filters output to contain only \code{'ellmer::ToolDef'} objects.
#'
#' @param generator A function that accepts a `session` parameter and returns
#'   either a single tool object or a list/vector of such objects; see
#'   \code{\link[ellmer]{tool}}.
#'
#' @return A wrapped function with class \code{'shidashi_mcp_wrapper'} that:
#'   - Accepts a `session` parameter
#'   - Calls the generator function with the session
#'   - Normalizes the output to a list
#'   - Filters to keep only valid tool objects
#'   - Returns a list of tool objects (possibly empty)
#'
#' @details
#'   The wrapper performs the following validations:
#'   - Ensures `generator` is a function
#'   - Checks that `generator` accepts a `session` parameter
#'
#'   The returned function automatically handles both single tool definitions
#'   and lists of tools, providing a consistent interface for \verb{MCP} tool
#'   registration.
#'
#' @examples
#' # Define a generator function that returns tool definitions
#' my_tool_generator <- function(session) {
#'   # Define MCP tools using ellmer package
#'
#'   tool_rnorm <- tool(
#'     function(n, mean = 0, sd = 1) {
#'       shiny::updateNumericInput(session, "rnorm", value = rnorm)
#'     },
#'     description = "Draw numbers from a random normal distribution",
#'     arguments = list(
#'       n = type_integer("The number of observations. Must be positive"),
#'       mean = type_number("The mean value of the distribution."),
#'       sd = type_number("The standard deviation of the distribution.")
#'     )
#'   )
#'
#'   # or `list(tool_rnorm)`
#'   tool_rnorm
#' }
#'
#' # Wrap the generator
#' wrapped_generator <- mcp_wrapper(my_tool_generator)
#'
#' @export
mcp_wrapper <- function(generator) {
  stopifnot(
    "generator must be a function" = is.function(generator),
    "generator must accept an arguments: session" =
      "session" %in% names(formals(generator))
  )
  structure(
    function(session) {
      # TODO: should we consider wraping with try-catch warning
      res <- generator(session = session)
      if (inherits(res, "ellmer::ToolDef")) {
        res <- list(res)
      } else {
        res <- as.list(res)
      }
      res <- res[vapply(res, function(tool) { inherits(tool, "ellmer::ToolDef") }, FALSE)]
      res
    },
    class = c("shidashi_mcp_wrapper", "function")
  )
}

setup_mcp_proxy <- function(port = NULL, overwrite = TRUE, verbose = TRUE) {
  src <- system.file("mcp-proxy", "shidashi-proxy.mjs", package = "shidashi")
  if (!nzchar(src)) {
    return(invisible(NULL))
  }

  mcp_server_dir <- file.path(tools::R_user_dir("shidashi", "cache"), "mcp_server")
  ports_dir <- file.path(mcp_server_dir, "ports")
  dir.create(ports_dir, recursive = TRUE, showWarnings = FALSE)

  # Write port record when a port is supplied.
  if (!is.null(port)) {
    port_file <- file.path(
      ports_dir,
      paste0(format(as.numeric(Sys.time()) * 1000, scientific = FALSE, digits = 15), ".json")
    )
    writeLines(
      paste0('{"port":', as.integer(port), ',"created":"',
             format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), '"}'),
      port_file
    )
    # Prune: keep only the 10 most-recent port records.
    port_files <- sort(list.files(ports_dir, pattern = "\\.json$", full.names = TRUE))
    if (length(port_files) > 10L) {
      file.remove(port_files[seq_len(length(port_files) - 10L)])
    }
  }

  # Copy proxy script to user cache.
  dest <- file.path(mcp_server_dir, "mcp-proxy.mjs")
  if (!file.exists(dest) || isTRUE(overwrite)) {
    file.copy(src, dest, overwrite = TRUE)
    if (verbose) message("Installed MCP proxy to:\n  ", dest)
  } else {
    if (verbose) message("MCP proxy already exists (overwrite = FALSE):\n  ", dest)
  }

  if (verbose) {
    snippet <- paste0(
      '{\n',
      '  "servers": {\n',
      '    "shidashi": {\n',
      '      "type": "stdio",\n',
      '      "command": "node",\n',
      '      "args": ["', dest, '"]\n',
      '    }\n',
      '  }\n',
      '}'
    )
    message(
      "\nPaste the following into your .vscode/mcp.json",
      " (or equivalent MCP settings):\n\n",
      snippet,
      "\n\nTo target a specific shidashi session, append its port as an extra arg:\n",
      '  "args": ["', dest, '", "<port>"]\n'
    )
  }

  invisible(dest)
}
