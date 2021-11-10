sync_inputs <- function(session = shiny::getDefaultReactiveDomain()) {

  shared_id <- session$cache$get("shidashi_shared_id")
  private_id <- session$cache$get("shidashi_private_id")
  if(length(shared_id) != 1 || length(private_id) != 1 ||
     !is.character(shared_id) || !is.character(private_id)){
    stop("Invalid session IDs, run `register_session_id()` first to register.")
  }

  root_session <- session$rootScope()

  reactives <- root_session$cache$get("shidashi_sync_inputs", NULL)

  if(!shiny::is.reactivevalues(reactives)){
    reactives <- shiny::reactiveValues()
    root_session$cache$set("shidashi_sync_inputs", reactives)
  }

  observer <- root_session$cache$get("shidashi_sync_handler", NULL)

  if(is.null(observer)){
    observer <- shiny::observeEvent({
      root_session$input[["@shidashi@"]]
    }, {
      try({
        message <- RcppSimdJson::fparse(root_session$input[["@shidashi@"]])

        if(identical(message$last_edit, private_id)){
          return()
        }

        input_names <- shiny::isolate({ names(root_session$input) })
        input_names <- input_names[!startsWith(input_names, "@")]
        input_names <- input_names[input_names %in% names(message$inputs)]
        if(!length(input_names)) { return() }

        lapply(input_names, function(nm){
          v <- message$inputs[[nm]]
          v2 <- shiny::isolate(root_session$input[[nm]])
          if(!identical(v, v2)){
            reactives[[nm]] <- v
          }
        })

        # input_names <- input_names[sel]
        #
        # if(!length(input_names)) { return() }
        #
        # print(message$inputs[input_names])
        # list2env(list(root_session = root_session), envir=.GlobalEnv)
        # do.call(root_session$setInputs, message$inputs[input_names])

      }, silent = FALSE)
    }, domain = root_session, ignoreNULL = TRUE, ignoreInit = TRUE,
    suspended = TRUE)

    root_session$cache$set("shidashi_sync_handler", observer)
  }

  list(
    reactives = reactives,
    sync_observer = observer
  )

}


#' @export
register_session_id <- function(
  session = shiny::getDefaultReactiveDomain(),
  shared_id = NULL, env = parent.frame(),
  shared_inputs = NA){

  if(length(shared_id)){
    if(grepl("[^a-z0-9_]", shared_id)){
      stop("session `shared_id` must only contain letters (lower-case), digits, and/or '_'.")
    }
  } else {
    # obtain the shared ID
    shared_id <- session$cache$get("shidashi_shared_id", NULL)
    if(length(shared_id) != 1 || !is.character(shared_id)){
      # get from session
      query_list <- httr::parse_url(shiny::isolate(session$clientData$url_search))
      shared_id <- query_list$query$shared_id
      shared_id <- tolower(shared_id)
      if(is.null(shared_id) || grepl("[^a-z0-9_]", shared_id)){
        shared_id <- rand_string(length = 26)
        shared_id <- tolower(shared_id)
      }
    }
  }
  session$cache$set("shidashi_shared_id", shared_id)

  if(!session$cache$exists("shidashi_private_id")){
    is_registerd <- FALSE
    private_id <- rand_string(length = 8)
    session$cache$set("shidashi_private_id", private_id)
  } else {
    is_registerd <- TRUE
    private_id <- session$cache$get("shidashi_private_id")
  }

  # set up shared_id bucket
  broadcast_observer <- session$cache$get(
    "shidashi_broadcast_handler", NULL)

  if( is.null(broadcast_observer) ){
    broadcast_observer <- shiny::observe({
      inputs <- shiny::reactiveValuesToList(session$input)
      nms <- names(inputs)

      sel <- !startsWith(nms, "@")
      if(length(sel) && any(sel)){
        nms <- nms[sel]
        inputs <- inputs[sel]
        names(inputs) <- session$ns(nms)
        sig <- session$cache$get("shidashi_input_signature", NULL)
        sig2 <- digest::digest(inputs)
        if(!identical(sig2, sig)){
          session$cache$set("shidashi_input_signature", sig2)
          message <- list(
            shared_id = shared_id,
            private_id = private_id,
            inputs = inputs
          )
          session$sendCustomMessage("shidashi.cache_session_input", message)
        }

      }
    }, domain = session, priority = -100000, suspended = TRUE)

    session$cache$set(
      "shidashi_broadcast_handler", broadcast_observer)

  }

  res <- sync_inputs(session = session)
  res$broadcast_observer <- broadcast_observer

  res$disable_broadcast <- function(){
    res$broadcast_observer$suspend()
  }
  res$enable_broadcast <- function(once = FALSE){
    if(once){
      res$broadcast_observer$run()
    } else {
      res$broadcast_observer$resume()
    }
  }
  res$disable_sync <- function(){
    res$sync_observer$suspend()
  }
  res$enable_sync <- function(once = FALSE){
    if(once){
      res$sync_observer$run()
    } else {
      res$sync_observer$resume()
    }
  }

  res
}



