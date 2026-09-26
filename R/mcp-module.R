# ---- MCP: choosing the open module a tool call runs in ----
#
# An "open module" is a live Shiny session that runs a module (a module
# iframe or a standalone `?module=` page). The dashboard shell page (empty
# namespace) is not one. Every MCP tool call chooses its open module
# independently:
#
#   candidates = open modules
#                -> restricted by the URL module (`/mcp/{app_id}/{module}`)
#                -> restricted to sessions that offer the tool
#                -> restricted by the `_module` argument
#   winner     = pinned, then most recently used, then most recently opened
#
# Nothing about the agent connection is remembered between calls.

# All open modules, each as a list with token, handle, module_id, entry.
# The handle is always `<module id>@<token prefix>`, so it stays the same
# when the user opens the module again in another tab.
mcp_open_modules <- function() {
  registry <- globals_session_registry()
  entries <- lapply(registry$keys(), get_session_entry)
  entries <- Filter(function(entry) {
    length(entry) && length(entry$namespace) == 1L &&
      is.character(entry$namespace) && nzchar(entry$namespace)
  }, entries)
  if (!length(entries)) {
    return(list())
  }

  module_ids <- vapply(entries, function(entry) entry$namespace, "")
  tokens <- vapply(entries, function(entry) entry$shiny_session$token, "")
  handles <- paste0(module_ids, "@", substr(tokens, 1L, 6L))

  lapply(seq_along(entries), function(ii) {
    list(
      token     = tokens[[ii]],
      handle    = handles[[ii]],
      module_id = module_ids[[ii]],
      entry     = entries[[ii]]
    )
  })
}

# Keep open modules matching `spec`: an exact handle or token first, then a
# token prefix, then a module id.
mcp_match_modules <- function(open_modules, spec) {
  if (length(spec) != 1L || is.na(spec) || !nzchar(spec)) {
    return(open_modules)
  }
  spec <- as.character(spec)
  handles <- vapply(open_modules, `[[`, "", "handle")
  tokens <- vapply(open_modules, `[[`, "", "token")
  module_ids <- vapply(open_modules, `[[`, "", "module_id")

  sel <- handles == spec | tokens == spec
  if (!any(sel)) {
    sel <- startsWith(tokens, spec)
  }
  if (!any(sel)) {
    sel <- module_ids == spec
  }
  open_modules[sel]
}

# Sort open modules best-first: pinned, then last used, then last opened
mcp_rank_modules <- function(open_modules) {
  if (length(open_modules) < 2L) {
    return(open_modules)
  }
  time_or_neg_inf <- function(value) {
    if (length(value) == 1L && inherits(value, "POSIXct")) {
      as.numeric(value)
    } else {
      -Inf
    }
  }
  pinned <- vapply(open_modules, function(open_module) {
    isTRUE(open_module$entry$activity$pinned)
  }, FALSE)
  focused <- vapply(open_modules, function(open_module) {
    time_or_neg_inf(open_module$entry$activity$focused_at)
  }, 0)
  opened <- vapply(open_modules, function(open_module) {
    time_or_neg_inf(open_module$entry$registered_at)
  }, 0)
  open_modules[order(pinned, focused, opened, decreasing = TRUE)]
}

# Why the top-ranked open module won
mcp_module_reason <- function(open_module) {
  activity <- open_module$entry$activity
  if (isTRUE(activity$pinned)) {
    return("pinned")
  }
  if (inherits(activity$focused_at, "POSIXct")) {
    return("last used")
  }
  "most recently opened"
}

