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

#' Create \verb{MCP} Tools for Shiny Input Management
#'
#' @description
#' Builds a \code{\link{mcp_wrapper}} that exposes two \verb{MCP} tools:
#' \code{shiny_input_info} (query registered inputs) and
#' \code{shiny_input_update} (set input values). Inputs must first be
#' registered via the returned helper functions before they become visible
#' to the \verb{MCP} tools.
#'
#' @return A list with two elements:
#' \describe{
#'   \item{\code{input_helpers}}{A list of helper functions for managing
#'     input specifications:
#'     \describe{
#'       \item{\code{register_input_specification(expr, inputId, description, update, writable, quoted, env)}}{Registers
#'         a shiny input for \verb{MCP} access and returns the evaluated
#'         UI element. The \code{expr} argument is a call expression that
#'         creates a shiny input widget, e.g.
#'         \code{shiny::textInput(inputId = "x", label = "X")}.
#'         All metadata (\code{inputId}, \code{description}, \code{update})
#'         must be provided explicitly by the module writer.
#'         Returns the evaluated UI element (e.g. an HTML tag object),
#'         so the call can be used inline in UI definitions.}
#'       \item{\code{update_input_specification(inputId, description, type, update, writable)}}{Modifies
#'         the spec of an already-registered input. All arguments except
#'         \code{inputId} are optional; only supplied values are changed.
#'         Returns a list with \code{item} (the updated \code{data.frame} row)
#'         and \code{changed} (logical).}
#'       \item{\code{get_input_specification()}}{Returns a \code{data.frame}
#'         of all registered input specs (columns: \code{inputId},
#'         \code{description}, \code{type}, \code{update}, \code{writable}).
#'         Returns an empty \code{data.frame} with the same columns when
#'         no inputs are registered.}
#'     }
#'   }
#'   \item{\code{tool_generator}}{A \code{shidashi_mcp_wrapper} that, given a
#'     \code{session}, returns a named list of \code{ellmer::ToolDef} objects:
#'     \code{shiny_input_info} and \code{shiny_input_update}.}
#' }
#'
#' @details
#' The \code{update} specification string follows the pattern
#' \code{"pkg::fun"} or \code{"pkg::fun(key=formal, ...)"}.
#' The key-value pairs override the
#' default argument names passed to the update function:
#' \itemize{
#'   \item \code{id} — the formal argument name for the input ID
#'     (default \code{"inputId"})
#'   \item \code{value} — the formal argument name for the new value
#'     (default \code{"value"})
#'   \item \code{session} — the formal argument name for the session
#'     (default \code{"session"})
#' }
#'
#' For example, \code{"shiny::updateSelectInput(id=inputId,value=select)"}
#' means the update call will use \code{inputId} for the ID argument and
#' \code{select} (not \code{value}) for the value argument.
#'
#' Values received from \verb{MCP} are JSON-encoded strings. The update tool
#' attempts to decode them with \code{jsonlite::fromJSON()} before passing
#' them to the update function, falling back to the raw string on failure.
#'
#' @examples
#' wrapper <- mcp_wrapper_input_output()
#'
#' # Register inputs inline — returns the UI element for use in UI code
#' text_ui <- wrapper$input_helpers$register_input_specification(
#'   expr = shiny::textInput(inputId = "my_text", label = "User name"),
#'   inputId = "my_text",
#'   description = "User name",
#'   update = "shiny::updateTextInput"
#' )
#'
#' select_ui <- wrapper$input_helpers$register_input_specification(
#'   expr = shiny::selectInput("my_select", "Choose a dataset",
#'                             choices = c("iris", "mtcars")),
#'   inputId = "my_select",
#'   description = "Choose a dataset to visualise",
#'   update = "shiny::updateSelectInput(value=selected)"
#' )
#'
#' # Inspect all registered specs
#' wrapper$input_helpers$get_input_specification()
#'
#' # The MCP tool generator (pass to your MCP server registration)
#' shiny_input_wrapper <- wrapper$tool_generator
#'
#' # Initialization with a mock session
#' tools <- shiny_input_wrapper(shiny::MockShinySession$new())
#'
#' @param input_specs An optional \code{fastmap::fastmap()} object to use as
#'   the backing store for input specifications.  When \code{NULL} (the
#'   default) a fresh \code{fastmap} is created.  Passing an existing
#'   \code{fastmap} allows multiple wrapper instances (e.g. one created
#'   during UI rendering and another during server initialization) to share
#'   the same input registry.
#'
#' @noRd
mcp_wrapper_input_output <- function(input_specs = fastmap::fastmap(), output_specs = fastmap::fastmap()) {

  # stores the input ID, description, type, update function, writable for a
  # session inputId should be relative to session, meaning
  # "btn" not session$ns("btn")

  normalize_update_fun <- function(update) {
    # update <- "updateSelectInput(id=inputId,value=select)"
    if (!grepl(":", update)) {
      update <- sprintf("shiny::%s", update)
    }
    # record the original spec string before stripping the call signature
    spec  <- update
    parts <- strsplit(update, "[:]+", perl = TRUE)[[1]]
    fun_part <- parts[[2]]
    pkg      <- parts[[1]]
    # fun_part might be updateTextInput, or
    # updateSelectInput(id=inputId,value=select)
    fun_name    <- fun_part
    fields <- list(
      id      = "inputId",
      value   = "value",
      session = "session"
    )
    if (endsWith(fun_part, ")")) {
      fun_name   <- sub("^([^(]+)\\(.*\\)$", "\\1", fun_part, perl = TRUE)
      args_inner <- sub("^[^(]+\\((.*)\\)$", "\\1", fun_part, perl = TRUE)
      # parse key=value pairs; skip quoted-string values like session="session"
      for (pair in strsplit(args_inner, ",")[[1]]) {
        kv <- strsplit(trimws(pair), "\\s*=\\s*", perl = TRUE)[[1]]
        if (length(kv) != 2L) next
        key <- trimws(kv[[1]])
        val <- trimws(kv[[2]])
        fields[[key]] <- val
      }
    }
    fun_impl <- asNamespace(pkg)[[fun_name]]
    if (!is.function(fun_impl)) {
      stop("Unable to find update function `", pkg, "::", fun_name, "`")
    }

    list(
      update       = spec,
      fun_impl    = fun_impl,
      pkg         = pkg,
      fun         = fun_name,
      fields      = fields
    )
  }

  register_input_spec <- function(
    expr,
    inputId,
    update,
    description = "",
    writable = TRUE,
    quoted = FALSE,
    env = parent.frame()
  ) {
    "
    Register a shiny input for MCP tool access and return the UI element.

    The `expr` argument should be a call expression that creates a shiny
    input widget, e.g. `shiny::textInput(inputId = 'x', label = 'X')`.
    The expression is evaluated and its result (the UI element) is
    returned, so this function can be used inline in place of the
    original input constructor.

    Usage:
      register_input_spec(
        expr = shiny::textInput(inputId = ns('my_text'), label = 'Name'),
        inputId = 'my_text',
        description = 'Name',
        update = 'shiny::updateTextInput',
        writable = TRUE
      )

    @param expr        A call expression that creates a shiny input widget,
      e.g. `shiny::textInput(inputId = 'x', label = 'X')` or
      `selectInput('sel', 'Choose', choices = c('a','b'))`.
    @param inputId     Character scalar. The shiny input ID.
    @param description Character scalar. A human-readable description
      of the input's purpose, shown to LLM agents via the MCP info tool.
    @param update      Character scalar. The update function spec,
      e.g. 'shiny::updateTextInput' or
      'shiny::updateSelectInput(value=selected)'.
      Field mappings (e.g. value=selected) override the default
      argument names passed to the update function.
    @param writable    Logical scalar (default TRUE). Whether the MCP
      update tool is allowed to change this input.

    @return The evaluated UI element produced by the `expr` expression.
      The input specification is registered as a side effect.
    "
    if (!quoted) {
      expr <- substitute(expr)
    }

    # Normalise and validate the update spec
    update_info <- normalize_update_fun(update)

    item <- data.frame(
      inputId     = inputId,
      description = paste(description, collapse = " "),
      type        = truc_string(deparse1(expr), max_char = 100),
      update      = update_info$update,
      writable    = as.logical(writable)[[1]]
    )

    input_specs$set(inputId, item)

    # Evaluate the expression and return the UI element
    eval(expr, envir = env)
  }

  class(register_input_spec) <- c("register_input_impl", "function")

  register_output_spec <- function(expr, outputId, description = "", quoted = FALSE, env = parent.frame()) {
    if (!quoted) {
      expr <- substitute(expr)
    }

    description <- trimws(paste(description, collapse = ""))
    if (!nzchar(description)) {
      description <- deparse1(expr)
    }

    item <- data.frame(
      outputId    = outputId,
      description = paste(description, collapse = " "),
      type        = truc_string(deparse1(expr), max_char = 150, side = "both")
    )

    output_specs$set(outputId, item)

    return(invisible(item))
  }
  class(register_output_spec) <- c("register_output_impl", "function")

  update_input_spec <- function(
    inputId,
    description = NULL,
    type = NULL,
    update = NULL,
    writable = NULL
  ) {
    "
    Update the specification of an already-registered shiny input.

    Usage:
      update_input_spec(inputId, description, type, update, writable)

    @param inputId     Character scalar. Must match a previously registered
      input ID; an error is raised otherwise.
    @param description Character or NULL. New description (replaces old).
    @param type        Character or NULL. New widget type.
    @param update      Character or NULL. New update function spec string.
    @param writable    Logical or NULL. New writable flag.

    @return A list (invisible) with:
      - item:    the updated 1-row data.frame.
      - changed: logical, TRUE if any field was modified.
    "
    if (!input_specs$has(inputId)) {
      stop("Input `", inputId, "` has not been registered.")
    }
    item <- input_specs$get(inputId)
    changed <- FALSE
    if (!is.null(description)) {
      item$description <- paste(description, collapse = " ")
      changed <- TRUE
    }
    if (!is.null(type)) {
      item$type <- type
      changed <- TRUE
    }
    if (!is.null(update)) {
      update_info <- normalize_update_fun(update)
      item$update <- update_info$update
      changed <- TRUE
    }
    if (!is.null(writable)) {
      item$writable <- as.logical(writable)[[1]]
      changed <- TRUE
    }
    if (changed) {
      input_specs$set(inputId, item)
    }

    invisible(list(
      item = item,
      changed = changed
    ))
  }

  get_input_spec <- function() {
    "
    Retrieve all registered input specifications as a data.frame.

    Usage:
      get_input_spec()

    @return A data.frame with columns: inputId, description, type,
      update, writable. Returns an empty data.frame with the same
      columns when no inputs have been registered.
    "
    if (input_specs$size() == 0) {
      return(data.frame(
        inputId     = character(),
        description = character(),
        type        = character(),
        update      = character(),
        writable    = logical()
      ))
    }
    items <- input_specs$as_list()
    re <- do.call("rbind", items)
    row.names(re) <- NULL
    re
  }

  wrapper <- mcp_wrapper(function(
    session = shiny::getDefaultReactiveDomain()
  ) {

    query_requests <- fastmap::fastmap()

    # Observer: when the browser responds via setInputValue, store the
    # result in query_requests so shiny_query_ui_result can fetch it.
    local({
      shiny::bindEvent(
        shiny::observe({
          res <- session$input[["@shiny_query_ui_result@"]]
          res <- as.list(res)
          rid <- res$request_id
          if (length(rid) != 1 || !query_requests$has(rid)) {
            return()
          }
          entry <- query_requests$get(rid)
          entry$result <- res
          # str(res)
          # message(Sys.time() - entry$request_timestamp)
          query_requests$set(rid, entry)
        }, domain = session, priority = 101),
        session$input[["@shiny_query_ui_result@"]],
        ignoreNULL = TRUE, ignoreInit = FALSE
      )
    })

    shiny_input_info <- ellmer::tool(
      name = "shiny_input_info",
      description = paste(
        "Query registered shiny input specifications.",
        "Returns input IDs, descriptions, types, update functions,",
        "whether each is writable, and (when a session is active)",
        "whether each currently exists and its current value."
      ),
      arguments = list(
        inputIds = ellmer::type_array(
          ellmer::type_string(
            description = "Shiny input ID"
          ),
          description = "Optional: specific input IDs to query. Omit to list all registered inputs.",
          required = FALSE
        )
      ),
      fun = function(inputIds = character()) {
        inputIds <- unlist(inputIds)
        inputIds <- inputIds[!is.na(inputIds) & nzchar(inputIds)]
        if (length(inputIds) > 0) {
          items <- input_specs$mget(inputIds)
        } else {
          items <- input_specs$as_list()
        }
        # split each row into list

        if (!is.null(session)) {
          input <- shiny::isolate(shiny::reactiveValuesToList(session$input))
          items <- lapply(items, function(item) {
            if (is.null(item)) { return(NULL) }
            item <- as.list(item)
            item$exists <- item$inputId %in% names(input)
            item$current_value <- input[[item$inputId]]
            item
          })
        } else {
          items <- lapply(items, function(item) {
            as.list(item)
          })
        }

        items
      }
    )

    shiny_input_update <- ellmer::tool(
      name = "shiny_input_update",
      description = paste(
        "Update a shiny input value by its ID.",
        "The value will be sent to the corresponding shiny update function",
        "(e.g. updateTextInput, updateSelectInput, updateNumericInput).",
        "Call `shiny_input_info()` first to discover available input IDs,",
        "their types, current values, and whether they are writable.",
        "After changing the inputs, always call `shiny_input_info` again",
        "to verify the changes."
      ),
      arguments = list(
        inputId = ellmer::type_string(
          description = "Shiny input ID of which the value is to be changed",
          required = TRUE
        ),
        value = ellmer::type_string(
          description = "The new value for the input. Use JSON encoding for non-string values (e.g. 123, [1,2,3], {\"a\":1})."
        )
      ),
      fun = function(inputId, value) {
        # TODO: add a mode for tentative updating the input (highlight the
        # inputs and mark the values instead of changing them)
        if (!input_specs$has(inputId)) {
          stop(
            "There is no input ID: `",
            inputId,
            "`. Available IDs are: ",
            paste(input_specs$keys(), collapse = ", "),
            ". Call `shiny_input_info()` to get their information."
          )
        }

        item <- input_specs$get(inputId)
        if (!item$writable) {
          stop("Input ID: `", inputId, "` is read-only.")
        }

        active_inputIds <- shiny::isolate(names(session$input))
        if (!item$inputId %in% active_inputIds) {
          stop(
            "Input ID: `", inputId,
            "` is inactive or missing from this session."
          )
        }

        # Decode JSON-encoded value
        value <- tryCatch(
          jsonlite::fromJSON(value),
          error = function(e) value
        )

        update_info <- normalize_update_fun(item$update)

        expr <- as.call(structure(
          list(
            quote(update_info$fun_impl),
            session,
            inputId,
            value
          ),
          names = c(
            "",
            update_info$fields$session %||% "session",
            update_info$fields$id %||% "inputId",
            update_info$fields$value %||% "value"
          )
        ))

        eval(expr)

        # Wait for Shiny to update
        Sys.sleep(0.1)

        return(invisible(list(
          updated = TRUE,
          shiny_namespace = session$ns(NULL),
          inputId = inputId,
          value = value
        )))
      }
    )


    shiny_query_ui <- ellmer::tool(
      name = "shiny_query_ui",
      description = paste(
        "Request the HTML content of a UI element by CSS selector.",
        "This sends a query to the browser and returns a request_id.",
        "The browser response is asynchronous; call `tool__shiny_query_ui_result`",
        "with the returned request_id to retrieve the actual content.",
        "Wait briefly (1-2 seconds) before fetching the result."
      ),
      arguments = list(
        css_selector = ellmer::type_string(
          description = "A CSS selector to query (e.g. '#my_output', '.card-body', 'div[data-id=\"plot\"]').",
          required = TRUE
        )
      ),
      fun = function(css_selector) {
        request_id <- rand_string()

        query_requests$set(request_id, list(
          request_id = request_id,
          request_timestamp = Sys.time(),
          selector = css_selector,
          result = NULL
        ))

        session$sendCustomMessage("shidashi.query_ui", list(
          selector = css_selector,
          request_id = request_id,
          input_id = session$ns("@shiny_query_ui_result@")
        ))

        # Wait for the browser to store the result in the map — up to 10 x 1s.
        # Doing the wait in the sender avoids the race where the client calls
        # shiny_query_ui_result before Shiny has flushed the reactive observer.
        coro::async(function() {
          for (i in seq_len(10)) {
            coro::async_sleep(1)
            if (query_requests$has(request_id) &&
                !is.null(query_requests$get(request_id)$result)) {
              break
            }
          }
          paste0(
            "Request registered (id: ", request_id, "). ",
            "Call `tool__shiny_query_ui_result(request_id = \"", request_id, "\")` ",
            "to retrieve the result."
          )
        })()
      }
    )

    shiny_query_ui_result <- ellmer::tool(
      name = "shiny_query_ui_result",
      description = paste(
        "Fetch the result of a previous `shiny_query_ui` request.",
        "Returns the innerHTML of the matched element, or an inline image",
        "if the element contains <img> or <canvas>.",
        "An optional text note may be appended with additional context",
        "(e.g. outerHTML, not-found message, or hidden-element content).",
        "If the result is not yet ready, wait ~0.5 s and call again."
      ),
      arguments = list(
        request_id = ellmer::type_string(
          description = "The request_id returned by a prior `shiny_query_ui` call.",
          required = TRUE
        )
      ),
      fun = function(request_id) {
        # 1. Unknown request_id
        if (!query_requests$has(request_id)) {
          stop(
            "Unknown request_id: '", request_id, "'. ",
            "It may have already been consumed or was never created. ",
            "Call `shiny_query_ui` first to register a new request."
          )
        }

        entry <- query_requests$get(request_id)
        res <- entry$result

        # 2. Result available — consume and return
        if (!is.null(res)) {
          query_requests$remove(request_id)
          # note is an optional free-text annotation added by newer JS versions
          # (e.g. outerHTML context, not-found message, hidden-element innerHTML).
          # Older JS omits it entirely; R does not branch on it — agents interpret it.
          note <- res$note %||% ""

          # Primary dispatch: image_data present → inline image
          if (length(res$image_data) == 1 && nzchar(res$image_data)) {
            mime <- res$image_type %||% "image/png"
            img <- ellmer::ContentImageInline(type = mime, data = res$image_data)
            if (nzchar(note)) {
              return(list(img, ellmer::ContentText(note)))
            }
            return(img)
          }

          # Default: return html string, append note when present
          html <- res$html %||% ""
          if (nzchar(note)) {
            html <- paste(
              c(html, "\n\n<!-- NOTE: ", note, "-->"),
              collapse = "\n"
            )
          }
          return(html)
        }

        # 3. Not yet available — check age
        elapsed <- as.double(
          difftime(Sys.time(), entry$request_timestamp, units = "secs")
        )
        if (elapsed > 30) {
          stop(
            "No response from browser for selector '",
            entry$selector, "' within 30 seconds. ",
            "The selector is most likely invalid (no matching results)."
          )
        }
        # Ask the client to wait briefly and retry
        coro::async(function() {
          coro::async_sleep(1)
          paste0(
            "Result not yet available (", round(elapsed, 1), "s elapsed). ",
            "Wait ~0.5 s and call `tool__shiny_query_ui_result(request_id = \"",
            request_id, "\")` again."
          )
        })()
      }
    )

    shiny_output_info <- ellmer::tool(
      name = "shiny_output_info",
      description = paste(
        "List registered Shiny output elements and optionally retrieve",
        "their rendered HTML content. When outputIds is omitted, returns",
        "all registered outputs with their descriptions. You can get the",
        "HTML content of output via `shiny_query_ui(selector)`"
      ),
      arguments = list(
        outputIds = ellmer::type_array(
          ellmer::type_string(description = "Shiny output ID"),
          description = "Optional: specific output IDs to query. Omit to list all registered outputs.",
          required = FALSE
        )
      ),
      fun = function(outputIds = character()) {
        outputIds <- unlist(outputIds)
        outputIds <- outputIds[!is.na(outputIds)]
        if (length(outputIds) > 0) {
          items <- output_specs$mget(outputIds)
        } else {
          items <- output_specs$as_list()
        }

        results <- lapply(items, function(item) {
          if (is.null(item)) return(NULL)
          as.list(item)
        })

        if (is.null(session)) {
          return(results)
        }

        results <- lapply(results, function(item) {
          item$css_selector <- sprintf("#%s", session$ns(item$outputId))
          item
        })

        return(results)
      }
    )

    list(
      shiny_input_info = shiny_input_info,
      shiny_input_update = shiny_input_update,
      shiny_query_ui = shiny_query_ui,
      shiny_query_ui_result = shiny_query_ui_result,
      shiny_output_info = shiny_output_info
    )
  })



  list(
    input_helpers = list(
      register_input_specification = register_input_spec,
      register_output_specification = register_output_spec,
      update_input_specification = update_input_spec,
      get_input_specification = get_input_spec
    ),
    tool_generator = wrapper
  )

}

