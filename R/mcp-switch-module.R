# ---- MCP: the `switch_module` meta tool ----
#
# Shows a module in the user's dashboard, as clicking it in the sidebar
# does: the dashboard brings the module's tab to the front, or opens one.
# The request goes to one browser page: the open module page the user used
# last, whose dashboard (the parent frame) switches tabs; or, with no module
# page open, the dashboard page opened last. The page answers through the
# `@shidashi_switch_module@` input. The call then waits until the module's
# page reports that the user sees it, so the next tool call runs there.
# Refused while the user has pinned a module: tool calls must stay there.

mcp_switch_module_input <- "@shidashi_switch_module@"

# Resolve with the first non-NULL value of `check()`, polled every
# `interval` seconds, or with NULL after `timeout` seconds. An error in
# `check()` rejects: it must not surface in the event loop.
mcp_poll <- function(check, timeout, interval = 0.2) {
  promises::promise(function(resolve, reject) {
    deadline <- Sys.time() + timeout
    poll <- function() {
      tryCatch({
        value <- check()
        if (!is.null(value)) {
          resolve(value)
        } else if (Sys.time() >= deadline) {
          resolve(NULL)
        } else {
          later::later(poll, delay = interval)
        }
      }, error = function(e) {
        reject(e)
      })
    }
    poll()
  })
}

