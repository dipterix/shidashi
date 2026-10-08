---
name: rave
description: Use when the user mentions RAVE (Reproducible Analysis and Visualization of intracranial electroencephalography, or iEEG, rave.wiki) or a RAVE module (power explorer, wavelet, notch filter, electrode localization, YAEL preprocessing, 3D viewer, power clustering), for example to load a subject or run an analysis in the RAVE dashboard. Not for other shidashi apps, or for R, Shiny or iEEG questions that do not mention RAVE.
---

# RAVE

RAVE is a software platform for reproducible analyzing and visualizing human invasive intracranial EEG (ECoG electrodes on the brain surface, stereotactic electrodes inserted into the brain, or DBS electrodes for brain stimulation). The application is for neuroscientists, neurologist, neurosurgeons who wish to study the human brain.

RAVE is a dashboard built with shidashi. Work in it through the shidashi MCP
tools (`shidashi_sessions`, the module tools, `switch_module`,
`shidashi_connect`) and the `rave-module` skill the app offers
(`skill_load__rave-module`). Do not run RAVE pipelines in R or edit RAVE
files unless the user asks, and never stop a RAVE app.

## 1. Find the RAVE app

1. Call `shidashi_sessions`. A RAVE app's `app.welcome` starts with "RAVE
   (Reproducible Analysis and Visualization of iEEG)". If it does, use it.
2. Otherwise:
   - Testing: RAVE runs on port 17283. Call `shidashi_connect` with
     `127.0.0.1:17283`.
   - Production: run `Rscript <this skill's folder>/scripts/find-rave.R`. It
     lists the RAVE sessions on this computer, newest first, with each
     session's address, whether it answers, its `base.log`, and its MCP call
     log. Connect to the one that answers with `shidashi_connect`; when
     several answer, ask the user which one.
3. No RAVE app answers: ask the user whether to start one. If they agree and
   you can run R on this computer, start it so that it keeps running after
   your command:

   ```
   nohup Rscript -e 'rave::start_rave()' > rave-start.log 2>&1 &
   ```

   Run `find-rave.R` again, connect, and tell the user the app's process id
   (`pid`) so they can stop it. If you cannot run R, ask the user to run
   `rave::start_rave()`.
4. No browser page open (`shidashi_sessions` lists no open modules, or a tool
   says no browser page is connected): run
   `Rscript <this skill's folder>/scripts/find-rave.R --open=<port>`. It
   checks that `GET <address>mcp` answers, then opens the app in the
   browser. If you cannot run R, give the user a one-click link to the
   address. Then call `shidashi_sessions` until the page is listed, and
   `switch_module` to open a module.

Each session folder has `logs/server-info.log` while its app runs (port,
address, process id; removed when the app stops) and `logs/base.log`, which
shows what the session is doing.

## 2. Before loading data or running an analysis

Read the rules at the top of the `rave-module` skill readme
(`skill_load__rave-module`) and follow them. In short: `shiny_input_info`
gives every input's `hint` and `@state.loader_opened`; ask the user every
`loader_mandatory` input in one message, and the `analysis_mandatory` ones
before the analysis; the skill's `subject_info.R` and `project_info.R` list
the real choices. Loading reads gigabytes of data: never load on a guess.

## 3. When calls keep failing

Read the last lines of the app's MCP call log, `mcp-calls.log` in the folder
named by the `mcp_log:` line of `server-info.log` (`find-rave.R` prints it).
`[failed]` lines give the reason; lines marked `(proxy)` never reached the
app.
