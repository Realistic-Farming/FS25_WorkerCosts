# Contributing to FS25 Realistic Worker Costs

Thanks for taking the time to contribute! Here's how to get started.

---

## Getting Started

1. **Fork** the repository and clone your fork locally.
2. Work on the `development` branch — never commit directly to `main`.
3. Test your changes in-game before submitting a PR.

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable releases only |
| `development` | Active development — base your PRs here |

---

## Environment Setup

| Resource | Location |
|----------|----------|
| Active Mods | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods` |
| Game Log | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt` |

**Build & deploy:**
```bash
py build.py --deploy
```

After deploying, load a save in FS25 and watch `log.txt` for lines tagged `[Worker Costs]`.

---

## Code Guidelines

- **Lua 5.1 only** — no `goto`, no `continue`, no `os.time()`. See the constraints table in `CLAUDE.md`.
- **Real-time `dt`** — all timing uses real elapsed milliseconds from `FSBaseMission.update`, never `environment.dayTime`.
- **Idempotent UI injection** — any code that injects into the FS25 menu must be safe to call multiple times.
- **Guard `g_currentMission`** — it is `nil` during mod load. Always wait for the mission lifecycle callbacks.
- **Client-only UI** — wrap all UI code with `mission:getIsClient()`.
- Keep changes focused. One feature or fix per PR.

---

## Submitting a Pull Request

1. Target the `development` branch.
2. Write a clear title: `fix(WorkerSystem): ...` / `feat(GUI): ...` / `chore: ...`
3. Describe what changed and why — include relevant log output if fixing a bug.
4. Confirm you tested in-game (single-player at minimum).

---

## Reporting Issues

Use the GitHub issue templates — there are templates for bug reports, feature requests, and mod compatibility problems.

---

## Questions

Open a [GitHub Discussion](../../discussions) rather than an issue for general questions or ideas.