# Modules with a link in the dashboard's sidebar: the `modules.yaml` entries
# that are not `hidden` (as in adminlte_sidebar()). `module_info()` drops
# `hidden`, so the file is read here. A data frame with `id` and `label`.
mcp_sidebar_modules <- function(root_path = template_root()) {
  settings <- yaml::read_yaml(file.path(root_path, "modules.yaml"))
  modules <- settings$modules
  modules <- modules[!vapply(modules, function(x) isTRUE(x$hidden), FALSE)]
  if (!length(modules)) {
    return(data.frame(id = character(0), label = character(0)))
  }
  data.frame(
    id = names(modules),
    label = vapply(modules, function(x) {
      label <- x$label
      if (length(label) == 1L && !is.na(label)) as.character(label) else ""
    }, ""),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# The dashboard page (a live session without a module) that registered
# last, as a registry entry, or NULL. A page whose URL names a module is a
# module page that has not registered its module yet.
mcp_latest_dashboard <- function() {
  entries <- lapply(globals_session_registry()$keys(), get_session_entry)
  entries <- Filter(function(entry) {
    if (!length(entry)) { return(FALSE) }
    namespace <- entry$namespace
    if (length(namespace) == 1L && is.character(namespace) &&
        nzchar(namespace)) {
      return(FALSE)
    }
    url <- entry$url
    if (length(url) == 1L && is.character(url) && nzchar(url) &&
        length(shiny::parseQueryString(url)$module)) {
      return(FALSE)
    }
    TRUE
  }, entries)
  if (!length(entries)) {
    return(NULL)
  }
  registered <- vapply(entries, function(entry) {
    if (inherits(entry$registered_at, "POSIXct")) {
      as.numeric(entry$registered_at)
    } else {
      -Inf
    }
  }, 0)
  entries[[which.max(registered)]]
}

# The open module page of `module_id` that reported focus at or after
# `since`, i.e. the user sees it; NULL when there is none yet
mcp_shown_module <- function(module_id, since) {
  shown <- Filter(function(open_module) {
    focused_at <- open_module$entry$activity$get("focused_at")
    identical(open_module$module_id, module_id) &&
      inherits(focused_at, "POSIXct") && isTRUE(focused_at >= since)
  }, mcp_open_modules())
  if (!length(shown)) {
    return(NULL)
  }
  mcp_rank_modules(shown)[[1L]]
}

mcp_tool_switch_module <- function(arguments, scope = list()) {
  module_id <- trimws(paste(as.character(unlist(arguments$module_id)),
                            collapse = ""))
  # a handle (`<module>@<token>`) names its module
  module_id <- sub("@.*$", "", module_id)
  auto_new <- !identical(as.logical(unlist(arguments$auto_new))[1], FALSE)

  modules <- tryCatch(mcp_sidebar_modules(), error = function(e) NULL)
  describe <- function(id) {
    label <- modules$label[match(id, modules$id)]
    if (length(label) == 1L && !is.na(label) && nzchar(label)) {
      sprintf("`%s` (%s)", id, label)
    } else {
      sprintf("`%s`", id)
    }
  }
  all_open <- mcp_open_modules()

  pinned <- Filter(function(open_module) {
    isTRUE(open_module$entry$activity$get("pinned", FALSE))
  }, all_open)
  if (length(pinned)) {
    return(mcp_tool_error(sprintf(
      paste(
        "The user pinned %s, so agent tool calls must stay in that module,",
        "and switching modules is refused while a module is pinned. Nothing",
        "changed. Ask the user to unpin it (its thumbtack button) if they",
        "want you to switch modules."
      ),
      describe(pinned[[1L]]$module_id)
    )))
  }

  if (!isTRUE(module_id %in% modules$id)) {
    problem <- if (nzchar(module_id)) {
      sprintf("There is no module `%s` in the dashboard's sidebar.", module_id)
    } else {
      "`module_id` is required."
    }
    listed <- if (length(modules$id)) {
      paste(vapply(modules$id, describe, ""), collapse = ", ")
    } else {
      "(none)"
    }
    return(mcp_tool_error(sprintf("%s The sidebar's modules: %s.", problem,
                                  listed)))
  }

  # A connection limited to one module (`/mcp/<module>`) stays with it
  scope_module <- scope$module
  scoped <- length(scope_module) == 1L && !is.na(scope_module) &&
    nzchar(scope_module)
  if (scoped) {
    allowed <- unique(c(
      vapply(mcp_match_modules(all_open, scope_module), `[[`, "",
             "module_id"),
      sub("@.*$", "", scope_module)
    ))
    if (!module_id %in% allowed) {
      return(mcp_tool_error(sprintf(
        "This connection is limited to module `%s`, so it cannot switch to `%s`.",
        allowed[[1L]], module_id
      )))
    }
  }

  # The page that gets the request: the module page used last (its
  # dashboard switches), else the dashboard page opened last
  candidates <- mcp_rank_modules(
    mcp_match_modules(all_open, if (scoped) scope_module)
  )
  if (length(candidates)) {
    page <- candidates[[1L]]$entry
    page_module <- candidates[[1L]]$module_id
  } else {
    page <- mcp_latest_dashboard()
    page_module <- NULL
  }
  if (is.null(page)) {
    return(mcp_tool_error(paste(
      "No dashboard page is open in the browser, so nothing can switch",
      "modules. Ask the user to open the app in the browser."
    )))
  }

  session <- page$shiny_session
  root <- session$rootScope()
  request_id <- rand_string()
  input_id <- session$ns(mcp_switch_module_input)
  timeout <- getOption("shidashi.switch_module_timeout", 10)
  wait <- getOption("shidashi.switch_module_wait", 30)
  started <- Sys.time()
  session$sendCustomMessage("shidashi.switch_module", list(
    module_id  = module_id,
    auto_new   = auto_new,
    request_id = request_id,
    input_id   = input_id
  ))

  answered <- mcp_poll(function() {
    value <- shiny::isolate(root$input[[input_id]])
    if (is.list(value) && identical(value$request_id, request_id)) {
      status <- paste(as.character(unlist(value$status)), collapse = "")
      if (nzchar(status)) status else "(none)"
    }
  }, timeout = timeout)

  shown_text <- function(status, shown) {
    if (is.null(shown)) {
      what <- if (identical(status, "opened")) {
        sprintf(
          "Opened %s in a new tab, but it has not finished loading within %s s.",
          describe(module_id), format(wait)
        )
      } else {
        sprintf(
          "Switched to %s, but its page has not reported back within %s s.",
          describe(module_id), format(wait)
        )
      }
      return(paste(what, sprintf(
        paste(
          "Until it does, tool calls run in the module used before: call",
          "`shidashi_sessions` and wait until `%s` is the `default_module`."
        ),
        module_id
      )))
    }
    what <- if (identical(status, "opened")) {
      sprintf("Opened %s in a new tab; it has loaded.", describe(module_id))
    } else {
      sprintf("Switched to %s: its open tab is in front.", describe(module_id))
    }
    tools <- shown$entry$tools
    if (is_shidashi_fastmap(tools) && tools$size() > 0L) {
      paste(what, sprintf("Tool calls now run there (`%s`).", shown$handle))
    } else {
      paste(what, paste(
        "It has no agent tools, so tool calls keep running in the module",
        "used before."
      ))
    }
  }

  result <- promises::then(answered, function(status) {
    if (is.null(status)) {
      stop(sprintf(
        paste(
          "The browser did not answer within %s s: the page may be busy or",
          "closed, or its dashboard JavaScript may be older than this tool.",
          "The switch was not confirmed."
        ),
        format(timeout)
      ), call. = FALSE)
    }
    switch(
      status,
      "activated" = ,
      "opened" = promises::then(
        mcp_poll(function() mcp_shown_module(module_id, since = started),
                 timeout = wait),
        function(shown) shown_text(status, shown)
      ),
      "not_open" = stop(sprintf(
        paste(
          "%s is not open in the dashboard, and `auto_new` is false, so",
          "nothing changed. Call `switch_module` again with `auto_new: true`",
          "to open it."
        ),
        describe(module_id)
      ), call. = FALSE),
      "no_dashboard" = stop(sprintf(
        paste(
          "The page that got the request%s is not inside a dashboard with",
          "module tabs (e.g. a module opened on its own with `?module=`), so",
          "it cannot switch modules. Nothing changed. Ask the user to open %s",
          "from the dashboard's sidebar."
        ),
        if (length(page_module)) sprintf(" (module `%s`)", page_module) else "",
        describe(module_id)
      ), call. = FALSE),
      "not_found" = stop(sprintf(
        paste(
          "The dashboard has no sidebar link for `%s`, so nothing changed.",
          "The page may be out of date: ask the user to reload the dashboard."
        ),
        module_id
      ), call. = FALSE),
      stop(sprintf(
        "Unexpected answer from the browser: `%s`. The switch was not confirmed.",
        status
      ), call. = FALSE)
    )
  })

  # Always a tool result: the HTTP handler catches only synchronous errors
  promises::then(
    result,
    onFulfilled = function(text) {
      list(content = list(list(type = "text", text = text)), isError = FALSE)
    },
    onRejected = function(e) {
      mcp_tool_error(conditionMessage(e))
    }
  )
}
