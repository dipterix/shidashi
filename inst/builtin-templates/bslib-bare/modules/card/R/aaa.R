library(shiny)
library(shidashi)

card_with_code <- function(expr, env = parent.frame(),
                           class = "height-50", width.cutoff = 25L) {
  expr <- substitute(expr)
  x <- eval(expr, envir = env)

  code <- clipboardOutput(
    clip_text = format_text_r(
      get_construct_string(x), quoted = TRUE,
      width.cutoff = width.cutoff
    ), class = "float-end", as_card_tool = TRUE
  )
  expr[["footer"]] <- code
  eval(expr, envir = env)
}
