library(shiny)
page_title <- function(complete = TRUE) {
  if (complete) {
    "Shiny Dashboard Template - bslib"
  } else {
    "ShiDashi"
  }
}

page_logo <- function(size = c("normal", "small", "large")) {
  "shidashi/img/icon.png"
}
page_loader <- function() {
  NULL
}

body_class <- function() {
  c(
    #--- Start as dark-mode ---
    "dark-mode",

    # drawer has no no-overlay
    "shidashi-drawer-no-overlay"
  )
}

nav_class <- function() {
  c(
    "shidashi-header",
    "navbar",
    "navbar-expand"
  )
}

sidebar_class <- function() {
  c(
    #--- Start as dark-mode ---
    "dark-mode"
  )
}

module_breadcrumb <- function() {}
