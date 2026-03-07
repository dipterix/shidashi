test_that("mcp_wrapper validates generator is a function", {
  expect_error(mcp_wrapper("not a function"), "generator must be a function")
})

test_that("mcp_wrapper validates generator accepts session param", {
  expect_error(
    mcp_wrapper(function(x) NULL),
    "generator must accept"
  )
})

test_that("mcp_wrapper returns a function with correct class", {
  gen <- function(session) {
    ellmer::tool(
      fun = function() "hello",
      name = "test_tool",
      description = "A test tool"
    )
  }
  wrapped <- mcp_wrapper(gen)
  expect_s3_class(wrapped, "shidashi_mcp_wrapper")
  expect_true(is.function(wrapped))
})

test_that("mcp_wrapper normalises single ToolDef to list", {
  gen <- function(session) {
    ellmer::tool(
      fun = function() "hello",
      name = "single_tool",
      description = "Returns a single tool"
    )
  }
  wrapped <- mcp_wrapper(gen)
  result <- wrapped(session = NULL)
  expect_type(result, "list")
  expect_length(result, 1)
  expect_true(inherits(result[[1]], "ellmer::ToolDef"))
})

test_that("mcp_wrapper filters out non-ToolDef objects", {
  gen <- function(session) {
    list(
      ellmer::tool(
        fun = function() "valid",
        name = "valid_tool",
        description = "A valid tool"
      ),
      "not a tool",
      42,
      NULL
    )
  }
  wrapped <- mcp_wrapper(gen)
  result <- wrapped(session = NULL)
  expect_length(result, 1)
  expect_equal(result[[1]]@name, "valid_tool")
})

test_that("mcp_wrapper returns empty list when generator returns no tools", {
  gen <- function(session) {
    list("no tools here", 123)
  }
  wrapped <- mcp_wrapper(gen)
  result <- wrapped(session = NULL)
  expect_type(result, "list")
  expect_length(result, 0)
})