find_expr <- function(call, env) {
  if (!is.call(call)) {
    stop("find_expr needs a function call, got:\n", deparse1(call))
    return(NULL)
  }
  fn_symbol <- call[[1L]]
  # Resolve the actual function object
  fn <- NULL

  if (
    identical(fn_symbol, quote(shiny::bindEvent)) ||
    identical(fn_symbol, quote(bindEvent))
  ) {
    call <- match.call(definition = shiny::bindEvent, call = call)
    call <- call$x
    fn_symbol <- call[[1L]]
  }

  if (is.call(fn_symbol) && identical(fn_symbol[[1L]], quote(`::`))) {
    # pkg::fun(...) form
    pkg <- as.character(fn_symbol[[2L]])
    fun_name <- as.character(fn_symbol[[3L]])
    ns <- asNamespace(pkg)
    fn <- ns[[fun_name]]
  } else {
    # try to get the function
    tryCatch(
      {
        fn <- eval(fn_symbol, envir = new.env(parent = env))
      },
      error = function(e) {}
    )
  }

  if (is.function(fn)) {
    call <- match.call(fn, call)
  }

  call <- as.list(call)

  expr <- call[["expr"]]
  if (is.null(expr)) {
    # First positional argument
    expr <- call[[2]]
  }

  expr
}


