# Keep the files tests make in the shidashi cache folder (app records, MCP
# call logs) out of the user's real cache folder. Tests that need their own
# folder set `shidashi.cache_dir` locally.
withr::local_options(
  list(shidashi.cache_dir = tempfile("shidashi-test-cache-")),
  .local_envir = testthat::teardown_env()
)
