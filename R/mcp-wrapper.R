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

setup_mcp_proxy <- function(overwrite = TRUE, verbose = TRUE) {
  src <- system.file("mcp-proxy", "shidashi-proxy.mjs", package = "shidashi")
  if (!nzchar(src)) {
    return(invisible(NULL))
  }

  # Running apps announce themselves in `apps/` (see mcp_write_app_record);
  # `ports/` held the records of older versions and is no longer read.
  server_dir <- mcp_server_dir()
  dir.create(server_dir, recursive = TRUE, showWarnings = FALSE)
  unlink(file.path(server_dir, "ports"), recursive = TRUE)

  # What the proxy answers on its own when no app is running
  writeLines(
    jsonlite::toJSON(list(
      instructions = mcp_server_instructions(app_id = NULL),
      tools = mcp_meta_tool_schemas()
    ), auto_unbox = TRUE, null = "null", pretty = TRUE),
    file.path(server_dir, "proxy-meta.json")
  )

  # Copy proxy script to user cache.
  dest <- file.path(server_dir, "mcp-proxy.mjs")
  if (!file.exists(dest) || isTRUE(overwrite)) {
    file.copy(src, dest, overwrite = TRUE)
    if (verbose) message("Installed MCP proxy to:\n  ", dest)
  } else {
    if (verbose) message("MCP proxy already exists (overwrite = FALSE):\n  ", dest)
  }

  if (verbose) {
    snippet <- paste0(
      "{\n",
      "  \"servers\": {\n",
      "    \"shidashi\": {\n",
      "      \"type\": \"stdio\",\n",
      "      \"command\": \"node\",\n",
      "      \"args\": [\"", dest, "\"]\n",
      "    }\n",
      "  }\n",
      "}"
    )
    message(
      "\nPaste the following into your .vscode/mcp.json",
      " (or equivalent MCP settings):\n\n",
      snippet,
      "\n\nThe proxy connects to the most recently started shidashi app and ",
      "follows it across restarts. To always drive one app, name its ",
      "directory; to always run in one module, name the module:\n",
      "  \"args\": [\"", dest, "\", \"--app\", \"<app directory>\", ",
      "\"--module\", \"<module id>\"]\n",
      "\nTo let the agent start an app for you, save it first with ",
      "shidashi::save_launcher().\n"
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
#' @param input_specs An optional map made by \code{new_fastmap()} to use as
#'   the backing store for input specifications.  When \code{NULL} (the
#'   default) a fresh \code{fastmap} is created.  Passing an existing
#'   \code{fastmap} allows multiple wrapper instances (e.g. one created
#'   during UI rendering and another during server initialization) to share
#'   the same input registry.
#'
#' @noRd
mcp_wrapper_input_output <- function(input_specs = new_fastmap(), output_specs = new_fastmap()) {

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

    # Pending `shiny_query_ui` requests: request id -> list(resolve, reject)
    query_requests <- new_fastmap()

    # Observer: the browser answers a `shiny_query_ui` request through
    # `setInputValue`; settle the promise that the tool call is waiting on.
    # A reply for an unknown id (for example after the timeout) is ignored.
    local({
      shiny::bindEvent(
        safe_observe({
          res <- as.list(session$input[["@shiny_query_ui_result@"]])
          rid <- res$request_id
          if (length(rid) != 1 || !query_requests$has(rid)) {
            return()
          }
          entry <- query_requests$get(rid)
          query_requests$remove(rid)
          entry$resolve(res)
        }, domain = session, priority = 101, label = "MCP query_ui reply"),
        session$input[["@shiny_query_ui_result@"]],
        ignoreNULL = TRUE, ignoreInit = FALSE
      )
    })

    # A request the browser answers through `@shiny_query_ui_result@`:
    # returns its id and a promise that the observer above resolves; a timer
    # rejects the promise with `timeout_message` if nothing arrives.
    browser_request <- function(timeout, timeout_message) {
      request_id <- rand_string()
      promise <- promises::promise(function(resolve, reject) {
        query_requests$set(request_id, list(resolve = resolve,
                                            reject = reject))
      })

      # An error in a `later` callback would surface in the event loop, so
      # the timeout is guarded like an observer
      later::later(function() {
        tryCatch({
          if (!query_requests$has(request_id)) {
            return()
          }
          entry <- query_requests$get(request_id)
          query_requests$remove(request_id)
          entry$reject(simpleError(timeout_message))
        }, error = function(e) {
          warning("[shidashi] browser request timeout failed: ",
                  conditionMessage(e), call. = FALSE)
        })
      }, delay = timeout)

      list(id = request_id, promise = promise)
    }

    query_ui_max_chars <- function(max_chars) {
      max_chars <- suppressWarnings(as.integer(max_chars)[1])
      if (length(max_chars) != 1 || is.na(max_chars) || max_chars < 1) {
        max_chars <- as.integer(getOption("shidashi.query_ui_max_chars",
                                          10000L))
      }
      max_chars
    }

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

        # Missing or not initialized
        active_inputIds <- shiny::isolate(names(session$input))
        if (!item$inputId %in% active_inputIds) {
          stop(
            "Input ID: `", inputId,
            "` is inactive or missing from this session."
          )
        }

        # Decode JSON-encoded value
        value <- tryCatch(
          jsonlite::fromJSON(value, simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE),
          error = function(e) value
        )

        update_info <- normalize_update_fun(item$update)

        call_list <- structure(
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
        )
        
        # Check if update_info$fun is action button/link
        if (isTRUE(update_info$fun %in% c(
          "updateActionButton", "updateActionLink", "updateActionButtonStyled"
        ))) {
          # This is to update button
          selector <- sprintf("#%s", session$ns(inputId))
          session$sendCustomMessage(
            "shidashi.click",
            list(selector = selector)
          )
        } else {
          expr <- as.call(call_list)
          eval(expr)
        }

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


    # The browser's answer as tool content: an image (with the note, if
    # any) or the trimmed HTML (with the note appended). The note is a short
    # annotation from the JS side (e.g. the element's opening tag, a
    # not-found message, or that the element is hidden); agents interpret it.
    query_ui_content <- function(res, transform_image = TRUE,
                                 max_chars = 10000L) {
      note <- mcp_trim_html(res$note %||% "", max_chars = max_chars)
      if (identical(res$type, "not_found")) {
        stop(note, call. = FALSE)
      }
      has_image <- length(res$image_data) == 1 && nzchar(res$image_data)
      if (transform_image && has_image) {
        img <- ellmer::ContentImageInline(
          type = res$image_type %||% "image/png",
          data = res$image_data
        )
        if (nzchar(note)) {
          return(list(img, ellmer::ContentText(note)))
        }
        return(img)
      }
      html <- mcp_trim_html(res$html %||% "", max_chars = max_chars)
      if (!nzchar(html)) {
        return(note)
      }
      if (nzchar(note)) {
        html <- paste(c(html, "\n\n<!-- NOTE: ", note, "-->"), collapse = "\n")
      }
      html
    }

    shiny_query_ui <- ellmer::tool(
      name = "shiny_query_ui",
      description = paste(
        "Get the content of a UI element by CSS selector. By default a plot,",
        "canvas, SVG, or single image comes back as a picture; pass",
        "`transform_image = false` to get the element's HTML instead. Long",
        "HTML is trimmed (image data and scripts are shortened); use a more",
        "specific selector, or `max_chars`, to see more. The browser answers",
        "within a few seconds, and a short note may add context."
      ),
      arguments = list(
        css_selector = ellmer::type_string(
          description = "A CSS selector to query (e.g. '#my_output', '.card-body', 'div[data-id=\"plot\"]').",
          required = TRUE
        ),
        transform_image = ellmer::type_boolean(
          description = paste(
            "Optional, default true: return plots, canvases, SVGs, and",
            "single images as a picture. Set false to get HTML only."
          ),
          required = FALSE
        ),
        max_chars = ellmer::type_integer(
          description = paste(
            "Optional: the most HTML characters to return.",
            "Longer HTML is trimmed, with a note saying so."
          ),
          required = FALSE
        )
      ),
      fun = function(css_selector, transform_image = TRUE, max_chars = NULL) {
        # Returns a promise: the MCP call (or the chat's tool call) waits on
        # it while R keeps running, so the browser's answer can arrive.
        transform_image <- !identical(as.logical(transform_image)[1], FALSE)
        max_chars <- query_ui_max_chars(max_chars)
        timeout <- getOption("shidashi.query_ui_timeout", 15)

        request <- browser_request(timeout, sprintf(
          paste(
            "The browser did not answer within %s s: the selector `%s`",
            "may match nothing, or the module page is not open."
          ),
          format(timeout), css_selector
        ))

        session$sendCustomMessage("shidashi.query_ui", list(
          selector = css_selector,
          request_id = request$id,
          input_id = session$ns("@shiny_query_ui_result@"),
          transform_image = transform_image
        ))

        promises::then(request$promise, function(res) {
          if (isFALSE(res$laid_out)) {
            res$note <- paste(c(res$note[nzchar(res$note)], paste(
              "To render a registered output even when it is hidden, call",
              "`shiny_output_result(outputId)`."
            )), collapse = " ")
          }
          query_ui_content(res, transform_image = transform_image,
                           max_chars = max_chars)
        })
      }
    )

    shiny_output_result <- ellmer::tool(
      name = "shiny_output_result",
      description = paste(
        "Get the rendered content of a registered output by its ID, even",
        "when it sits in a hidden tab or a collapsed card: the output is",
        "rendered first if needed, waiting up to 10 seconds. Plots,",
        "canvases, SVGs, and single images come back as a picture; pass",
        "`transform_image = false` to get the HTML instead. For an",
        "htmlwidget output (such as a table that shows one page at a time)",
        "or a downloadable data output, the full data also comes back as",
        "text. Call `shiny_output_info()` to list the output IDs."
      ),
      arguments = list(
        outputId = ellmer::type_string(
          description = "A registered output ID, from `shiny_output_info()`.",
          required = TRUE
        ),
        transform_image = ellmer::type_boolean(
          description = paste(
            "Optional, default true: return plots, canvases, SVGs, and",
            "single images as a picture. Set false to get HTML only."
          ),
          required = FALSE
        ),
        max_chars = ellmer::type_integer(
          description = paste(
            "Optional: the most characters to return (default 10000), for",
            "the HTML and for the data text separately. Longer content is",
            "trimmed, with a note saying so."
          ),
          required = FALSE
        )
      ),
      fun = function(outputId, transform_image = TRUE, max_chars = NULL) {
        if (!output_specs$has(outputId)) {
          registered <- output_specs$keys()
          if (!length(registered)) {
            stop("This module registers no outputs. Use `shiny_query_ui()` ",
                 "with a CSS selector instead.")
          }
          stop("There is no registered output ID: `", outputId,
               "`. Registered IDs are: ", paste(registered, collapse = ", "),
               ".")
        }
        transform_image <- !identical(as.logical(transform_image)[1], FALSE)
        max_chars <- query_ui_max_chars(max_chars)
        timeout <- getOption("shidashi.output_result_timeout", 10)
        deadline <- Sys.time() + timeout
        seconds_left <- function() {
          as.numeric(difftime(deadline, Sys.time(), units = "secs"))
        }

        ns_outputId <- session$ns(outputId)
        selector <- paste0("#", ns_outputId)
        input_id <- session$ns("@shiny_query_ui_result@")

        # Step 1: the browser finds the element, and gives a plot that was
        # never shown a fallback size (shiny sizes plots from the browser)
        width <- shiny::isolate(
          session$clientData[[paste0("output_", ns_outputId, "_width")]]
        )
        prepare <- browser_request(timeout, sprintf(
          "The browser did not answer within %s s: the module page may not be open.",
          format(timeout)
        ))
        session$sendCustomMessage("shidashi.prepare_output", list(
          selector = selector,
          request_id = prepare$id,
          input_id = input_id,
          needs_size = is.null(width)
        ))

        promises::then(prepare$promise, function(prepared) {
          if (identical(prepared$type, "not_found")) {
            stop(prepared$note %||% sprintf(
              "No element matched selector: '%s'", selector
            ), call. = FALSE)
          }

          # Step 2: render the output even if hidden, then query the
          # browser. The query goes out after the flush that sends the
          # value, so the browser never reads a stale element.
          restore <- render_hidden_output(outputId, session = session,
                                          once = TRUE)
          query <- browser_request(max(seconds_left(), 0.1), sprintf(
            paste(
              "The output `%s` did not finish rendering within %s s; the",
              "session may be busy with a long computation. Try again later."
            ),
            outputId, format(timeout)
          ))
          cancel_query <- session$onFlushed(function() {
            if (!query_requests$has(query$id)) {
              return()
            }
            session$sendCustomMessage("shidashi.query_ui", list(
              selector = selector,
              request_id = query$id,
              input_id = input_id,
              transform_image = transform_image,
              # the browser answers before R gives up
              wait_ms = round(max(seconds_left() - 1, 0.1) * 1000),
              rendered = TRUE
            ))
          }, once = TRUE)

          promises::then(
            query$promise,
            onFulfilled = function(res) {
              size <- prepared$fallback_size
              if (length(size$width) == 1 && length(size$height) == 1) {
                res$note <- paste(c(sprintf(
                  paste(
                    "The output has never been shown, so it was drawn at a",
                    "fallback size of %sx%s px."
                  ),
                  size$width, size$height
                ), res$note[nzchar(res$note)]), collapse = " ")
              }
              content <- query_ui_content(res, transform_image = transform_image,
                                          max_chars = max_chars)

              # Outputs registered as htmlwidgets or as downloadable data
              # also return their data as text: a widget such as a DT table
              # shows only one page of it. The registry is missing outside a
              # running app (e.g. a mock session)
              entry <- tryCatch(get_session_entry(session$token),
                                error = function(e) NULL)
              renderer <- NULL
              if (!is.null(entry)) {
                renderer <- entry$output_renderers$get(outputId)
              }
              download_type <- if (is.list(renderer)) renderer$download_type
              if (!isTRUE(download_type %in% c("htmlwidget", "data"))) {
                return(content)
              }

              read_data <- function() {
                if (identical(download_type, "htmlwidget")) {
                  # print() stops early, so a huge data frame stays cheap
                  old_opts <- options(max.print = max(max_chars, 100L))
                  on.exit(options(old_opts), add = TRUE)
                  widget <- eval(renderer$render_expr,
                                 envir = new.env(parent = renderer$render_env))
                  # a render function such as `DT::renderDataTable` also
                  # takes a plain data frame
                  x <- widget
                  if (inherits(widget, "htmlwidget")) {
                    x <- .subset2(widget, "x")
                  }
                  return(utils::capture.output({
                    print(list(class = class(widget), content = x))
                  }))
                }

                if (!is.function(renderer$download_function)) {
                  return("[shidashi] This output has no download function.")
                }
                extension <- ""
                if (length(renderer$extension)) {
                  extension <- gsub("^[\\.]{0,}", ".", renderer$extension[[1]])
                }
                tmp <- tempfile(fileext = extension)
                on.exit(unlink(tmp), add = TRUE)
                renderer$download_function(tmp)
                size <- file.size(tmp)
                if (is.na(size) || size == 0) {
                  return("[shidashi] The download function wrote no data.")
                }
                if (any(readBin(tmp, "raw", n = min(size, 8192)) == as.raw(0))) {
                  return(sprintf(paste(
                    "[shidashi] The data is a binary file of %s bytes;",
                    "it cannot be shown as text."
                  ), format(size)))
                }
                iconv(rawToChar(readBin(tmp, "raw", n = size)),
                      from = "UTF-8", to = "UTF-8", sub = "?")
              }

              text <- tryCatch(
                shiny::withReactiveDomain(session, shiny::isolate(read_data())),
                error = function(e) {
                  reason <- conditionMessage(e)
                  if (!nzchar(reason)) {
                    # e.g. `req()`, which stops without a message
                    reason <- "the output is not ready."
                  }
                  paste("[shidashi] Could not get the data:", reason)
                }
              )
              text <- paste(text, collapse = "\n")
              total <- nchar(text)
              if (total > max_chars) {
                # cut at a line break, so printed tables stay aligned
                text <- substr(text, 1, max_chars)
                line_end <- max(gregexpr("\n", text, fixed = TRUE)[[1]])
                if (line_end > 1) {
                  text <- substr(text, 1, line_end - 1)
                }
                text <- sprintf(paste(
                  "%s\n[shidashi] trimmed: showing %d of %d characters.",
                  "Use a larger max_chars."
                ), text, nchar(text), total)
              }
              heading <- if (identical(download_type, "htmlwidget")) {
                paste("Full data of this widget (the page may show only part",
                      "of it, e.g. one page of a table):")
              } else {
                "Data of this output, as its download button saves it:"
              }

              if (is.character(content)) {
                content <- lapply(content[nzchar(content)], ellmer::ContentText)
              } else if (S7::S7_inherits(content, ellmer::Content)) {
                content <- list(content)
              }
              c(content, list(ellmer::ContentText(paste(heading, text,
                                                        sep = "\n"))))
            },
            onRejected = function(e) {
              cancel_query()
              restore()
              stop(e)
            }
          )
        })
      }
    )

    shiny_output_info <- ellmer::tool(
      name = "shiny_output_info",
      description = paste(
        "List registered Shiny output elements. When outputIds is omitted,",
        "returns all registered outputs with their descriptions. Get an",
        "output's rendered content with `shiny_output_result(outputId)`,",
        "which also works when the output is in a hidden tab or card."
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
      shiny_output_info = shiny_output_info,
      shiny_output_result = shiny_output_result
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

# Make HTML cheaper for an agent to read: shorten long data URIs, drop
# script and style bodies, remove whitespace between tags, and cut at a tag
# boundary when longer than `max_chars`, saying how much was cut.
mcp_trim_html <- function(html, max_chars = 10000L) {
  html <- paste(as.character(html), collapse = "\n")
  if (!nzchar(html)) {
    return(html)
  }

  uris <- gregexpr("data:[^,\"'\\s)]*,[^\"'\\s)<>]{100,}", html, perl = TRUE)
  regmatches(html, uris) <- lapply(regmatches(html, uris), function(found) {
    vapply(found, function(uri) {
      comma <- regexpr(",", uri, fixed = TRUE)
      sprintf("%s...(%d characters omitted)", substr(uri, 1, comma),
              nchar(uri) - comma)
    }, "")
  })

  html <- gsub("(?is)(<(script|style)\\b[^>]*>).*?(</\\2\\s*>)",
               "\\1...(omitted)\\3", html, perl = TRUE)
  html <- gsub(">\\s+<", "><", html, perl = TRUE)
  html <- gsub("\\s{2,}", " ", html, perl = TRUE)
  html <- trimws(html)

  total <- nchar(html)
  if (total <= max_chars) {
    return(html)
  }
  kept <- substr(html, 1, max_chars)
  tag_ends <- gregexpr(">", kept, fixed = TRUE)[[1]]
  last_tag_end <- max(tag_ends)
  if (last_tag_end > 0 && max_chars - last_tag_end <= 200) {
    kept <- substr(kept, 1, last_tag_end)
  }
  sprintf(
    paste(
      "%s\n<!-- [shidashi] trimmed: showing %d of %d characters. Use a more",
      "specific selector, or a larger max_chars. -->"
    ),
    kept, nchar(kept), total
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
      safe_observe({
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
      }, domain = session, label = "output download dialog"),
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
      download_type = download_type,
      download_function = download_function
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

    # Also add hook functions
    switch(
      download_type,
      "threeBrain" = {

        if (system.file(package = "threeBrain") != "") {
          shidashi <- asNamespace("shidashi")

          shiny::bindEvent(
            safe_observe(
              bquote({
                tryCatch(
                  expr = {

                    shidashi <- asNamespace("shidashi")
                    theme <- shidashi$get_theme()
                    if (!is.list(theme) ||
                        length(theme$background) != 1 ||
                        !is.character(theme$background)) {
                      return()
                    }
                    bgcolor <- substr(grDevices::adjustcolor(theme$background), 1, 7)

                    threeBrain <- asNamespace("threeBrain")
                    proxy <- threeBrain$brain_proxy(outputId = .(outputId))
                    proxy$set_background(bgcolor)

                  },
                  error = function(e) {},
                  warning = function(e) {}
                )
              }),
              quoted = TRUE,
              env = env,
              priority = -1L,
              domain = session,
              label = "threeBrain background"
            ),
            shidashi$get_theme(),
            ignoreNULL = TRUE,
            ignoreInit = TRUE
          )
        } # // if (system.file(package = "threeBrain") != "")
      },
      {
        # Default
      }
    )
  }

  invisible(NULL)
}

#' @title Render an Output Even When It Is Hidden
#' @description
#' By default \code{shiny} does not render outputs that are hidden, for
#' example inside an inactive tab or a collapsed card
#' (\code{suspendWhenHidden = TRUE}). \code{render_hidden_output()} turns
#' this off for one output, so the output renders at the next flush even
#' when hidden. With \code{once = TRUE}, the option is restored after that
#' flush.
#' @param outputId character string.  The \code{shiny} output ID (without
#'   the module namespace prefix).
#' @param session the \code{shiny} session object.
#' @param once logical (default \code{TRUE}).  Whether to restore the
#'   option after the next flush; when \code{FALSE}, the output keeps
#'   rendering while hidden until the returned function is called.
#' @return A function (invisible) that restores the option; calling it
#'   more than once has no further effect.  Nothing is changed when the
#'   output already renders while hidden.
#' @examples
#' \dontrun{
#' # inside a shidashi module server function:
#' register_output(renderPlot({ plot(1:10) }), outputId = "my_plot")
#'
#' # render `my_plot` once, even while its tab is not shown
#' render_hidden_output("my_plot")
#' }
#' @export
render_hidden_output <- function(
  outputId,
  session = shiny::getDefaultReactiveDomain(),
  once = TRUE
) {
  if (is.null(session)) {
    stop("shidashi::render_hidden_output must run in a shiny session.")
  }
  output <- session$output
  opts <- tryCatch(
    shiny::outputOptions(output, outputId),
    error = function(e) {
      stop("Output `", outputId, "` is not defined in this session.",
           call. = FALSE)
    }
  )

  restore <- function() {
    invisible()
  }

  # `opts` is NULL only for sessions that cannot set output options, such
  # as `shiny::MockShinySession`; an unset option means TRUE (the default)
  if (!is.null(opts) && !isFALSE(opts$suspendWhenHidden)) {
    # Resumes the output; if it was invalidated while hidden, it runs at
    # the next flush
    shiny::outputOptions(output, outputId, suspendWhenHidden = FALSE)

    restored <- FALSE
    cancel_hook <- NULL
    restore <- function() {
      if (restored) {
        return(invisible())
      }
      restored <<- TRUE
      if (is.function(cancel_hook)) {
        cancel_hook()
      }
      if (!isTRUE(session$isClosed())) {
        shiny::outputOptions(output, outputId, suspendWhenHidden = TRUE)
      }
      invisible()
    }
    if (isTRUE(once)) {
      # Flush callbacks run after the output values are sent (and wait for
      # async outputs), so the value is out before the option is restored
      cancel_hook <- session$onFlushed(restore, once = TRUE)
    }
  }

  # Make sure a flush happens even when nothing is pending, so the
  # callback runs; not `session$flushOutput()`, which would flush before
  # the output runs
  tryCatch(session$requestFlush(), error = function(e) NULL)

  invisible(restore)
}


#' @title Shiny render plot function with automated theme switcher
#' @description
#' A wrapper around \code{\link[shiny]{renderPlot}}, but with themes
#' automatically set via \code{\link[graphics]{par}}; only supports
#' base plots. For \pkg{ggplot2}, please manually call
#' \code{\link{get_theme}} to get the theme.
#'
#' @param expr,env,quoted,... passed to \code{\link[shiny]{renderPlot}}
#' @returns See \code{\link[shiny]{renderPlot}}
#'
#' @examples
#'
#' server <- function(input, output, session) {
#'
#'   output$plot <- renderPlot2({
#'     plot(rnorm(100))
#'   })
#'
#' }
#'
#' @export
renderPlot2 <- function(expr, ..., env = parent.frame(), quoted = FALSE) {
  func <- shiny::exprToFunction(expr, env, quoted)
  shiny::renderPlot({
    .theme <- shidashi::get_theme()
    if (is.list(.theme)) {
      .theme <- list(fg = .theme$foreground %||% "#000000",
                     bg = .theme$background %||% "#FFFFFF")
      .oldpar <- graphics::par(
        fg = .theme$fg,
        bg = .theme$bg,
        col = .theme$fg,
        col.axis = .theme$fg,
        col.lab = .theme$fg,
        col.main = .theme$fg,
        col.sub = .theme$fg
      )
      on.exit({
        graphics::par(.oldpar)
      }, add = TRUE)
    }
    func()
  }, ...)
}

