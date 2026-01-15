# TurnScheduler Profiling (Long-term)

This document is the **source of truth** for TurnScheduler performance profiling
and the long-term TS-301 follow-up work.

## Goals

- Make it easy to run a repeatable “typical interaction” scenario with profiling enabled.
- Persist **key logs + conclusions** on disk (so future refactors don’t regress silently).

## How to enable profiling

TurnScheduler supports lightweight, opt-in profiling logs.

- Set `TURN_SCHEDULER_PROFILE=1`
- Run your normal dev flow (server + browser) or run a targeted script/test

When enabled, TurnScheduler prints lines like:

```
[TurnScheduler::Perf] ActivatedQueue total_ms=... sql_count=... sql_ms=... payload=...
```

Hot paths covered:
- `ActivatedQueue`
- `QueuePreview`
- `Broadcasts.queue_updated`

Implementation: `playground/app/services/turn_scheduler/instrumentation.rb`

## “Typical interaction” checklist (recommended)

Try to keep the scenario consistent so results are comparable between runs:

1) **Group + list**: 2–3 AI members, `reply_order=list`, user sends 1 message, observe full round.
2) **Group + natural**: mention activation, talkativeness activation, allow_self_responses on/off.
3) **Group + pooled**: verify single activation and epoch behavior.
4) **Policy stress**: during_generation_user_input_policy = reject/restart/queue while a run is active.
5) **Membership churn**: mute/unmute or remove/add a member mid-round, observe preview correctness.
6) **Multi-process ordering** (if applicable): verify UI doesn’t regress on stale queue updates.

## Where to capture logs

Use the Rails log output:
- dev server: `playground/log/development.log`
- test runs: `playground/log/test.log` (noisy in parallel mode)

Extract only profiling lines:

```
rg -n \"\\[TurnScheduler::Perf\\]\" playground/log/development.log
```

## Logbook (append-only)

Add a new entry per run. Keep it short and comparable.

## Automated runner (no browser)

There is a built-in task that runs a deterministic “typical interaction” flow
with a fake no-HTTP LLM client, captures `[TurnScheduler::Perf]` lines, and
outputs a markdown entry.

Run it:

```
cd playground
bin/rails turn_scheduler:profile_typical
```

Append the entry to a file (recommended for long-term TS-301 tracking):

```
cd playground
bin/rails turn_scheduler:profile_typical OUT=../docs/playground/TURN_SCHEDULER_PROFILING_LOGBOOK.md APPEND=1
```

(The file will be created if it does not exist.)

Tuning knobs:
- `REPLY_ORDER=list|natural|pooled|manual` (default: `list`)
- `AI_COUNT=2` (default: `2`)
- `USER_MESSAGE="Hello"` (default: `"Hello (profiling)"`)

### Template

```
#### YYYY-MM-DD (env / branch / commit)

Scenario:
- ...

Key log excerpts (summarized):
- ActivatedQueue: sql_count=..., total_ms=..., notes=...
- QueuePreview:  sql_count=..., total_ms=..., notes=...
- Broadcasts:    sql_count=..., total_ms=..., notes=...

Conclusions:
- ...

Follow-ups:
- ...
```
