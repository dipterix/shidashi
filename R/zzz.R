.onLoad <- function(libname, pkgname) {
  # Make sure at least one template exists
  tryCatch({
    template_root()
  }, error = function(e){})
}
