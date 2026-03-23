# mcp_input_update_wrapper <- mcp_wrapper_input_output()
#
# mcp_input_update_generator <- mcp_input_update_wrapper$tool_generator
# register_input <- mcp_input_update_wrapper$input_helpers$register_input_specification


# # Returns two tools:
# #   - shiny_input_info
# #   - shiny_input_update
# unname(sapply(
#   X = mcp_input_update_generator(shiny::MockShinySession$new()),
#   FUN = function(tool) {
#     tool@name
#   }
# ))
