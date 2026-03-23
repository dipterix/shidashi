.onLoad <- function(libname, pkgname) {
  S7::methods_register()
  # Make sure at least one template exists
  tryCatch({
    template_root()
  }, error = function(e){})
}
