library(shiny)
page_title <- function(complete = TRUE){
  if(complete){
    "Shiny Dashboard Template - bslib"
  } else {
    "ShiDashi"
  }
}
page_logo <- function(size = c("normal", "small", "large")){
  "shidashi/img/icon.png"
}
page_loader <- function(){
  NULL
}
body_class <- function(){
  c(
    #--- Start as dark-mode ---
    "dark-mode",

    # drawer has no no-overlay
    "shidashi-drawer-no-overlay"
  )
}
nav_class <- function(){
  c(
    "shidashi-header",
    "navbar",
    "navbar-expand"
  )
}

sidebar_class <- function(){
  c(
    #--- Start as dark-mode ---
    "dark-mode"
  )
}

module_breadcrumb <- function(){}

drawer_ui <- function(){
  # Return the inner content for the drawer panel.
  # The outer .shidashi-drawer wrapper is provided by index.html.
  # Override this function in your project's R/common.R to add
  # custom drawer content (settings panels, controls, etc.)
  shiny::tagList(
    shiny::h5("Settings"),
    shiny::p(
      "This is the right-side drawer panel. ",
      "Customize this in ", shiny::tags$code("R/common.R"),
      " by editing the ", shiny::tags$code("drawer_ui()"), " function."
    ),
    shiny::hr(),
    shiny::tags$small(
      "Open with ", shiny::tags$code("drawer_open()"),
      " or the ", shiny::tags$i(class = "fas fa-cog"), " icon."
    ),
    shiny::hr(),
    shiny::p("Current module info can be obtained via ",
             shiny::tags$code("shidashi::active_module()"), ":"),
    shiny::verbatimTextOutput("drawer_output")
  )
}
