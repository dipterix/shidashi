# The stdio proxy shipped as a Claude plugin (inst/mcp-proxy/)

# The plugin files are left out of the built package (.Rbuildignore), so
# these tests only run from the source tree.
plugin_file <- function(...) {
  inst <- testthat::test_path("..", "..", "inst")
  if (!dir.exists(inst)) {
    testthat::skip("plugin files are not part of the built package")
  }
  file.path(inst, "mcp-proxy", ...)
}

skip_without_node <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("processx")
  testthat::skip_if(!nzchar(Sys.which("node")), "node is not installed")
}

# A copy of the proxy in a folder that is not `mcp_server/`, like the one
# Claude installs a plugin into
plugin_copy <- function() {
  dir <- tempfile("plugin-")
  dir.create(dir)
  file.copy(
    system.file("mcp-proxy", "shidashi-proxy.mjs", package = "shidashi"),
    file.path(dir, "shidashi-proxy.mjs")
  )
  file.path(dir, "shidashi-proxy.mjs")
}

# Write a proxy-meta.json whose instructions carry `marker`
write_marker_meta <- function(cache, marker) {
  dir.create(file.path(cache, "mcp_server"), recursive = TRUE,
             showWarnings = FALSE)
  writeLines(
    jsonlite::toJSON(list(
      instructions = marker,
      tools = list(list(
        name = "marker_tool",
        inputSchema = list(type = "object")
      ))
    ), auto_unbox = TRUE),
    file.path(cache, "mcp_server", "proxy-meta.json")
  )
}

# Environment for a child process: the cache variables are cleared unless
# given (an empty value counts as unset, as in R)
proxy_env <- function(...) {
  env <- c(SHIDASHI_CACHE_DIR = "", R_USER_CACHE_DIR = "", XDG_CACHE_HOME = "")
  given <- c(...)
  env[names(given)] <- given
  c("current", env)
}

# Send JSON-RPC requests to the proxy; returns the responses by id
run_proxy <- function(script, env, requests) {
  input <- tempfile(fileext = ".jsonl")
  writeLines(vapply(requests, jsonlite::toJSON, "", auto_unbox = TRUE), input)
  result <- processx::run("node", script, env = env, stdin = input,
                          timeout = 20)
  lines <- strsplit(result$stdout, "\n", fixed = TRUE)[[1]]
  messages <- lapply(lines[nzchar(lines)], jsonlite::fromJSON,
                     simplifyVector = FALSE)
  messages <- Filter(function(m) !is.null(m$id), messages)
  structure(messages, names = vapply(messages, function(m) {
    as.character(m$id)
  }, ""))
}

initialize_request <- list(jsonrpc = "2.0", id = "init",
                           method = "initialize", params = list())
tools_list_request <- list(jsonrpc = "2.0", id = "tools",
                           method = "tools/list", params = list())

tool_names <- function(response) {
  vapply(response$result$tools, `[[`, "", "name")
}

test_that("the plugin manifest names the package and its release", {
  manifest <- jsonlite::fromJSON(
    plugin_file(".claude-plugin", "plugin.json"), simplifyVector = FALSE
  )
  expect_identical(manifest$name, "shidashi")
  # The plugin and the package share major.minor.patch, but the development
  # number (the fourth part) may differ
  release <- function(version) format(package_version(version)[, 1:3])
  expect_identical(release(manifest$version),
                   release(utils::packageDescription("shidashi")$Version))
})

test_that("the plugin starts the proxy that ships next to it", {
  config <- jsonlite::fromJSON(plugin_file(".mcp.json"),
                               simplifyVector = FALSE)
  server <- config$mcpServers$shidashi
  expect_identical(server$command, "node")
  expect_identical(unlist(server$args),
                   "${CLAUDE_PLUGIN_ROOT}/shidashi-proxy.mjs")
  expect_true(file.exists(plugin_file("shidashi-proxy.mjs")))
})

