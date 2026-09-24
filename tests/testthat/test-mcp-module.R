test_that("resolver ranks pinned over focused over most recently opened", {
  app_env <- local_mcp_app()
  now <- Sys.time()
  older <- fake_module_session("demo", "tool__x", registered_at = now - 30)
  newer <- fake_module_session("aiagent", "tool__x", registered_at = now - 10)

  res <- mcp_resolve_module("tool__x")
  expect_true(res$ok)
  expect_identical(res$token, newer)
  expect_identical(res$reason, "most recently opened")

  set_activity(older, focused_at = now - 5)
  res <- mcp_resolve_module("tool__x")
  expect_identical(res$token, older)
  expect_identical(res$reason, "last used")

  set_activity(newer, pinned = TRUE)
  res <- mcp_resolve_module("tool__x")
  expect_identical(res$token, newer)
  expect_identical(res$reason, "pinned")
})

test_that("resolver skips sessions that do not offer the tool", {
  app_env <- local_mcp_app()
  offers <- fake_module_session("demo", "tool__x", registered_at = Sys.time() - 60)
  fake_module_session("aiagent", "tool__y", pinned = TRUE)

  res <- mcp_resolve_module("tool__x")
  expect_identical(res$token, offers)
})

test_that("resolver ignores the shell page and closed sessions", {
  app_env <- local_mcp_app()
  fake_module_session("", "tool__x", pinned = TRUE)
  closed <- fake_module_session("aiagent", "tool__x", pinned = TRUE)
  open <- fake_module_session("demo", "tool__x", registered_at = Sys.time() - 60)
  get_session_entry(closed)$shiny_session$close()

  res <- mcp_resolve_module("tool__x")
  expect_identical(res$token, open)
})

test_that("handles are module ids unless a module is open more than once", {
  app_env <- local_mcp_app()
  single <- fake_module_session("demo")
  first <- fake_module_session("aiagent")
  second <- fake_module_session("aiagent")

  open <- mcp_open_modules()
  handles <- vapply(open, `[[`, "", "handle")
  names(handles) <- vapply(open, `[[`, "", "token")

  expect_identical(handles[[single]], "demo")
  expect_identical(handles[[first]], paste0("aiagent@", substr(first, 1, 6)))
  expect_identical(handles[[second]], paste0("aiagent@", substr(second, 1, 6)))
})

test_that("_module selects by module id, handle, or token prefix", {
  app_env <- local_mcp_app()
  demo <- fake_module_session("demo", "tool__x")
  first <- fake_module_session("aiagent", "tool__x")
  second <- fake_module_session("aiagent", "tool__x", pinned = TRUE)

  expect_identical(mcp_resolve_module("tool__x", module = "demo")$token, demo)
  expect_identical(
    mcp_resolve_module("tool__x", module = "aiagent")$token, second
  )
  handle <- paste0("aiagent@", substr(first, 1, 6))
  expect_identical(mcp_resolve_module("tool__x", module = handle)$token, first)
  expect_identical(
    mcp_resolve_module("tool__x", module = substr(first, 1, 8))$token, first
  )
  res <- mcp_resolve_module("tool__x", module = "demo")
  expect_identical(res$reason, "requested")
})

test_that("the URL module and _module must both match", {
  app_env <- local_mcp_app()
  demo <- fake_module_session("demo", "tool__x")
  fake_module_session("aiagent", "tool__x", pinned = TRUE)

  res <- mcp_resolve_module("tool__x", scope_module = "demo")
  expect_identical(res$token, demo)

  res <- mcp_resolve_module("tool__x", module = "aiagent",
                            scope_module = "demo")
  expect_false(res$ok)
})

test_that("resolver explains what to do when nothing matches", {
  app_env <- local_mcp_app()

  res <- mcp_resolve_module("tool__x", providers = c("demo", "aiagent"))
  expect_false(res$ok)
  expect_match(res$message, "No dashboard module is open")

  fake_module_session("demo", "tool__x")
  res <- mcp_resolve_module("tool__x", module = "nope")
  expect_false(res$ok)
  expect_match(res$message, "nope")
  expect_match(res$message, "demo")
})

test_that("pinning a module unpins every other open module", {
  app_env <- local_mcp_app()
  first <- fake_module_session("demo", pinned = TRUE)
  second <- fake_module_session("aiagent")

  mcp_set_pin(second, TRUE)
  expect_false(get_session_entry(first)$activity$pinned)
  expect_true(get_session_entry(second)$activity$pinned)

  mcp_set_pin(second, FALSE)
  expect_false(get_session_entry(second)$activity$pinned)
})

test_that("resolver reports the module a call would use without _module", {
  app_env <- local_mcp_app()
  fake_module_session("demo", "tool__x", pinned = TRUE)
  other <- fake_module_session("aiagent", "tool__x")

  res <- mcp_resolve_module("tool__x", module = "aiagent")
  expect_identical(res$token, other)
  expect_identical(res$default_handle, "demo")
  expect_identical(res$default_reason, "pinned")

  res <- mcp_resolve_module("tool__x")
  expect_identical(res$default_handle, res$handle)
  expect_identical(res$default_reason, res$reason)
})

test_that("only_modules limits the candidates and the default", {
  app_env <- local_mcp_app()
  fake_module_session("demo", "tool__x", pinned = TRUE)
  aiagent <- fake_module_session("aiagent", "tool__x")

  res <- mcp_resolve_module("tool__x", only_modules = "aiagent")
  expect_identical(res$token, aiagent)
  expect_identical(res$default_handle, "aiagent")
  expect_identical(res$reason, "most recently opened")
})
