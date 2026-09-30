.onLoad <- function(libname, pkgname) {
  S7::methods_register()
  # Make sure at least one template exists
  tryCatch({
    template_root()
  }, error = function(e) {})
}


shidashi_finalize_installation <- function(
  upgrade = c("ask", "always", "never", "data-only", "config-only"),
  ...
) {

  setup_mcp_proxy(overwrite = TRUE, verbose = FALSE)

  # tools::R_user_dir("shidashi", which = "data")

  # cat(readLines('/Users/dipterix/Library/Application Support/Claude/claude_desktop_config.json'), sep = "\n")

}