# Internal helper: set up download handler, popout handler, and send
# output metadata to JS. Called by register_output().
register_output_widgets <- function(
  render_expr,
  render_env,
  outputId,
  download_type = "image",
  download_function = NULL,
  output_opts = list(),
  extension = NULL,
  description = "",
  session = shiny::getDefaultReactiveDomain()
) {

  if (is.null(session)) { return(invisible()) }

  ns <- session$ns
  ns_outputId <- ns(outputId)
  input <- session$input

  # Determine enabled widgets
  widgets <- "popout"
  if (!identical(download_type, "no-download")) {
    widgets <- c("download", widgets)
  }

  # --- Download handler setup ---
  if ("download" %in% widgets) {
    download_ns_id <- ns(paste0(outputId, "__download"))
    trigger_ns_id <- paste0(ns_outputId, "__download_trigger")
    modal_prefix <- paste0(outputId, "__dlmodal_")

    shiny::bindEvent(
      shiny::observe({
        # Build modal UI based on download_type
        modal_ui <- switch(
          download_type,
          "image" = shiny::tagList(
            shiny::numericInput(
              inputId = ns(paste0(modal_prefix, "width")),
              label = "Width (cm)",
              value = 30, min = 1, max = 200, step = 0.1
            ),
            shiny::numericInput(
              inputId = ns(paste0(modal_prefix, "height")),
              label = "Height (cm)",
              value = 20, min = 1, max = 200, step = 0.1
            ),
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "filename")),
              label = "Filename",
              value = paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
            ),
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          ),
          "threeBrain" = shiny::tagList(
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "filename")),
              label = "Filename",
              value = paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
            ),
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "title")),
              label = "Title",
              value = "RAVE Viewer"
            ),
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          ),
          "data" = shiny::tagList(
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "filename")),
              label = "Filename",
              value = paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
            ),
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          ),
          "htmlwidget" = shiny::tagList(
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "filename")),
              label = "Filename",
              value = paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
            ),
            shiny::checkboxInput(
              inputId = ns(paste0(modal_prefix, "self_contained")),
              label = "Self-contained",
              value = TRUE
            ),
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          ),
          "stream_viz" = shiny::tagList(
            shiny::textInput(
              inputId = ns(paste0(modal_prefix, "filename")),
              label = "Filename",
              value = paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
            ),
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          ),
          # fallback
          shiny::tagList(
            shiny::downloadButton(
              outputId = download_ns_id,
              label = "Download"
            )
          )
        )

        shiny::showModal(shiny::modalDialog(
          title = if (nzchar(description)) description else paste("Download", outputId),
          modal_ui,
          easyClose = TRUE,
          footer = shiny::modalButton("Cancel")
        ), session = session)
      }, domain = session),
      input[[paste0(outputId, "__download_trigger")]],
      ignoreNULL = TRUE, ignoreInit = TRUE
    )

    # Download handler
    session$output[[paste0(outputId, "__download")]] <- shiny::downloadHandler(
      filename = function() {
        fname <- input[[paste0(modal_prefix, "filename")]]
        if (!length(fname) || !nzchar(fname)) {
          fname <- paste0(outputId, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
        }
        switch(
          download_type,
          "image" = paste0(fname, ".pdf"),
          "threeBrain" = paste0(fname, ".html"),
          "htmlwidget" = paste0(fname, ".html"),
          "stream_viz" = paste0(fname, ".bin"),
          {
            if (length(extension)) {
              extension <- gsub("^[\\.]{0,}", ".", extension)
            } else {
              extension <- ""
            }
            paste0(fname, extension)
          }

        )
      },
      content = function(file) {
        switch(
          download_type,
          "image" = {
            width_cm <- input[[paste0(modal_prefix, "width")]]
            height_cm <- input[[paste0(modal_prefix, "height")]]
            if (!length(width_cm) || is.na(width_cm)) {
              width_cm <- 30
            }
            if (!length(height_cm) || is.na(height_cm)) {
              height_cm <- 20
            }
            width_in <- width_cm / 2.54
            height_in <- height_cm / 2.54

            grDevices::pdf(
              file,
              onefile = TRUE,
              useDingbats = FALSE,
              width = width_in,
              height = height_in
            )

            tryCatch(
              {
                res <- eval(render_expr, envir = new.env(parent = render_env))
                if (inherits(res, "ggplot")) {
                  # render ggplot
                  print(res)
                }
              },
              finally = {
                grDevices::dev.off()
              }
            )
          },
          "threeBrain" = {
            tb <- asNamespace("threeBrain")
            title <- input[[paste0(modal_prefix, "title")]]
            if (!length(title) || !nzchar(title)) {
              title <- "RAVE Viewer"
            }
            widget <- eval(render_expr, envir = new.env(parent = render_env))
            tb$save_brain(widget, file, title = title)
          },
          "htmlwidget" = {
            widget <- eval(render_expr, envir = new.env(parent = render_env))
            htmlwidgets::saveWidget(widget, file, selfcontained = TRUE)
          },
          "data" = {
            if (is.function(download_function)) {
              download_function(file)
            }
          },
          "stream_viz" = {
            bin_path <- stream_path(outputId, session)
            if (file.exists(bin_path)) {
              file.copy(bin_path, file, overwrite = TRUE)
            }
          }
        )

        # download finishes, dismiss the modal
        shiny::removeModal()
      }
    )
  }

  # --- Send output metadata to JS ---
  session$sendCustomMessage("shidashi.register_output_widgets", list(
    outputId = ns_outputId,
    widgets = as.list(widgets),
    download_type = download_type,
    token = session$token
  ))

  # --- Store render info in session registry ---
  entry <- get_session_entry(session$token)
  if (!is.null(entry)) {
    entry$output_renderers$set(outputId, list(
      render_expr = render_expr,
      render_env = render_env,
      output_opts = output_opts,
      extension = extension,
      download_type = download_type
    ))
  }

  invisible()
}

