
infobox_with_code <- function(x, title = "",
                              class = "height-100",
                              class_body = "padding-5 bg-gray-70"){
  shiny::div(
    class = "fill-width position-relative",
    shiny::span(
      class = "position-absolute padding-bottom-5 bg-gray",
      style = "right: 0; z-index: 100;",
      clipboardOutput(clip_text = get_construct_string(x),
                      as_card_tool = TRUE, message = "Copy to clipboard")
    ),
    x
  )
}
