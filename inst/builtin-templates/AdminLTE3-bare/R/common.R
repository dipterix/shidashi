library(shiny)
page_title <- function(complete = TRUE){
  if(complete){
    "Shiny Dashboard Template - Barebone"
  } else {
    "ShiDashi"
  }
}
page_logo <- function(size = c("normal", "small", "large")){
  # Relative path to your logo icon in www/
  # "shidashi/img/icon.png"
  NULL
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
    #--- Fix the navigation banner ---
    #"layout-navbar-fixed",

    #--- Collapse the sidebar at the beginning ---
    # "sidebar-collapse",

    #--- Let control sidebar open at the beginning ---
    # "control-sidebar-slide-open",

    #--- Fix the sidebar position ---
    "layout-fixed",

    #--- Default behavior when collapsing sidebar
    # "sidebar-mini", "sidebar-mini-md", "sidebar-mini-xs"

    #--- Hide the navbar-nav-iframe
    "navbar-iframe-hidden",

    #--- Start as dark-mode ---
    "dark-mode"

    #--- Make scrollbar thinner ---
    # "fancy-scroll-y"

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
