sync_inputs <- function(session = shiny::getDefaultReactiveDomain()) {

  # shared_id <- session$cache$get("shidashi_shared_id")
  shared_id <- session$userData$shidashi$shared_id

  # private_id <- session$cache$get("shidashi_private_id")
  private_id <- session$userData$shidashi$private_id

  if(length(shared_id) != 1 || length(private_id) != 1 ||
     !is.character(shared_id) || !is.character(private_id)){
    stop("Invalid session IDs, run `register_session_id()` first to register.")
  }

  root_session <- session$rootScope()

  # reactives <- root_session$cache$get("shidashi_sync_inputs", NULL)
  reactives <- root_session$userData$shidashi$input_reactives

  if(!shiny::is.reactivevalues(reactives)){
    reactives <- shiny::reactiveValues()
    root_session$userData$shidashi$input_reactives <- reactives
  }

  observer <- root_session$userData$shidashi$input_sync_handler
  if(is.null(observer)){
    observer <- shiny::observeEvent({
      root_session$input[["@shidashi@"]]
    }, {
      try({
        message <- jsonlite::fromJSON(root_session$input[["@shidashi@"]])

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

    root_session$userData$shidashi$input_sync_handler <- observer
  }

  # ----- backward compatible
  root_session$cache$set("shidashi_sync_inputs", reactives)
  root_session$cache$set("shidashi_sync_handler", observer)

  list(
    reactives = reactives,
    sync_observer = observer
  )

}

#' @name javascript-tunnel
#' @title The 'JavaScript' tunnel
#' @param session shiny reactive domain
#' @param shared_id the shared id of the session, usually automatically set
#' @param shared_inputs the input names to share to/from other sessions
#' @param event_data a reactive value list returned by
#' \code{register_session_events}
#' @param type event type; see 'Details'
#' @param default default value if \code{type} is missing
#' @return \code{register_session_id} returns a list of function to control
#' "sharing" inputs with other shiny sessions with the same \code{shared_id}.
#' \code{register_session_events} returns a reactive value list that reflects
#' the session state.
#' \code{get_jsevent} returns events fired by
#' \code{shidashi.broadcastEvent} in 'JavaScript'.
#' \code{get_theme} returns a list of theme, foreground, and background color.
#'
#' @details The \code{register_session_id} should be used in the module
#' server function. It registers a \code{shared_id} and a \code{private_id}
#' to the session. The sessions with the same \code{shared_id} can synchronize
#' their inputs, specified by \code{shared_inputs} even on different browser
#' tabs.
#'
#' \code{register_session_events} will read the session events from 'JavaScript'
#' and passively update these information. Any the event fired by
#' \code{shidashi.broadcastEvent} in 'JavaScript' will be available as
#' reactive value. \code{get_jsevent} provides a convenient way to read
#' these events provided the right
#' event types. \code{get_theme} is a special \code{get_jsevent} that with
#' event type \code{"theme.changed"}.
#'
#' Function \code{register_session_id} and \code{register_session_events}
#' should be called at the beginning of server functions. They can be
#' called multiple times safely. Function
#' \code{get_jsevent} and \code{get_theme} should be called in reactive
#' contexts (such as \code{\link[shiny]{observe}},
#' \code{\link[shiny]{observeEvent}}).
#'
#' @examples
#'
#' # shiny server function
#'
#' library(shiny)
#' server <- function(input, output, session){
#'   sync_tools <- register_session_id(session = session)
#'   event_data <- register_session_events(session = session)
#'
#'   # if you want to enable syncing. They are suspended by default
#'   sync_tools$enable_broadcast()
#'   sync_tools$enable_sync()
#'
#'   # get_theme should be called within reactive context
#'   output$plot <- renderPlot({
#'     theme <- get_theme(event_data)
#'     mar(bg = theme$background, fg = theme$foreground)
#'     plot(1:10)
#'   })
#'
#' }
#'
NULL

#' @title Register global reactive list
#' @description Creates or get reactive value list that is shared within the same
#' shiny session
#' @param name character, the key of the list
#' @param session shiny session
#' @return A shiny \code{\link[shiny]{reactiveValues}} object
#' @export
register_global_reactiveValues <- function(name, session = shiny::getDefaultReactiveDomain()){
  if(is.null(session)){
    return(shiny::reactiveValues())
  }
  root_session <- session$rootScope()
  if( is.null(root_session$userData$shidashi$global_reactiveValues) ) {
    root_session$userData$shidashi$global_reactiveValues <- fastmap::fastmap()
  }
  value_list <- root_session$userData$shidashi$global_reactiveValues
  event_data <- value_list$get( key = name, missing = NULL )
  if(!shiny::is.reactivevalues(event_data)){
    event_data <- shiny::reactiveValues()
    value_list$set( key = name, value = event_data )
  }
  event_data
}



#' @rdname javascript-tunnel
#' @export
register_session_id <- function(
  session = shiny::getDefaultReactiveDomain(),
  shared_id = NULL,
  shared_inputs = NA){

  # DIPSAUS DEBUG START
  # session <- shiny:::MockShinySession$new()
  # shared_id <- NULL
  # shared_inputs <- NA

  # Get stored session information
  if( !is.environment(session$userData$shidashi) ) {
    session$userData$shidashi <- new.env(parent = emptyenv())
  }

  if(length(shared_id)){
    if(grepl("[^a-z0-9_]", shared_id)){
      stop("session `shared_id` must only contain letters (lower-case), digits, and/or '_'.")
    }
  } else {
    shared_id <- session$userData$shidashi$shared_id
    if(length(shared_id) != 1 || !is.character(shared_id)){
      # get from session
      query_list <- httr::parse_url(shiny::isolate(session$clientData$url_search))
      shared_id <- query_list$query$shared_id
      shared_id <- tolower(shared_id)
      if(!length(shared_id) || grepl("[^a-z0-9_]", shared_id)){
        shared_id <- rand_string(length = 26)
        shared_id <- tolower(shared_id)
      }
    }
  }
  session$userData$shidashi$shared_id <- shared_id

  if(is.null(session$userData$shidashi$private_id)) {
    is_registerd <- FALSE
    private_id <- rand_string(length = 8)
    session$userData$shidashi$private_id <- private_id
  } else {
    is_registerd <- TRUE
    private_id <- session$userData$shidashi$private_id
  }

  broadcast_observer <- session$userData$shidashi$broadcast_observer
  if( is.null(broadcast_observer) ) {
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
    session$userData$shidashi$broadcast_observer <- broadcast_observer
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


  # ----- For backward compatibility -----------------------------------
  session$cache$set("shidashi_shared_id", shared_id)
  session$cache$set("shidashi_private_id", private_id)
  session$cache$set("shidashi_broadcast_handler", broadcast_observer)

  res
}

#' @rdname javascript-tunnel
#' @export
register_session_events <- function(session = shiny::getDefaultReactiveDomain()){
  if(is.environment(session)){
    root_session <- session$rootScope()

    # event_data <- root_session$cache$get("shidashi_event_data", NULL)
    if(!is.environment(root_session$userData$shidashi)) {
      root_session$userData$shidashi <- new.env(parent = emptyenv())
    }
    event_data <- root_session$userData$shidashi$event_data
    if(!shiny::is.reactivevalues(event_data)){
      event_data <- shiny::reactiveValues()
      root_session$userData$shidashi$event_data <- event_data
    }

    # observer <- root_session$cache$get("shidashi_event_handler", NULL)
    observer <- root_session$userData$shidashi$event_handler

    if(is.null(observer)){
      observer <- shiny::observeEvent({
        root_session$input[["@shidashi_event@"]]
      }, {
        event <- root_session$input[["@shidashi_event@"]]
        if(is.list(event) && length(event$type) == 1 && is.character(event$type) ){
          event_data[[event$type]] <- event$message
        }
      }, domain = root_session)

      session$sendCustomMessage("shidashi.get_theme", list())
      root_session$userData$shidashi$event_handler <- observer
    }

    root_session$cache$set("shidashi_event_data", event_data)
    root_session$cache$set("shidashi_event_handler", observer)

  } else {
    event_data <- list()
  }
  event_data
}


#' @rdname javascript-tunnel
#' @export
get_theme <- function(event_data, session = shiny::getDefaultReactiveDomain()){
  get_jsevent(event_data, "theme.changed", list(
    theme = "light",
    background = "#FFFFFF",
    foreground = "#000000"
  ), session = session)
}

#' @rdname javascript-tunnel
#' @export
get_jsevent <- function(event_data, type, default = NULL,
                        session = shiny::getDefaultReactiveDomain()){
  if(shiny::is.reactivevalues(event_data)){
    shiny::withReactiveDomain(domain = session, {
      if(is.list(event_data[[type]])){
        return(event_data[[type]])
      } else {
        return(default)
      }
    })
  } else {
    return(default)
  }
}




