# agents/tools/get_shiny_input_values.R
#
# Root-level MCP tool: Read Shiny input values from the bound session.
# The session is already bound via register_shinysession, so no explicit
# token parameter is needed.
#
# Enable per module in agents/agent.yaml:
#   tools:
#     root:
#       get_shiny_input_values: true

get_shiny_input_values <- shidashi::mcp_wrapper(
  function(session) {

    # Capture the live session in closure
    bound_session <- session

    ellmer::tool(
      fun = function(input_ids = character()) {
        input_ids <- as.character(input_ids[!is.na(input_ids)])
        values <- tryCatch({
          if (is.null(input_ids) || length(input_ids) == 0L) {
            shiny::isolate(shiny::reactiveValuesToList(bound_session$input))
          } else {
            structure(
              names = input_ids,
              lapply(input_ids, function(id) {
                shiny::isolate(bound_session$input[[id]])
              })
            )
          }
        }, error = function(e) {
          stop("Error reading inputs: ", conditionMessage(e))
        })
      },
      name = "get_shiny_input_values",
      description = "Read R-Shiny input values from the bound session.",
      arguments = list(
        input_ids = ellmer::type_array(
          items = ellmer::type_string(),
          description = "Input IDs to read. If empty or omitted, returns all input values.",
          required = FALSE
        )
      )
    )
  }
)