#' @name register_io
#' @title Register Shiny Inputs and Outputs for \verb{MCP} Access
#' @description
#' Register \code{shiny} inputs and outputs for \verb{MCP} (Model Context
#' Protocol) agent access.
#'
#' \code{register_input()} wraps a \code{shiny} input constructor to
#' register metadata.  It evaluates \code{expr} and returns the UI element.
#'
#' \code{register_output()} is a server-side function that registers a
#' render function call (e.g. \code{renderPlot(\{...\})}), assigns it to
#' \code{session$output}, registers the \verb{MCP} output spec, and sets
#' up download-widget handlers.  The UI overlay icons are injected
#' entirely by \verb{JS}.
#'
#' @param expr For \code{register_input}: a call expression that creates
#'   a \code{shiny} input widget.
#'   For \code{register_output}: a render function call such as
#'   \code{renderPlot(\{...\})}.
#' @param inputId character string.  The \code{shiny} input ID
#'   (without the module namespace prefix).
#' @param outputId character string.  The \code{shiny} output ID
#'   (without the module namespace prefix).
#' @param update character string.  The fully qualified update function,
#'   e.g. \code{"shiny::updateTextInput"}.  Field mappings such as
#'   \code{"shiny::updateSelectInput(value=selected)"} override the
#'   default argument names passed to the update function.
#' @param description character string.  A human-readable description of
#'   the input or output purpose, exposed to \verb{LLM} agents via \verb{MCP} tools.
#' @param writable logical (default \code{TRUE}).  Whether the \verb{MCP}
#'   update tool is allowed to change this input.
#' @param quoted logical (default \code{FALSE}).  If \code{TRUE},
#'   \code{expr} is treated as already quoted; otherwise it is captured
#'   with \code{substitute()}.
#' @param env the environment in which to evaluate \code{expr}.
#' @param ... reserved for future use.
#' @param output_opts a named list of extra options for the output
#'   (e.g. width, height defaults).
#' @param download_function a custom download handler function.  When
#'   \code{download_type = "data"}, this function receives the file path
#'   and writes the download content.
#' @param download_type character string.  One of \code{"image"},
#'   \code{"threeBrain"}, \code{"data"}, or \code{"no-download"}.
#' @param extension character vector of allowed file extension for
#'   download, or \code{NULL}.
#' @param session the \code{shiny} session object.  For
#'   \code{register_output}, defaults to
#'   \code{shiny::getDefaultReactiveDomain()}.
#' @return \code{register_input} returns the evaluated UI element.
#'   \code{register_output} is called for its side effects (assigning
#'   the render function and registering widgets) and returns \code{NULL}
#'   invisibly.
#' @seealso \code{\link{init_app}}, \code{\link{mcp_wrapper}}
#' @examples
#' \dontrun{
#' # inside a shidashi module UI function:
#' ns <- shiny::NS("demo")
#'
#' register_input(
#'   expr = shiny::sliderInput(
#'     inputId = ns("threshold"),
#'     label = "Threshold",
#'     min = 0, max = 1, value = 0.5
#'   ),
#'   inputId = "threshold",
#'   update = "shiny::updateSliderInput",
#'   description = "Filter threshold for the plot"
#' )
#'
#' # inside a shidashi module server function:
#' register_output(
#'   expr = renderPlot(\{ plot(iris) \}),
#'   outputId = "my_plot",
#'   description = "Scatter plot of iris data",
#'   download_type = "image"
#' )
#' }
#' @export
register_input <- function(expr,
                           inputId,
                           update,
                           description = "",
                           writable = TRUE,
                           quoted = FALSE,
                           env = parent.frame()) {
  if (!quoted) {
    expr <- substitute(expr)
  }

  register_input_impl <- get0(
    x = ".register_input",
    envir = env,
    mode = "function",
    inherits = TRUE
  )

  if (isTRUE(inherits(register_input_impl, "register_input_impl"))) {
    register_input_impl(
      expr = expr,
      inputId = inputId,
      description = description,
      update = update,
      writable = writable,
      quoted = TRUE,
      env = env
    )
  } else {
    eval(expr, envir = env)
  }

}

