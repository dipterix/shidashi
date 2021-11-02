{
    shinytemplates::template_settings$set(root_path = "/Users/dipterix/Dropbox (Personal)/projects/shinytemplates/inst/templates/AdminLTE")
    do.call(shiny::runApp, list(launch.browser = TRUE, test.mode = TRUE, 
        appDir = "/Users/dipterix/Dropbox (Personal)/projects/shinytemplates/inst/templates/AdminLTE"))
}
