# Create an ellmer Chat object for the chat-bot

Factory function that creates an
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
object based on the configured provider. Reads from
`options(shidashi.chat_provider)`, `shidashi.chat_model`, and
`shidashi.chat_base_url`. These arguments are passed to
[`chat`](https://ellmer.tidyverse.org/reference/chat-any.html).

## Usage

``` r
init_chat(
  system_prompt = getOption("shidashi.chat_system_prompt", NULL),
  provider = getOption("shidashi.chat_provider", "anthropic"),
  base_url = getOption("shidashi.chat_base_url", NULL)
)
```

## Arguments

- system_prompt:

  character; the system prompt. Defaults to
  `getOption("shidashi.chat_system_prompt")`.

- provider:

  character; provider name or provider name with models. Defaults to
  `getOption("shidashi.chat_provider", "anthropic")`.

- base_url:

  character or `NULL`; base URL for API-compatible providers.

## Value

An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html) R6
object (tools not yet bound).
