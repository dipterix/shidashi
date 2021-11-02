#' @export
register_session_id <- function(session = shiny::getDefaultReactiveDomain(),
                                shared_id = NULL, env = parent.frame(),
                                watch_list){

  if(length(shared_id)){
    if(grepl("[^a-z0-9_]", shared_id)){
      stop("session `shared_id` must only contain letters (lower-case), digits, and/or '_'.")
    }
  } else {
    # obtain the shared ID
    shared_id <- session$cache$get("shinytemplates_shared_id", NULL)
    if(length(shared_id) != 1 || !is.character(shared_id)){
      shared_id <- rand_string(length = 26)
      shared_id <- tolower(shared_id)
    }
  }
  session$cache$set("shinytemplates_shared_id", shared_id)

  if(!session$cache$exists("shinytemplates_private_id")){
    is_registerd <- FALSE
    private_id <- rand_string(length = 8)
    session$cache$set("shinytemplates_private_id", private_id)
  } else {
    is_registerd <- TRUE
    private_id <- session$cache$get("shinytemplates_private_id")
  }

  watch_all <- FALSE
  if(missing(watch_list)){
    watch_all <- TRUE
  }

  # set up shared_id bucket
  if(!is_registerd && (watch_all || length(watch_list))){
    input_observer <- shiny::observe({
      inputs <- shiny::reactiveValuesToList(session$input)
      if(watch_all) {
        nms <- names(inputs)
      } else {
        inputs <- inputs[watch_list]
        nms <- watch_list
      }

      sel <- !startsWith(nms, "@")
      if(length(sel) && any(sel)){
        nms <- nms[sel]
        inputs <- inputs[sel]
        names(inputs) <- session$ns(nms)
        sig <- session$cache$get("shinytemplates_input_signature", NULL)
        sig2 <- digest::digest(inputs)
        if(!identical(sig2, sig)){
          session$cache$set("shinytemplates_input_signature", sig2)
          message <- list(
            shared_id = shared_id,
            private_id = private_id,
            inputs = inputs
          )
          session$sendCustomMessage("shinytemplates.cache_session_input", message)
        }

      }
    }, domain = session, priority = -100000)
  }

}
