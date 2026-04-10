library(shiny)
library(shidashi)

server_stream_viz <- function(input, output, session, ...) {

  # Set up the stream directory once for this session
  shidashi::stream_init(session)

  # ---- register_output for the stream-viz widget ----------------------------
  shidashi::register_output(
    shidashi::renderStreamViz({
      shidashi::stream_viz("viz_signal", session = session, streaming = TRUE)
    }),
    outputId = "viz_signal",
    description = "Multi-channel signal viewer (stream-viz Three.js widget)",
    download_type = "stream_viz",
    session = session
  )

  # ---- Simulation state -----------------------------------------------------
  simulating <- reactiveVal(FALSE)
  sim_time <- reactiveVal(0)
  init <- FALSE

  observeEvent(input$btn_simulate, {
    currently <- simulating()
    simulating(!currently)
    if (!currently) {
      sim_time(0)
      shiny::updateActionButton(session, "btn_simulate",
                                label = "Stop Simulation",
                                icon = shidashi::as_icon("stop"))
    } else {
      shiny::updateActionButton(session, "btn_simulate",
                                label = "Simulate",
                                icon = shidashi::as_icon("play"))
    }
  })

  # ---- Periodic data generation (50 ms flush rate) --------------------------
  observe({
    if (!simulating()) {
      init <<- FALSE
      return()
    }
    shiny::invalidateLater(100, session)

    n_ch <- isolate(as.integer(input$n_channels))
    sr   <- isolate(as.integer(input$sample_rate))
    buf_sec <- isolate(as.numeric(input$n_seconds))
    n_t  <- as.integer(sr * buf_sec)

    # Advance simulation clock (isolate to avoid self-dependency loop)
    t0 <- isolate(sim_time())
    dt <- 50 / 1000  # 50 ms flush interval
    sim_time(t0 + dt)

    # Generate multi-channel sine waves with noise
    t_seq <- seq(t0, by = 1 / sr, length.out = n_t)
    mat <- matrix(0.0, nrow = n_ch, ncol = n_t)
    for (ch in seq_len(n_ch)) {
      freq      <- 2 + ch * 1.5
      amplitude <- 1 / ch
      mat[ch, ] <- amplitude * sin(2 * pi * freq * t_seq) +
                   rnorm(n_t, sd = 0.1 * amplitude)
    }

    ch_names <- paste0("Ch ", seq_len(n_ch))

    # Write binary stream file
    abspath <- shidashi::stream_path("viz_signal", session)
    shidashi::stream_to_js(
      abspath,
      data = as.numeric(mat),
      type = "float32",
      n_channels   = n_ch,
      n_timepoints = n_t,
      sample_rate  = sr,
      channel_names = ch_names,
      time_start = t0,
      time_end = t0 + buf_sec,
      x_unit = "s"
    )

    # Push update to the browser widget in-place
    if (!init) {
      init <<- TRUE
      shidashi::updateStreamViz("viz_signal", streaming = TRUE)
    }
  })
}
