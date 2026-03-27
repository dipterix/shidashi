library(shiny)
library(shidashi)

server_stream_viz <- function(input, output, session, ...) {

  # Set up the stream directory once for this session
  shidashi::stream_init(session)

  # Initial empty placeholder
  output$viz_signal <- shidashi::renderStreamViz({
    shidashi::stream_viz(stream_id = NULL)
  })

  # React to the Simulate button
  shiny::observeEvent(input$btn_simulate, {

    n_ch <- as.integer(input$n_channels)
    sr   <- as.integer(input$sample_rate)
    n_t  <- as.integer(input$n_seconds) * sr

    # Generate synthetic multi-channel signal
    # Each channel is a sinusoid with unique frequency + small Gaussian noise
    t_seq <- seq(0, input$n_seconds, length.out = n_t)

    # Channel-contiguous matrix: row i = channel i, columns = time points
    mat <- matrix(0.0, nrow = n_ch, ncol = n_t)
    for (ch in seq_len(n_ch)) {
      freq      <- 2 + ch * 1.5                 # 3.5 Hz … up to ~99.5 Hz
      amplitude <- 0.5 + runif(1, 0, 1.5)
      mat[ch, ] <- amplitude * sin(2 * pi * freq * t_seq) +
                   rnorm(n_t, sd = 0.1 * amplitude)
    }

    # Write float32 channel-contiguous binary file
    abspath <- shidashi::stream_path("viz_signal", session)
    shidashi::stream_to_js(
      abspath,
      data = as.numeric(mat),   # vector: ch0[0..nT-1], ch1[0..nT-1], …
      type = "float32",
      n_channels   = n_ch,
      n_timepoints = n_t,
      sample_rate  = sr,
      channel_names = paste0("Ch ", seq_len(n_ch))
    )

    # Push update to the browser widget in-place (no flicker)
    shidashi::updateStreamViz(session, "viz_signal")
  })
}
