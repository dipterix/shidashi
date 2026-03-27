#' Initialise the shidashi stream directory for a Shiny session
#'
#' Call once in the server function to set up the directory that
#' \code{\link{stream_path}} and \code{\link{stream_to_js}} will write to.
#' When running inside a shidashi template the directory is automatically
#' resolved from the template root; when running in plain Shiny a temporary
#' directory is created and registered with
#' \code{\link[shiny]{addResourcePath}} so that the browser can fetch
#' \code{stream/{token}_{id}.bin}.  An optional cleanup hook is registered
#' to remove this session's files when the session ends.
#'
#' @param session Shiny session object.  Defaults to the currently active
#'   reactive domain.
#' @return Invisibly returns the absolute path to the stream directory.
#' @seealso \code{\link{stream_path}}, \code{\link{stream_to_js}}
#' @export
stream_init <- function(session = shiny::getDefaultReactiveDomain()) {
  in_shidashi <- !is.null(template_settings$get("root_path", NULL))
  if (in_shidashi) {
    path <- file.path(template_root(), "www", "stream")
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  } else {
    path <- file.path(tempdir(), "shidashi-stream")
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    shiny::addResourcePath("stream", path)
  }
  Sys.setenv(SHIDASHI_STREAM_PATH = path)
  # Clean up this session's files when the session ends
  if (!is.null(session)) {
    token <- session$token
    session$onSessionEnded(function() {
      files <- list.files(path, pattern = paste0("^", token, "_"),
                          full.names = TRUE)
      unlink(files)
    })
  }
  invisible(path)
}

#' Get the absolute path for a shidashi stream file
#'
#' Returns the full path to the binary file that will be served at
#' \code{stream/{token}_{id}.bin}.  The filename embeds the session token so
#' that simultaneous Shiny sessions never overwrite each other's data.
#' Call \code{\link{stream_init}} at least once per session before relying on
#' this function.
#'
#' @param id Character scalar. Stream identifier.  Must be a valid file-name
#'   component (no path separators).
#' @param session Shiny session object.  Defaults to the currently active
#'   reactive domain.
#' @return Invisible character scalar: absolute path to the \code{.bin} file.
#' @seealso \code{\link{stream_init}}, \code{\link{stream_to_js}}
#' @export
stream_path <- function(id, session = shiny::getDefaultReactiveDomain()) {
  stopifnot(is.character(id), length(id) == 1L, nzchar(id))
  env_path <- Sys.getenv("SHIDASHI_STREAM_PATH", unset = "")
  stream_dir <- if (nzchar(env_path)) {
    env_path
  } else {
    file.path(template_root(), "www", "stream")
  }
  dir.create(stream_dir, showWarnings = FALSE, recursive = TRUE)
  token <- if (!is.null(session)) session$token else "static"
  nsid  <- if (!is.null(session)) session$ns(id) else id
  invisible(file.path(stream_dir, paste0(token, "_", nsid, ".bin")))
}

#' Write data to a shidashi stream binary file
#'
#' Serialises \code{data} together with a JSON header into the binary
#' envelope expected by the JavaScript \code{window.shidashi.fetchStreamData(id)}
#' method.
#'
#' \strong{Wire format}
#' \preformatted{
#'   [endianFlag: 1 byte]  [headerLen: uint32 LE]  [header: UTF-8 JSON]  [body]
#' }
#' \code{endianFlag} is always \code{0x01} (little-endian).
#' \code{header} is a JSON object containing at minimum \code{data_type}
#' plus any extra fields passed via \code{...}.
#'
#' \strong{Body encoding by type}
#' \describe{
#'   \item{\code{"raw"}}{Passed through verbatim; \code{data} must be a
#'     \code{raw} vector or will be coerced via \code{as.raw()}.}
#'   \item{\code{"json"}}{\code{data} is serialised with
#'     \code{jsonlite::toJSON(auto_unbox = TRUE)}.}
#'   \item{\code{"int32"}}{\code{data} is coerced to integer and written as
#'     4-byte little-endian signed integers.}
#'   \item{\code{"float32"}}{\code{data} is coerced to double and written as
#'     4-byte little-endian IEEE 754 single-precision floats.}
#'   \item{\code{"float64"}}{\code{data} is coerced to double and written as
#'     8-byte little-endian IEEE 754 double-precision floats.}
#' }
#'
#' @param abspath Character scalar. Absolute path to the target \code{.bin}
#'   file.  Use \code{\link{stream_path}(id)} to obtain a path under the
#'   app's \code{www/stream/} directory.
#' @param data The data to serialise.  See Details for how each \code{type}
#'   interprets this argument.
#' @param type Character scalar. One of \code{"raw"}, \code{"json"},
#'   \code{"int32"}, \code{"float32"}, or \code{"float64"}.
#' @param ... Additional named scalar values to embed in the JSON header and
#'   expose to the JavaScript caller via \code{result.header}.
#' @return Invisibly returns \code{abspath}.
#' @seealso \code{\link{stream_path}}
#' @export
stream_to_js <- function(abspath, data,
                         type = c("raw", "json", "int32", "float32", "float64"),
                         ...) {
  type <- match.arg(type)

  # Build header JSON
  extra <- list(...)
  header_list <- c(list(data_type = type), extra)
  header_json <- jsonlite::toJSON(header_list, auto_unbox = TRUE)
  header_bytes <- charToRaw(header_json)

  # Encode body
  body_bytes <- switch(
    type,
    raw = {
      if (is.raw(data)) data else as.raw(data)
    },
    json = {
      charToRaw(jsonlite::toJSON(data, auto_unbox = TRUE))
    },
    int32 = {
      writeBin(as.integer(data), raw(), size = 4L, endian = "little")
    },
    float32 = {
      writeBin(as.double(data), raw(), size = 4L, endian = "little")
    },
    float64 = {
      writeBin(as.double(data), raw(), size = 8L, endian = "little")
    }
  )

  # Write binary envelope
  con <- file(abspath, "wb")
  on.exit(close(con), add = TRUE)

  # endianFlag: 0x01 = little-endian
  writeBin(as.raw(0x01L), con)
  # headerLen: 4-byte uint32 LE
  writeBin(as.integer(length(header_bytes)), con, size = 4L, endian = "little")
  # header JSON bytes
  writeBin(header_bytes, con)
  # body bytes
  writeBin(body_bytes, con)

  invisible(abspath)
}