test_that("the proxy uses the cache folder named by SHIDASHI_CACHE_DIR", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  write_marker_meta(cache, "from SHIDASHI_CACHE_DIR")
  writeLines(
    jsonlite::toJSON(list(saved_marker_app = list(
      root_path = tempdir(), modules = list("demo")
    )), auto_unbox = TRUE),
    file.path(cache, "launchers.json")
  )

  responses <- run_proxy(
    plugin_copy(),
    proxy_env(SHIDASHI_CACHE_DIR = cache),
    list(
      initialize_request,
      tools_list_request,
      list(jsonrpc = "2.0", id = "launchers", method = "tools/call",
           params = list(name = "shidashi_launchers",
                         arguments = structure(list(), names = character())))
    )
  )
  expect_match(responses$init$result$instructions, "from SHIDASHI_CACHE_DIR",
               fixed = TRUE)
  expect_true("marker_tool" %in% tool_names(responses$tools))
  expect_match(responses$launchers$result$content[[1]]$text,
               "saved_marker_app", fixed = TRUE)
})

test_that("the proxy finds the cache folder the way tools::R_user_dir does", {
  skip_without_node()
  home <- tempfile("home-")
  dir.create(home)
  cases <- list(
    list(R_USER_CACHE_DIR = tempfile("r-user-cache-")),
    list(XDG_CACHE_HOME = tempfile("xdg-cache-")),
    # the platform default under the user's home folder
    list(HOME = home, LOCALAPPDATA = file.path(home, "AppData", "Local"))
  )
  for (case in cases) {
    env <- do.call(proxy_env, case)
    expected <- processx::run(
      file.path(R.home("bin"), "Rscript"),
      c("--vanilla", "-e", "cat(tools::R_user_dir('shidashi', 'cache'))"),
      env = env
    )$stdout
    marker <- paste("R_user_dir", names(case)[[1]])
    write_marker_meta(expected, marker)

    responses <- run_proxy(plugin_copy(), env, list(initialize_request))
    expect_match(responses$init$result$instructions, marker, fixed = TRUE)
  }
})

test_that("a proxy copied into mcp_server/ uses the folder it sits in", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  old <- options(shidashi.cache_dir = cache)
  on.exit(options(old), add = TRUE)
  script <- setup_mcp_proxy(verbose = FALSE)

  responses <- run_proxy(script, proxy_env(),
                         list(initialize_request, tools_list_request))
  expect_match(responses$init$result$instructions, "_module", fixed = TRUE)
  expect_true("shidashi_sessions" %in% tool_names(responses$tools))
})

test_that("the proxy finishes a long last reply before it exits", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  write_marker_meta(cache, strrep("long instructions ", 20000))

  responses <- run_proxy(plugin_copy(),
                         proxy_env(SHIDASHI_CACHE_DIR = cache),
                         list(initialize_request))
  expect_gt(nchar(responses$init$result$instructions), 300000)
})

test_that("the proxy reads meta tools written after it started", {
  skip_without_node()
  cache <- tempfile("shidashi-cache-")
  dir.create(cache)
  proc <- processx::process$new(
    "node", plugin_copy(),
    env = proxy_env(SHIDASHI_CACHE_DIR = cache),
    stdin = "|", stdout = "|", stderr = "|"
  )
  on.exit(proc$kill(), add = TRUE)

  ask <- function(request) {
    proc$write_input(paste0(jsonlite::toJSON(request, auto_unbox = TRUE), "\n"))
    deadline <- Sys.time() + 10
    while (Sys.time() < deadline) {
      proc$poll_io(500)
      line <- proc$read_output_lines(n = 1)
      if (length(line)) {
        message <- jsonlite::fromJSON(line, simplifyVector = FALSE)
        if (identical(message$id, request$id)) return(message)
      }
    }
    stop("the proxy did not answer ", request$id)
  }

  before <- ask(tools_list_request)
  expect_false("marker_tool" %in% tool_names(before))

  write_marker_meta(cache, "written later")
  after <- ask(tools_list_request)
  expect_true("marker_tool" %in% tool_names(after))
  expect_match(ask(initialize_request)$result$instructions, "written later",
               fixed = TRUE)
})
