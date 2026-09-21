---
name: master-loop
description: "Run a mixed AI harness Herdr pane loop as master: labelled panes named master, planner, coder and verifier execute a multi-unit campaign, one unit at a time. Use when this pane is master or the orchestrator of such a loop, when asked to start or resume the loop, dispatch or brief a unit, or check on the planner/coder/verifier. Requires HERDR_ENV=1."
---

# Master loop

Four Herdr panes, one campaign, one unit in flight at a time.

| Role | Does | Never |
|---|---|---|
| **master** (you) | Owns the plan. Drives **planner only**. Defines units, reports to the owner, asks about commits. | Builds. Edits code. Talks to coder or verifier. |
| **planner** | Owns the unit-local coder/verifier loop and reports its terminal outcome. | Builds while coder or verifier works. |
| **coder** | Builds the unit. Owns the build tool for its job. | Verifies its own work. Touches the gate. Commits. |
| **verifier** | Reads the diff, runs the suites, executes revert proofs. Owns the build tool for its job. | Fixes what it finds — it reports; planner re-dispatches coder. |

**One agent runs the build/test tool at a time, campaign-wide** — planner and master included stay off
it for that job's lifetime; anyone who must run concurrently is write-files-only. Breakage here is
silent: shared build output, stale test binaries, a green that means nothing.

## 1. Resolve panes and agent hosts every turn

The role is the **pane label** on this tab. Labels are stable; IDs are not in role order; agent *names*
die on `/clear`. Never hardcode an ID or reuse a remembered layout.

```bash
test "${HERDR_ENV:-}" = 1 || echo "not inside Herdr - stop"
herdr pane list --workspace "$HERDR_WORKSPACE_ID" | tr '{},' '\n\n\n' \
  | awk -F'"' -v tab="$HERDR_TAB_ID" '/"label":/{l=$4} /"pane_id":/{p=$4} /"tab_id":/{if($4==tab) print l"\t"p}'
```

Address panes by the resolved ID; re-resolve after any close, split, swap or rename. A missing role: say
which and stop, never guess from position. Fix with `herdr pane rename <pane-id> <label>`, and
`herdr agent start <pane-id> ...` if the pane has no agent.

Also run `herdr agent list` and join its entries to the labelled panes by `pane_id`. The `agent` field
identifies `claude` or `codex`; do not infer the host from the pane label, title or remembered occupant.
The host determines skill syntax and which repo instruction files apply.

## 2. Campaign state lives outside the tracked worktree

