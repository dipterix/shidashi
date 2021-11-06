library(shiny)
page_title <- function(complete = TRUE){
  if(complete){
    "AdminLTE 3 | Shiny Dashboard"
  } else {
    "AdminLTE-Shiny Template"
  }
}
page_logo <- function(size = c("normal", "small", "large")){
  "dist/img/AdminLTELogo.png"
}
page_loader <- function(){
  # if no loader is needed, then return NULL
  shiny::div(
    class = "preloader flex-column justify-content-center align-items-center",
    shiny::img(
      class = "animation__shake",
      src = page_logo("large"),
      alt = "Logo", height="60", width="60"
    )
  )
}
body_class <- function(){
  c(
    # "hold-transition",
    # "sidebar-collapse",
    # "control-sidebar-slide-open",
    "layout-fixed", "dark-mode", #"layout-navbar-fixed",
    "sidebar-mini", "sidebar-mini-md", "sidebar-mini-xs",
    "fancy-scroll-y"
  )
}
nav_class <- function(){
  c(
    "main-header",
    "navbar",
    "navbar-expand",
    "navbar-dark",
    "navbar-primary"
  )
}

module_breadcrumb <- function(){}
