
rand_string <- function (length = 10) {
  paste(sample(c(letters, LETTERS, 0:9), length, replace = TRUE),
        collapse = "")
}

set_attr_call <- function(x, call, collapse = "\n", ...) {
  if(!is.character(call)){
    call <- deparse(call)
  }
  call <- paste(call, collapse = collapse, ...)
  attr(x, "shidashi.code") <- call
  x
}

combine_class <- function(...){
  s <- paste(c(...), collapse = " ", sep = " ")
  s <- unlist(strsplit(s, " "))
  s <- unique(s)
  s <- s[!s %in% '']
  paste(s, collapse = " ")
}
remove_class <- function(target, class){
  if (!length(target)) { return("") }
  s <- unlist(strsplit(target, " "))
  s <- unique(s)
  s <- s[!s %in% c('', class)]
  paste(s, collapse = " ")
}

#' @export
guess_body_class <- function(cls){
  if(missing(cls)){
    cls <- "fancy-scroll-y darm-mode"
  } else {
    cls <- unlist(strsplit(paste(cls, collapse = ' '), " "))
    combine_class(cls[startsWith(cls, "fancy-scroll-") | cls %in% 'dark-mode'])
  }
}

#' @export
get_construct_string <- function(x){
  attr(x, "shidashi.code")
}

#' @export
format_text_r <- function(expr, quoted = FALSE, reformat = TRUE,
                          width.cutoff = 80L, indent = 2, wrap=TRUE,
                          args.newline = TRUE, blank = FALSE, ...){
  if(!quoted){
    expr <- substitute(expr)
  }

  if(length(expr) !=1 || !is.character(expr)){
    expr <- paste(deparse(expr), collapse = "\n")
  }

  if(reformat){
    expr <- formatR::tidy_source(
      text = expr, output = FALSE,
      width.cutoff = width.cutoff, indent = indent, wrap=wrap,
      args.newline = args.newline, blank = blank,
      ...
    )$text.tidy
  }
  paste(expr, collapse = "\n")
}

#' @export
html_highlight_code <- function(
  expr, class = NULL, quoted = FALSE,
  reformat = TRUE, copy_on_click = TRUE,
  width.cutoff = 80L, indent = 2, wrap=TRUE,
  args.newline = TRUE, blank = FALSE,
  ..., hover = c("overflow-visible-on-hover", "overflow-auto")){

  hover <- match.arg(hover)
  if(!quoted){
    expr <- substitute(expr)
  }
  expr <- format_text_r(expr = expr, quoted = TRUE,
                reformat = reformat, width.cutoff = width.cutoff,
                indent = indent, wrap = wrap, args.newline = args.newline,
                blank = blank, ...)

  shiny::HTML(
    sprintf(
      "<pre class='padding-8 no-margin bg-gray-90 %s %s %s' %s><code class='r'>%s</code></pre>",
      hover,
      paste(class, collapse = " "),
      ifelse(copy_on_click, "clipboard-btn shidashi-clipboard-output", ""),
      ifelse(copy_on_click,
             sprintf("data-clipboard-text='%s' role='button' title='Click to copy!'", expr),
             ""),
      expr
    )
  )
}

#' @export
show_ui_code <- function(
  x, class = NULL, code_only = FALSE,
  as_card = FALSE, card_title = "", class_body = "bg-gray-70",
  width.cutoff = 80L, indent = 2, wrap=TRUE,
  args.newline = TRUE, blank = FALSE, copy_on_click = TRUE,
  ...)
{
  code <- format_text_r(
    get_construct_string(x),
    quoted = TRUE,
    width.cutoff = width.cutoff,
    indent = indent,
    wrap = wrap,
    args.newline = args.newline,
    blank = blank,
    ...
  )

  res <- info_box(
    class = combine_class("no-margin overflow-visible-on-hover", class),
    class_content = "display-block bg-gray-90 no-padding code-display",
    icon = NULL,
    html_highlight_code(code, quoted = TRUE, reformat = FALSE,
                        copy_on_click = copy_on_click)
  )


  if(as_card){
    res <- card(
      title = card_title, class_body = class_body,
      tools = clipboardOutput(
        clip_text = code,
        as_card_tool = TRUE),
      footer = res,
      class_foot = "display-block bg-gray-90 no-padding code-display fill-width",
      if(code_only){ NULL }else{x}
    )
  }
  res
}


