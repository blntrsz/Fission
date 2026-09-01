# mise setup for project-local Xcode tasks

## Recommended file and format

- Put a **TOML** file named **`mise.toml`** at the repository root. This is mise's default local config filename and its documented project-config form. Although mise recognizes alternatives such as `.mise.toml` and `.mise/config.toml`, and can read `.tool-versions`, the docs recommend `mise.toml` over `.tool-versions`; task definitions belong in `mise.toml`. ([Configuration: `mise.toml`](https://mise.jdx.dev/configuration.html#mise-toml), [Configuration: `.tool-versions`](https://mise.jdx.dev/configuration.html#tool-versions), [Tasks](https://mise.jdx.dev/tasks/))
- Project configs are discovered by walking upward from the invocation directory and are merged with parent/global configs; a nearer project config overrides conflicting broader settings. Thus one root `mise.toml` is discoverable when commands are run from descendant directories. ([Configuration hierarchy](https://mise.jdx.dev/configuration.html#configuration-hierarchy))

## Task definitions

Define the requested names as detailed TOML tasks:

```toml
[tasks.desktop]
description = "Run the desktop app"
run = "<desktop shell command>"

[tasks.mobile]
description = "Run the mobile app"
run = "<mobile shell command>"
```

`run` is the required task property. It may be a single shell-command string, an array of commands executed sequentially (stopping on failure), or a multiline script. Arrays represent separate commands, not the argument vector of one command. ([Task configuration: `run`](https://mise.jdx.dev/tasks/task-configuration.html#run), [TOML tasks: run command](https://mise.jdx.dev/tasks/toml-tasks.html#run-command))

## Working directory and environment

- A TOML task defaults to `dir = "{{ config_root }}"`: for a root `mise.toml`, this is the repository root. Set `dir` only when a command intentionally needs another directory; `dir = "{{cwd}}"` instead uses the caller's invocation directory. ([Task configuration: `dir`](https://mise.jdx.dev/tasks/task-configuration.html#dir))
- mise also passes `MISE_ORIGINAL_CWD`, `MISE_CONFIG_ROOT`, `MISE_PROJECT_ROOT`, and task metadata such as `MISE_TASK_NAME` to tasks. ([Tasks: environment variables passed to tasks](https://mise.jdx.dev/tasks/#environment-variables-passed-to-tasks))
- Shared repository variables go under `[env]`; they are available to `mise run` tasks even without relying on shell activation. Per-task variables use `env = { KEY = "value" }`. Task-local `env` applies to that task and is **not** automatically passed to its `depends` tasks. ([Environments: using environment variables](https://mise.jdx.dev/environments/#using-environment-variables), [Environments: environment in tasks](https://mise.jdx.dev/environments/#environment-in-tasks), [Task configuration: `env`](https://mise.jdx.dev/tasks/task-configuration.html#env))

## Long-running or long-form shell commands

Invoke the tasks explicitly as:

```sh
mise run desktop
mise run mobile
```

`mise run <task>` is the recommended unambiguous form for scripts and documentation; the shorter `mise <task>` can later collide with a mise command. ([Running tasks](https://mise.jdx.dev/tasks/running-tasks.html#mise-run-shorthand))

For a command that is textually long or needs shell setup, use a TOML multiline literal, optionally with a shebang:

```toml
[tasks.desktop]
run = '''
#!/usr/bin/env bash
<desktop command \
  with options>
'''
```

Multiline scripts and shebang interpreters are directly supported. Without an override, inline commands use `sh -c`; shell tasks using `sh`, `bash`, or `zsh` run with fail-fast `set -e` behavior. ([TOML tasks: multiline example](https://mise.jdx.dev/tasks/toml-tasks.html#detailed-task-examples), [TOML tasks: shell/shebang](https://mise.jdx.dev/tasks/toml-tasks.html#shell-shebang))

A normal long-running process can remain the task's foreground command; no special duration setting is documented. If it needs direct terminal input/output (for example, an interactive prompt or full-screen UI), configure `interactive = true` or, where raw stdio is specifically required, `raw = true`. Both connect directly to stdin/stdout/stderr and impose exclusive execution constraints, so they should not be added merely because a build takes a long time. ([Task configuration: `interactive`](https://mise.jdx.dev/tasks/task-configuration.html#interactive), [Task configuration: `raw`](https://mise.jdx.dev/tasks/task-configuration.html#raw), [Running tasks: stdin](https://mise.jdx.dev/tasks/running-tasks.html#running-tasks))
