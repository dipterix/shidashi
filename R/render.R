
#' Render a 'shidashi' project
#' @param root_path the project path, default is the demo folder from
#' \code{template_root()}
#' @param ... additional parameters passed to \code{\link[shiny]{runApp}},
#' such as \code{host}, \code{port}
#' @param launch_browser whether to launch browser; default is \code{TRUE}
#' @param as_job whether to run as 'RStudio' jobs; this options is only
#' available when 'RStudio' is available
#' @param test_mode whether to test the project; this options is helpful when
#' you want to debug the project without relaunching shiny applications
#' @param prelaunch expression to execute before launching the session; the
#' expression will execute in a brand new session
#' @param prelaunch_quoted whether the expression is quoted; default is false
#' @return This functions runs a 'shiny' application, and returns the job id
#' if 'RStudio' is available.
#'
#' @examples
#'
#' template_root()
#'
#' if(interactive()) {
#'   render()
#' }
#'
#' @export
render <- function(
  root_path = template_root(),
  ...,
  prelaunch = NULL,
  prelaunch_quoted = FALSE,
  launch_browser = TRUE,
  as_job = TRUE,
  test_mode = getOption("shiny.testmode", FALSE)
) {
  if (!dir.exists(root_path)) {
    stop("`root_path` cannot be found: ", root_path)
  }
  root_path <- normalizePath(root_path, mustWork = TRUE, winslash = "/")

  if (!prelaunch_quoted) {
    prelaunch <- substitute(prelaunch)
  }

  # Resolve port: use caller-supplied port= or pick a random one.
  dots <- list(...)
  mcp_port <- dots[["port"]]
  if (is.null(mcp_port)) {
    mcp_port <- httpuv::randomPort()
  }
  dots[["port"]] <- mcp_port

  # Write port record and keep proxy up-to-date in user cache.
  setup_mcp_proxy(port = mcp_port, overwrite = TRUE, verbose = FALSE)

  # Copy global.R from inst/ so that shinyAppDir sources it at startup.
  # global.R calls shidashi::init_app() to create per-application state.
  global_src <- system.file("global.R", package = "shidashi")
  if (nzchar(global_src)) {
    file.copy(global_src, file.path(root_path, "global.R"), overwrite = TRUE)
  }

  # Write template_settings$set into ui.R so shinyAppDir picks up the correct
  # root_path regardless of working directory or how the app is launched.
  writeLines(
    c(
      sprintf('shidashi::template_settings$set("root_path" = "%s")', root_path),
      "shidashi::adminlte_ui()"
    ),
    file.path(root_path, "ui.R")
  )

  if (!as_job || system.file(package = "rstudioapi") == "" ||
     !rstudioapi::isAvailable(version_needed = "1.4.1717",
                              child_ok = FALSE)) {

    shidashi::template_settings$set("root_path" = root_path)
    eval(prelaunch, envir = new.env(parent = globalenv()))

    # Use shinyAppDir so that ui.R / server.R are loaded normally, then
    # chain the MCP handler in front of Shiny's built-in httpHandler.
    app <- register_mcp_route(shiny::shinyAppDir(root_path))
    do.call(shiny::runApp, c(
      list(appDir = app, launch.browser = launch_browser, test.mode = test_mode),
      dots
    ))
  } else {
    script <- file.path(root_path, "_rs_job.R")

    # Build app object in the job script so httpHandler is attached
    run_call <- as.call(c(
      list(quote(shiny::runApp)),
      list(
        appDir = quote(app),
        launch.browser = launch_browser,
        test.mode = test_mode
      ),
      dots
    ))
    s <- c(
      'options("crayon.enabled" = TRUE)',
      'options("crayon.colors" = 256)\n',
      deparse(prelaunch),
      "\n",
      sprintf("app <- shidashi:::register_mcp_route(shiny::shinyAppDir(\"%s\"))", root_path),
      deparse(run_call)
    )
    writeLines(
      con = script,
      s
    )
    rstudioapi::jobRunScript(
      path = script, workingDir = root_path,
      name = basename(root_path)
    )
  }

}

#' Template function to include 'snippets' in the view folder
#' @description Store the reusing 'HTML' segments in the
#' \code{views} folder. This function should be used in the
#' \code{'index.html'} template
#' @param file files in the template \code{views} folder
#' @param ... ignored
#' @param .env,.root_path internally used
#' @return rendered 'HTML' segments
#' @examples
#' \dontrun{
#' # in your 'index.html' file
#' <html>
#' <header>
#' {{ shidashi::include_view("header.html") }}
#' </header>
#' <body>
#'
#' </body>
#' <!-- Before closing html tag -->
#' {{ shidashi::include_view("footer.html") }}
#' </html>
#' }
#' @export
include_view <- function(file, ..., .env = parent.frame(),
                         .root_path = template_root()) {
  tryCatch({
    file <- normalizePath(file.path(.root_path, "views", file),
                          mustWork = TRUE)
  }, error = function(e) {
    stop(call. = NULL, "Cannot find views/", file)
  })
  list2env(list(.env = .env), envir = .GlobalEnv)
  args <- NULL
  if (is.environment(.env$env)) {
    args <- get0("@args", envir = .env$env, ifnotfound = NULL)
  }
  if (!is.list(args)) {
    args <- as.list(.env)
  }
  # more_args <- list(...)
  # for(nm in names(more_args)) {
  #   if (nm != "") {
  #     args[[nm]] <- more_args[[nm]]
  #   }
  # }
  argnames <- names(args)
  args <- args[!argnames %in% c("headContent", "suppressDependencies", "filename", "document_", "text_")]
  call <- as.call(c(
    list(quote(shiny::htmlTemplate),
         filename = file,
         document_ = FALSE),
    args
  ))
  return(eval(call, envir = .env))
  # shiny::htmlTemplate(file, ..., document_ = FALSE)
}

#' Reset shiny outputs with messages
#' @description Forces outdated output to reset and show a silent message.
#' @param outputId output ID
#' @param message output message
#' @param session shiny reactive domain
#' @return No value
#' @export
reset_output <- function(outputId, message = "This output has been reset",
                         session = shiny::getDefaultReactiveDomain()) {
  session$sendCustomMessage("shidashi.reset_output", list(
    outputId = session$ns(outputId),
    message = message
  ))
}