#' Choose the open module a tool call runs in
#' @param tool_name live tool name to look up in `entry$tools`, or `NULL` to
#'   accept any open module
#' @param module the `_module` argument from the agent, or `NULL`
#' @param scope_module the module from the URL path, or `NULL`
#' @param providers module ids known to provide the tool; used only to write
#'   a helpful message when nothing is open
#' @param only_modules module ids the call may run in, or `NULL` for any;
#'   used for module-qualified tools (`tool__<module>__<name>`)
#' @return On success, `list(ok = TRUE, token, handle, module_id, reason,
#'   entry, default_handle, default_reason)`, where the defaults describe
#'   the module the call would use without `module`. Otherwise
#'   `list(ok = FALSE, message)`.
#' @noRd
mcp_resolve_module <- function(tool_name = NULL, module = NULL,
                               scope_module = NULL, providers = NULL,
                               only_modules = NULL) {
  all_open <- mcp_open_modules()
  candidates <- mcp_match_modules(all_open, scope_module)
  if (length(only_modules)) {
    candidates <- Filter(function(candidate) {
      candidate$module_id %in% only_modules
    }, candidates)
  }

  if (length(tool_name)) {
    candidates <- Filter(function(candidate) {
      candidate$entry$tools$has(tool_name)
    }, candidates)
  }
  offering <- candidates

  requested <- length(module) == 1L && !is.na(module) && nzchar(module)
  candidates <- mcp_match_modules(candidates, module)

  if (!length(candidates)) {
    return(list(ok = FALSE, message = mcp_no_module_message(
      tool_name = tool_name,
      module = if (requested) module else scope_module,
      offering = offering,
      all_open = all_open,
      providers = providers
    )))
  }

  best <- mcp_rank_modules(candidates)[[1L]]
  # The module this call would use without `module`: the current one
  current <- mcp_rank_modules(offering)[[1L]]
  list(
    ok             = TRUE,
    token          = best$token,
    handle         = best$handle,
    module_id      = best$module_id,
    reason         = if (requested) "requested" else mcp_module_reason(best),
    entry          = best$entry,
    default_handle = current$handle,
    default_reason = mcp_module_reason(current)
  )
}

mcp_no_module_message <- function(tool_name, module, offering, all_open,
                                  providers) {
  quote_list <- function(x) {
    paste(sprintf("`%s`", x), collapse = ", ")
  }
  tool_text <- if (length(tool_name)) sprintf("`%s`", tool_name) else "tools"

  if (length(module) == 1L && nzchar(module) && length(offering)) {
    return(sprintf(
      "No open dashboard module matches `%s`. Open modules that offer %s: %s.",
      module, tool_text, quote_list(vapply(offering, `[[`, "", "handle"))
    ))
  }

  # if (length(providers)) {
  #   open_hint <- sprintf(
  #     "Ask the user to open one of these modules in the dashboard: %s.",
  #     quote_list(providers)
  #   )
  # } else {
  #   open_hint <- "Ask the user to open a dashboard module that provides it."
  # }
  open_hint <- "Are you sure the MCP call is correct?"
  if (length(module) == 1L && nzchar(module)) {
    return(sprintf(
      "No open dashboard module matches `%s` and offers %s. %s",
      module, tool_text, open_hint
    ))
  }
  if (!length(all_open)) {
    return(sprintf("No dashboard module is open. %s", open_hint))
  }
  sprintf("No open dashboard module offers %s. %s", tool_text, open_hint)
}

# Pin (or unpin) a session as the module for agent tool calls. At most one
# session per app is pinned; the browser toggles are kept in sync.
mcp_set_pin <- function(token, pinned = TRUE) {
  pinned <- isTRUE(pinned)
  entry <- get_session_entry(token)
  if (!is.environment(entry$activity)) {
    return(invisible(FALSE))
  }
  if (pinned) {
    for (other_token in globals_session_registry()$keys()) {
      if (identical(other_token, token)) next
      other <- get_session_entry(other_token)
      if (is.environment(other$activity) && isTRUE(other$activity$pinned)) {
        other$activity$pinned <- FALSE
        other$shiny_session$sendCustomMessage(
          "shidashi.ai_pin_state", list(pinned = FALSE)
        )
      }
    }
  }
  entry$activity$pinned <- pinned
  entry$shiny_session$sendCustomMessage(
    "shidashi.ai_pin_state", list(pinned = pinned)
  )
  invisible(TRUE)
}
