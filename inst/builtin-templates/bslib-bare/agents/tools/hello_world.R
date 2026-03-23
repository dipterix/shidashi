# agents/tools/hello_world.R
#
# Root-level MCP tool: Returns a greeting.
# Used to verify the MCP tunnel works end-to-end.
#
# Enable per module in agents/agent.yaml:
#   tools:
#     root:
#       hello_world: true

hello_world <- shidashi::mcp_wrapper(
  function(session) {
    ellmer::tool(
      fun = function(name = "World") {
        paste0("Hello, ", name, "!")
      },
      name = "hello_world",
      description = "Returns a greeting. Used to verify the MCP tunnel works.",
      arguments = list(
        name = ellmer::type_string(
          "Name to greet (default: 'World')",
          required = FALSE
        )
      )
    )
  }
)
