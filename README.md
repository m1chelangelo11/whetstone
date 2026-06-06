# agent-learn-mode

**Learning mode for AI coding agents.** The agent guides you, names APIs, critiques
and helps you debug — but it **never writes the code for you**. You generate every
line yourself. Built for learning to program, not for shipping faster.

The premise: you learn when you *generate*, not when you *recognize*. Code handed to
you reads as obvious, you nod, and a week later you can't reproduce it. This setup
removes that shortcut on purpose.

---

## What's in here

```
agent-learn-mode/
├── .ai/
│   ├── core.md        # the contract (always-on): the wall, hint ladder, gates
│   ├── phases.md      # state machine: DESIGN → BUILD → REVIEW / DEBUG
│   └── handoff.md     # the fixed shape of every agent turn
├── install.sh         # installs into a target project (copy or submodule)
├── CLAUDE.snippet.md  # manual-install fallback (the import lines)
└── README.md
```

## The contract in brief

Full text in [`.ai/core.md`](.ai/core.md). The load-bearing rules:

- **The wall** — the agent never emits code as a solution to your task. It may name
  an API/library/feature ("use `collections.defaultdict`") but not show how to wire
  them. Default boundary: *APIs yes, wiring no.*
- **Hint ladder** — starts at the lowest rung that unblocks (a question), climbs only
  after a real attempt from you. Never starts by handing an answer.
- **Attempt-first** — it won't move past a sticking point until you show an attempt.
- **Reproduce-from-blank gate** — before advancing, you must restate the logic in your
  own words. If you can't reproduce it, you go back, not forward.
- **Code-as-study is allowed** — it *may* show reference code, stdlib source, or your
  own pasted code for analysis. Reading other people's code is encouraged; only code
  that solves your current task is off-limits.
- **One step per turn** — you drive with "next".
- **Hard under pressure** — "just write it all" gets reminded of the wall once, then
  the highest allowed rung. It does not fold.

## Install

The target project must be a git repo if you use submodule mode. Run interactively
(asks for mode + wall) or pass flags.

```bash
# interactive — from inside the target project
cd ~/projects/my-app
bash ~/projects/agent-learn-mode/install.sh

# non-interactive
bash install.sh --target ~/projects/my-app --mode copy --wall hard
```

| Flag       | Values                  | Meaning                                              |
|------------|-------------------------|------------------------------------------------------|
| `--target` | path (default: cwd)     | project to install into                              |
| `--mode`   | `copy` \| `submodule`   | how the `.ai/` files are placed                      |
| `--wall`   | `hard` \| `soft` \| `off` | how strictly file writes are blocked               |
| `--repo`   | git URL                 | source repo for submodule mode                       |

What it does, idempotently (safe to re-run):

1. Places `.ai/` — copied to the project root (`copy`), or added as a submodule at
   `.agent-learn/` (`submodule`).
2. Injects the import lines into the project's `CLAUDE.md`, inside a
   `<!-- agent-learn-mode -->` marker block, as **plain text** (Claude Code does not
   evaluate `@imports` inside code fences). Existing `CLAUDE.md` content is preserved;
   the paths match the chosen mode automatically.
3. Sets the wall in `.claude/settings.json` (merged via `jq`, existing rules kept).
4. Backs up (`*.bak.<timestamp>`) anything it changes.

> `jq` is required for `--wall hard`/`soft`. `--wall off` needs nothing.

## The wall: hard / soft / off

This is your call, and the installer makes you make it each time.

- **hard** → `permissions.deny` for `Edit`, `Write`, `MultiEdit`, `NotebookEdit`. The
  agent physically cannot touch files. You type everything.
- **soft** → the same tools in `permissions.ask`. The agent prompts you each time
  instead of refusing — a wall that yields, but only on a deliberate click.
- **off** → no enforcement. The contract still applies as context (the agent usually
  honors it), but nothing blocks a slip.

A wall that yields on demand yields at 11pm before a deadline. Pick `hard` unless you
have a reason not to.

> **VSCode extension caveat:** there have been reports of the VSCode extension ignoring
> `permissions` rules. If you run Claude Code there, run the edit test below to confirm
> the wall actually blocks. The terminal CLI enforces reliably.

## Verify (do all three)

```bash
# 2) settings parse cleanly (a typo here silently disables the wall)
jq . .claude/settings.json
```

1. Start Claude Code in the project, run `/memory` → `core.md`, `phases.md`,
   `handoff.md` must appear in the loaded files.
2. `jq` (above) parses without error.
3. Ask the agent to edit a file → it must **refuse** (hard) or **prompt** (soft).

## Copy vs submodule

- **copy** — simplest. A frozen snapshot in the project. To update: `git pull` this
  repo, then re-run `install.sh --mode copy` (it's idempotent). Best for solo work on
  one machine.
- **submodule** — one source of truth, version-pinned per project, survives cloning to
  another machine and works for collaborators. Costs ceremony and has a sharp edge:
  `git clone` **without** `--recurse-submodules` leaves `.agent-learn/` empty and the
  wall silently gone.

```bash
# clone a project that uses the submodule
git clone --recurse-submodules <project-url>
# or, after a plain clone:
git submodule update --init --recursive

# update the contract to the latest pushed version
git submodule update --remote .agent-learn
git add .agent-learn && git commit -m "bump agent-learn-mode"
```

**Recommendation:** stay on `copy` until you use this across *multiple projects and
multiple machines* at once. Submodule is an optimization for scale you may not have yet.

## Your side of the contract

The repo enforces its half. This half is yours, and no file can enforce it:

- You write every line.
- You don't accept a step you can't reproduce from a blank page.
- You treat the reproduce-from-blank gate as real, not a formality.

Without it, the wall is theater. With it, in six months this was learning.

## Requirements / notes

- **Claude Code.** The wall uses `permissions` rules; `@imports` use Claude Code's
  memory system.
- **`jq`** for `--wall hard`/`soft`.
- Keep each contract file under ~200 lines — longer files dilute context and reduce
  how reliably the agent follows them.
- `CLAUDE.md` (with the imports) loads at launch and survives `/compact`.