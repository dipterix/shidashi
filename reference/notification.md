# The 'Bootstrap' notification

The 'Bootstrap' notification

## Usage

``` r
show_notification(
  message,
  title = "Notification!",
  subtitle = "",
  type = c("default", "info", "warning", "success", "danger", "white", "dark"),
  close = TRUE,
  position = c("topRight", "topLeft", "bottomRight", "bottomLeft"),
  autohide = TRUE,
  fixed = TRUE,
  delay = 5000,
  icon = NULL,
  collapse = "",
  session = shiny::getDefaultReactiveDomain(),
  class = NULL,
  ...
)

clear_notifications(class = NULL, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- message:

  notification body content, can be 'HTML' tags

- title, subtitle:

  title and subtitle of the notification

- type:

  type of the notification; can be `"default"`, `"info"`, `"warning"`,
  `"success"`, `"danger"`, `"white"`, `"dark"`

- close:

  whether to allow users to close the notification

- position:

  where the notification should be; choices are `"topRight"`,
  `"topLeft"`, `"bottomRight"`, `"bottomLeft"`

- autohide:

  whether to automatically hide the notification

- fixed:

  whether the position should be fixed

- delay:

  integer in millisecond to hide the notification if `autohide=TRUE`

- icon:

  the icon of the title

- collapse:

  if `message` is a character vector, the collapse string

- session:

  shiny session domain

- class:

  the extra class of the notification, can be used for style purposes,
  or by `clear_notifications` to close specific notification types.

- ...:

  other options; see
  <https://adminlte.io/docs/3.1//javascript/toasts.html#options>

## Value

Both functions should be used in shiny reactive contexts. The messages
will be sent to shiny 'JavaScript' interface and nothing will be
returned.

## Examples

``` r
if (FALSE) { # \dontrun{

# the examples must run in shiny reactive context

show_notification(
  message = "This validation process has finished. You are welcome to proceed.",
  autohide = FALSE,
  title = "Success!",
  subtitle = "type='success'",
  type = "success"
)

show_notification(
  message = "This notification has title and subtitle",
  autohide = FALSE,
  title = "Hi there!",
  subtitle = "Welcome!",
  icon = "kiwi-bird",
  class = "notification-auto"
)

# only clear notifications with class "notification-auto"
clear_notifications("notification-auto")

} # }
```
