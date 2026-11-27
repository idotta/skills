---
name: worker-herd
description: >-
  Coordinate several Claude worker sessions running in parallel on one machine: each in its own git worktree and
  herdr tab, sharing CPU through heavy-work slots, reviewed PR by PR, never merging. Use when starting, briefing,
  monitoring or reviewing parallel workers, when builds/tests/stress runs from several sessions collide, when a
  shared lock seems stuck, or when writing a worker brief.
---

# Worker herd

You are the coordinator: workers write the code, you brief, unblock, review and report. The user merges.

## Heavy work takes a slot

The machine is shared, so heavy commands go through `scripts/heavy.sh` (next to this file). It keeps at most
`HEAVY_SLOTS` (default 2) running at once across every worktree of the repo, using locks in
`~/.herdr/worktrees/<repo>/`.

```bash
H=~/.claude/skills/worker-herd/scripts/heavy.sh
$H --deadline 30m -- dotnet build                                     # build, full suite, lint, e2e: one slot
$H --all --deadline 30m -- taskset -c 0,1 eng/stress-tests.sh         # stress: every slot, so it runs on a quiet machine
```

- Heavy means a full build, a full test suite, lint or typecheck over the repo, e2e, or a stress run. A single test,
  a file's lint or `git` is not.
- Stress and any timing-sensitive measurement take `--all`. A run that was red while other heavy work ran settles
  nothing; rerun it under `--all` before calling a failure "load".
- `--deadline` should be about 3× the command's normal time. On expiry it writes the stacks of every .NET process in
  the command to `<lock dir>/stacks-<time>.txt` (with `dotnet-stack`, if installed) and kills the whole process group,
  so a hang frees the slot and leaves evidence instead of blocking everyone.
- A red run that reproduces under `--all` is a bug: root-cause it, or file an issue if it predates the change.

## Watching the herd

- Check about every 30 min, and whenever a report is overdue: `herdr-app ls`, `hc read <terminal> --lines 20`, the
  load (`uptime`), and who holds the slots (`fuser -v ~/.herdr/worktrees/<repo>/heavy.*`).
- A command holding a slot with little CPU time gained (`ps -o etimes,time -p <pid>`) is hung, not slow. Tell its
  worker to take stacks and kill it; don't wait for its deadline.
- Load well above the core count means something is skipping `heavy.sh`. Find it and tell its worker.

## Briefs

- Write one shared brief for what every worker has in common, plus one brief per worker. Name the coordinator session
  exactly as `ListAgents` shows it.
- The shared brief covers the worktree and branch, the repo's rules, `heavy.sh`, the shared files and who resolves
  conflicts (whoever lands second), and "PR with Closes/Part of, never merge".
- Each worker's brief covers its issue, the decisions already made (marked "don't re-litigate"), and what to report.
- Changes to the shared brief also go to the running workers by message: they won't re-read the file.

## Reviews

- Give each PR a review subagent with the code, the issue and the rules, and the worker's claims to check rather than
  your conclusion. On a loaded machine, tell it to read only, with no builds or tests.
- Send the findings back to the worker in one message: what blocks, what to fix in this PR, and what to file as an
  issue. A design call that is clearly an engineering one, you make and state. One that is the user's, you ask.
- A PR is ready when CI is green on its head, its stress run is clean under `--all`, and its review is answered. Then
  tell the user, with the merge order when PRs conflict or stack.

## Reporting to the user

Lead with what needs them: PRs ready to merge, in order, and decisions only they can make. Then one line per worker.
Report time lost and why (a hang, load, a rerun) without being asked.
