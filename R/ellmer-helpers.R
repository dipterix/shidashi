# ---- ellmer helpers: Content → MCP content serialization ----
#
# Bridges ellmer Content objects to MCP JSON-RPC content items.
#
# The MCP protocol defines its own content format:
#   - text:     {"type": "text", "text": "..."}
#   - image:    {"type": "image", "data": "base64...", "mimeType": "image/png"}
#   - resource: {"type": "resource", "resource": {"uri": "...", "mimeType": "..."}}
#
# This file provides:
#   - ProviderAny: fallback S7 Provider subclass producing MCP-format content
#   - as_json methods for ProviderAny + ellmer Content types
#   - get_mcp_provider(req): detect or default to ProviderAny
#   - content_to_mcp(ret, provider): convert tool return values to MCP content

# --- External generic reference ---

ellmer_as_json <- S7::new_external_generic("ellmer", "as_json", c("provider", "x"))

# --- Fallback MCP provider ---
# Used when we cannot determine the actual LLM provider from the request.
# Produces MCP-standard content format from as_json dispatch.

ProviderAny <- S7::new_class(
  name = "ProviderAny",
  parent = ellmer::Provider
)

# --- as_json methods for ProviderAny ---

# ContentText → MCP text content
S7::method(ellmer_as_json, list(ProviderAny, ellmer::ContentText)) <- function(provider, x, ...) {
  list(type = "text", text = x@text)
}

# ContentImageInline → MCP image content
S7::method(ellmer_as_json, list(ProviderAny, ellmer::ContentImageInline)) <- function(provider, x, ...) {
  list(type = "image", data = x@data, mimeType = x@type)
}

# ContentImageRemote → MCP resource content (URL reference)
S7::method(ellmer_as_json, list(ProviderAny, ellmer::ContentImageRemote)) <- function(provider, x, ...) {
  list(type = "resource", resource = list(uri = x@url, mimeType = "image/jpeg"))
}

# Generic Content fallback: extract S7 props
S7::method(ellmer_as_json, list(ProviderAny, ellmer::Content)) <- function(provider, x, ...) {
  nms <- S7::prop_names(x)
  nms <- nms[!nms %in% "request"]
  res <- S7::props(x, nms)
  # Wrap as text with JSON representation
  list(
    type = "text",
    text = as.character(
      jsonlite::toJSON(res, auto_unbox = TRUE, null = "null", force = TRUE)
    )
  )
}

# character → text content
S7::method(ellmer_as_json, list(ProviderAny, S7::class_character)) <- function(provider, x, ...) {
  list(type = "text", text = paste(x, collapse = "\n"))
}

# any → JSON-serialized text content
S7::method(ellmer_as_json, list(ProviderAny, S7::class_any)) <- function(provider, x, ...) {
  list(
    type = "text",
    text = as.character(
      jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", force = TRUE)
    )
  )
}

# --- Provider detection ---

#' Detect or create an ellmer Provider for MCP content serialization
#'
#' Examines the HTTP request headers (e.g. \code{User-Agent}) to try to
#' identify the upstream LLM provider.  Falls back to \code{ProviderAny}
#' which produces MCP-standard content format.
#'
#' @param req The Rook request environment, or \code{NULL}.
#' @return An \code{ellmer::Provider} instance.
#' @keywords internal
#' @noRd
get_mcp_provider <- function(req = NULL) {
  # TODO: detect actual provider from request headers
  # e.g. req$HTTP_USER_AGENT might contain "anthropic", "openai", etc.
  # For now, always return the MCP-format fallback provider.
  ProviderAny(name = "mcp", model = "unknown", base_url = "http://localhost")
}

# --- Content → MCP result conversion ---

#' Convert a tool return value to MCP content format
#'
#' Handles ellmer \code{Content} objects, \code{ContentToolResult},
#' lists of \code{Content}, plain strings, and arbitrary R objects.
#' Returns a list with \code{content} (array of MCP content items) and
#' \code{isError} (logical).
#'
#' @param ret The raw return value from a tool function.
#' @param provider An \code{ellmer::Provider} for content serialization.
#'   When \code{NULL}, \code{get_mcp_provider()} is used.
#' @return A list with \code{content} and \code{isError}.
#' @keywords internal
#' @noRd
content_to_mcp <- function(ret, provider = NULL) {
  if (is.null(provider)) {
    provider <- get_mcp_provider()
  }
  as_json_fn <- asNamespace("ellmer")[["as_json"]]

  # Unwrap ContentToolResult
  if (S7::S7_inherits(ret, ellmer::ContentToolResult)) {
    if (!is.null(ret@error)) {
      err_msg <- if (inherits(ret@error, "condition")) {
        conditionMessage(ret@error)
      } else {
        as.character(ret@error)
      }
      return(list(
        content = list(list(type = "text", text = paste("Error:", err_msg))),
        isError = TRUE
      ))
    }
    ret <- ret@value
  }

  # Single Content object
  if (S7::S7_inherits(ret, ellmer::Content)) {
    return(list(
      content = list(as_json_fn(provider, ret)),
      isError = FALSE
    ))
  }

  # List of Content objects
  if (is.list(ret) && length(ret) > 0) {
    is_content <- vapply(
      ret,
      function(x) S7::S7_inherits(x, ellmer::Content),
      logical(1)
    )
    if (all(is_content)) {
      return(list(
        content = lapply(ret, function(x) as_json_fn(provider, x)),
        isError = FALSE
      ))
    }
  }

  # NULL
  if (is.null(ret)) {
    return(list(
      content = list(list(type = "text", text = "<empty results>")),
      isError = FALSE
    ))
  }

  # Character
  if (is.character(ret)) {
    return(list(
      content = list(list(type = "text", text = paste(ret, collapse = "\n"))),
      isError = FALSE
    ))
  }

  # Other: JSON serialize and wrap in text content
  list(
    content = list(as_json_fn(provider, ret)),
    isError = FALSE
  )
}
