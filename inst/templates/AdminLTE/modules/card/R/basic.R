
ui_card_basic <- function(){

  shiny::tagList(
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Basic Card Example",
        "Card body"
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 1",
        class = "card-outline card-primary",
        'class = "card-outline card-primary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 2",
        class = "card-primary",
        'class = "card-primary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 3",
        class = "bg-primary",
        'class = "bg-primary"'
      )
    )),

    # cards with themes
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Secondary Card",
        class = "card-secondary",
        'class = "card-secondary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Success Card",
        class = "card-success",
        'class = "card-success"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Info Card",
        class = "card-info",
        'class = "card-info"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Warning Card",
        class = "card-warning",
        'class = "card-warning"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Danger Card",
        class = "card-danger",
        'class = "card-danger"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Dark Card",
        class = "card-dark",
        'class = "card-dark"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Light Card",
        class = "card-light",
        'class = "card-light"'
      )
    ))

  )

}