#' @rdname register_io
#' @export
register_output <- function(
  expr,
  outputId,
  description = "",
  quoted = FALSE,
  env = parent.frame(),
  ...,
  output_opts = list(),
  download_function = NULL,
  download_type = c("image", "htmlwidget", "threeBrain", "no-download", "data", "stream_viz"),
  extension = NULL,
  session = shiny::getDefaultReactiveDomain()
) {

  if (is.null(session)) {
    stop("shidashi::register_output must run in a shiny server function.")
  }

  download_type <- match.arg(download_type)

  if (!quoted) {
    expr <- substitute(expr)
  }

  # Parse the render call to extract the inner expr
  parsed_expr <- find_expr(expr, env)

  # Register MCP output spec (records the call, does NOT eval)
  register_output_impl <- get0(
    x = ".register_output",
    envir = env,
    mode = "function",
    inherits = TRUE
  )

  if (isTRUE(inherits(register_output_impl, "register_output_impl"))) {
    register_output_impl(
      expr = expr,
      outputId = outputId,
      description = description,
      quoted = TRUE,
      env = env
    )
  }

  # Set up download/popout widgets
  register_output_widgets(
    render_expr = parsed_expr,
    render_env = env,
    outputId = outputId,
    download_type = download_type,
    download_function = download_function,
    output_opts = output_opts,
    extension = extension,
    description = description,
    session = session
  )

  # Evaluate the full render call and assign to session output
  render_function <- eval(expr, envir = env)
  if (!is.null(session)) {
    session$output[[outputId]] <- render_function
  }

  invisible(NULL)
}
