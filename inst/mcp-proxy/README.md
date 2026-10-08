# shidashi plugin for Claude

Drive `shidashi` dashboards from Claude. `shidashi` is an R package for
building Shiny dashboards made of modules. Each module can offer tools to AI
agents. With this plugin, Claude can see which modules you have open, read
and set their inputs, read their outputs, and run their tools. It can also
start the apps you saved with `shidashi::save_launcher()`.

## Install

In Claude Code:

```
/plugin marketplace add dipterix/shidashi
/plugin install shidashi@shidashi
```

In Claude Desktop, open **Customize > Plugins > Add > Add marketplace**,
enter `dipterix/shidashi`, and install `shidashi`.

The plugin runs in Claude Code and in Cowork on your computer.

## Requirements

- [Node.js](https://nodejs.org/) 18 or newer

## Use

1. Start an app in R, for example `shidashi::render()`, and open a module in
   your browser.
2. Ask Claude to work with it, for example: "Which shidashi modules are
   open?"

With no app running, Claude asks whether you want to start one yourself or
have it launch one of your saved apps. To attach to an app on another
computer, give Claude its address.

The plugin finds running apps through the `shidashi` cache folder,
`tools::R_user_dir("shidashi", "cache")`. If you moved that folder with
`options(shidashi.cache_dir = ...)`, set the environment variable
`SHIDASHI_CACHE_DIR` to the same folder for Claude.

## Skills

- `rave`: loads when you mention `RAVE`. It tells Claude how to find a
  running `RAVE` app on your computer (or start one, if you agree), open it
  in the browser, and which questions to ask before loading data.

## Call log

Every `MCP` call, and its reply, is written to a log in the `shidashi`
cache folder: `MCP-logs/date-<start time>_app-<app id>/mcp-calls.log`, one
folder per running app. Each line (at most 300 characters) has the time,
the tool, and the start of its arguments, result, or the reason it failed,
so you can see why a call failed. Calls that never reached an app are
marked `(proxy)`. The newest 50 folders are kept. Turn the log off with the
environment variable `SHIDASHI_MCP_LOG=false` (and, in R,
`options(shidashi.mcp_log = FALSE)`).

## Privacy

The plugin runs only on your computer. It collects no data and sends
nothing to the plugin author or any other third party. It stores only the
log files of apps it starts, kept in the `shidashi` cache folder until the
next start of the same app, and the call log above (only you can access
those files). The call log holds the start of tool arguments and results,
which can include names from your data, such as project and subject codes.
It sends requests only to `shidashi` apps running on your computer, or to 
an app address you give Claude. Tool results go to Claude like the rest of 
your conversation.

Notice: although this plugin does not collect nor send anything remotely, 
it's a tool to give claude access to the shidashi dashboard. It is up to 
Anthropic on how those data are stored on their server. Therefore, 
please do not input sensitive data to the connected apps.

Questions and issues: <https://github.com/dipterix/shidashi/issues>

## License

MIT