Use one campaign directory that survives `/clear`, stays out of `git status`, and is writable by every
pane under its active sandbox. A sibling directory such as `C:\dev\<area>\<ticket>\` on Windows or
`/work/<area>/<ticket>/` on Linux is usual, not guaranteed. Verify access before unit 1. If no shared
writable directory exists, ask the owner to designate or authorize one; do not silently move campaign
state into tracked files.

`PLAN.md` (master: unit table with status, locked owner decisions, what is out of scope) is the record,
not your context. Beside it: `job-<unit>-<slug>.md` (planner→coder),
`report-u<unit>.md` (coder: files written, revert table, open questions), `verify-<unit>.md`
(planner→verifier), `verify-u<unit>.md` (verifier: verdict, real counts, which proofs it ran).

**Every agent writes a file and replies with only the path**, a verdict line and the numbers. Agent
TUIs may use alternate-screen rendering or truncate scrollback, so spoken output is not the record.

## 3. Starting cold

1. Resolve the panes. If the campaign is running, read `PLAN.md` and the latest report first — they, not
   your memory, say where it stands.
2. Build the **constraint block** once from every repo instruction file applicable to the target path,
   including `AGENTS.md`, `CLAUDE.md` and `CLAUDE.local.md`. Resolve scope and precedence per host:
   Codex follows `AGENTS.md`; Claude Code follows its Claude instruction files. Put shared constraints
   in the common block and conflicts in labelled host addenda. Give the planner both addenda; give each
   coder or verifier only its matching one. Include exact build/test commands and how they serialize;
   exact format/lint commands, including any that look right but are wrong here; line endings, final newline,
   encoding for new files; commit policy (assume never auto-commit); files no agent may edit
   (architecture gates, CI config — **master's** to own); model families banned for subagents.
3. Size units so one coder job plus one verifier job closes them; put them in `PLAN.md`.
4. Put open questions to the owner **before** the unit that depends on them, with a recommendation, not
   a survey. Never open a unit with a question still open inside it.

## 4. The unit cycle

master does steps 1, 2 and 6 only.

1. **Write the unit brief** into the campaign dir (§5).
2. **Clear and re-brief planner** — its context is not meant to survive a unit. Use the syntax for the
   current shell.

   POSIX shell (Linux or macOS):

   ```bash
   herdr agent send-keys <planner> ctrl+u
   herdr agent prompt <planner> "/clear"
   # confirm a fresh session before continuing
   herdr agent send-keys <planner> ctrl+u
   herdr agent prompt <planner> "$(cat <brief-file>)"
   ```

   On Git Bash for Windows, use the POSIX recipe but prefix both `herdr agent prompt` commands with
   `MSYS_NO_PATHCONV=1`.

   PowerShell:

   ```powershell
   herdr agent send-keys $planner 'ctrl+u'
   herdr agent prompt $planner '/clear'
   # confirm a fresh session before continuing
   $brief = Get-Content -Raw -LiteralPath $briefFile
   herdr agent send-keys $planner 'ctrl+u'
   herdr agent prompt $planner $brief
   ```

   Where Herdr reports an `agent_session`, compare it before and after `/clear`; otherwise read the
   pane and confirm the previous transcript is gone. Do not send the brief until reset is confirmed.
3. planner resolves coder's current host, clears coder with the same reset protocol, then briefs
   **coder** using that host's skill syntax. It judges the report against the brief. A report that
   misses the charge goes back to coder, not on to verifier.
4. planner resolves verifier's current host, clears verifier, then briefs **verifier** with the diff,
   the report path and the revert table using that host's skill syntax; verdict is PASS or FAIL with
   real suite counts.
5. planner owns the unit-local loop: FAIL goes back to coder with a fix brief, then to verifier again;
   PASS closes the unit. It may run small, bounded repair rounds without returning to master. Return
   only on PASS, a required owner decision or scope change, or repeated failure that needs replanning.
6. **master updates `PLAN.md`**, reports to the owner in a few lines, asks whether to commit.

Wait on a pane with **no `--until` flags** — `--until idle --until blocked` excludes `done`, so a
finished agent never fires the wait and you are never hooked back:

```bash
herdr agent wait <pane> --timeout 3600000
```

Run it as a separate backgrounded command. `herdr agent prompt --wait` settles on the first matching
state and can return mid-job; prompt first, wait after.

### The slash trap

**Git Bash rewrites leading `/` arguments into Windows paths before `herdr` runs.** For example,
`"/clear"` arrives as `C:/Program Files/Git/clear`, so the old transcript survives silently. Set
`MSYS_NO_PATHCONV=1` on **every** `herdr agent prompt`; choosing per call invites omissions.

Skill syntax is host-specific and must appear in the brief; plain `lean-work` invokes nothing:

| Host | Put in the brief |
|---|---|
| Claude Code | `/lean-work` on the first line |
| Codex | `$lean-work` in the request; do not send `/lean-work` |

Codex's `/skills` is interactive, not an unattended dispatch mechanism. After dispatch, confirm the
turn started and no unknown-command error remains; a Claude `Skill(<name>)` marker is useful when
present but is not a cross-host requirement. Clear composer text with `ctrl+u` first because automatic
suggestions concatenate with the command. They are UI state, not owner instructions.

The path-conversion workaround is Git Bash on Windows only. Native POSIX shells and PowerShell need no
prefix. Detect the dispatching pane's shell at each hop; master and planner need not use the same shell.

## 5. What every brief carries

Repo/worktree path spelled exactly, plus any checkout that is off-limits · campaign dir and `PLAN.md`
pointer · which unit, and the charge in one paragraph including what is out of scope · who the agent is
and who owns the build tool for this job · the target host and its correct skill invocation · the common
constraint block plus only the target's matching host addendum · the output path, and "reply with only
that path, the verdict and the counts" · the source of truth to work from and the existing file whose
idiom to follow ("follow the idiom in `<file>`" beats describing it) · for coder, the revert table (§6)
and: files written, anything the gate needs, tests that could not be written faithfully with the reason,
questions the sources could not answer.

The master→planner brief is the exception: include the planner, coder and verifier host map with each
role's invocation syntax, plus all host addenda. The planner must re-resolve a downstream pane before
dispatch and update the map if its occupant changed.

Sequence agents that would touch the same file. Two agents on one file is a lost edit.

## 6. The one proof rule: the revert table

coder delivers, per test added or changed, **the single production line whose removal or inversion turns
that test red**. verifier executes a sample — mutate, run that test class alone, confirm red, restore —
and states which proofs it ran itself versus accepted from the table. The author never verifies its own
bites; this is what catches a test that pins something other than its name claims, and a test rescued by
its own deadline.

Mutation traps: it must **compile** (a build failure looks like a red and proves nothing); it must be
real code or a string literal, never a comment (source scans strip comments); and **restore by content,
not by copying a backup** — a copy keeps the old timestamp, the build skips the rebuild, and the run
reports the previous binary, lying in both directions. Touch the write time, or confirm it rebuilt.

A guard on a branch unreachable *because the rest of the unit is correct* has no mutation: ship it with
a comment naming the invariant and say so in the report instead of padding the suite.

## 7. Remaining traps

- **`herdr agent read` refuses while the agent is working** and cannot recover scrolled-away rows. Files,
  not scrollback.
- **A pane that dies mid-job leaves its edits with no report** — indistinguishable from finished work in
  `git status`. Check for the report file, not the file list. Account or subscription errors kill a pane
  silently.
- A pane whose cwd differs from the target tree may prompt for permission. Compare the exact requested
  path with the brief. Approve only when it is expected and already within owner-authorized scope;
  otherwise report the mismatch and stop.

## 8. master never

Runs the build while an agent holds it, even "just to check" · commits, stages or pushes unasked · lets
an agent edit the architecture gate or CI config (master's, and a gate rule added without proving it
bites is untested) · spawns a subagent on a model family the owner ruled out · works from a remembered
pane layout, or writes one down.
