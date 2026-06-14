# Pro-Staff Build Plan — FS25_WorkerCosts

Status: proposed direction (not yet started)
Target: v1.0.9.5 -> 2.x
Source: community proposal issues #54-#59 (author: @Arissani)

This document is the engineering plan for the "Pro-Staff" personnel-management
overhaul. The community issues describe the desired end state; this plan maps that
end state onto how the mod actually works today and sequences it into shippable
phases.

---

## 1. Current state (verified against source)

| Area | Reality today |
|------|---------------|
| Job detection | One `g_currentMission.aiSystem:getActiveJobs()` call per frame in `WorkerSystem:update` (`src/WorkerSystem.lua:188`). No per-vehicle `onUpdate` polling. |
| Worker identity | Tracking is keyed by `tostring(worker.vehicle)`, a runtime pointer. Not stable across save/load. No worker entity exists. |
| Billing | `mission.addMoney` is hooked to suppress the game's built-in `MoneyType.AI` helper wages, then the mod charges its own via `MoneyType.OTHER` (`src/WorkerSystem.lua:89`, `:301`). |
| Wage model | Hourly OR per-hectare, single base rate x skill multiplier (0.8-1.2 from `job:getSkillLevel()`), plus a monthly salary dialog with a 20% late penalty. |
| Persistence | Settings only (`FS25_WorkerCosts.xml`). No worker data is saved. |
| UI | Full in-game menu suite already exists: `WCDashboardFrame`, `WCWorkerStatsFrame`, `WCWageSettingsFrame`, `WCSalaryDialog`. |
| Multiplayer | No network/event layer in the mod. |

## 2. Corrections to the proposal

1. **There is no `MessageType.AI_JOB_FINISHED`.** The engine publishes
   `AI_JOB_STARTED(job, startFarmId)`, `AI_JOB_STOPPED(job, aiMessage)`, and
   `AI_JOB_REMOVED(jobId)` (`AISystem`), plus a per-vehicle spec event
   `onAIJobFinished` (`AIJobVehicle`). The event-driven concept is valid; the name
   is not. Use `AI_JOB_STARTED` / `AI_JOB_STOPPED` — their payloads already carry
   the job and the owning farm id.
2. **The mod does not poll vehicles via `onUpdate`.** It makes a single active-jobs
   query per frame. The "resource-inefficient polling" premise in #57 does not match
   the code. Events help with identity lifecycle, not with a polling cost that isn't
   there.
3. **Persistent workers are net-new, not an enhancement.** Workers have no stable
   identity and nothing about them is saved today. #55 is the foundation, not a
   feature on top of existing data.

## 3. Foundational decision: what is a "worker"?

In FS25 a worker is a helper name drawn from `HelperManager`, attached to a vehicle
only for the duration of one AI job. There is no engine-side object to carry XP,
levels, or seniority.

**Decision: the mod owns its own roster (Option A).**

WorkerCosts maintains a list of hired employees. Starting an AI job on a vehicle
attributes the work to an assigned roster worker (or auto-assigns an idle one). The
game's helper system is just the engine that drives the vehicle. This is the only
model under which hire/fire, severance, assignment (#58), XP and persistence (#55)
are mutually coherent.

The rejected alternative (Option B, pin identity to game helper names) fails because
helper names are reused, the pool is finite, and a "worker" disappears the moment a
job ends.

## 4. Phased plan

Dependency order, not the proposal's 1-6 order. Each phase ships independently.

### Phase 0 — Worker identity + persistence layer (prereq; from #55)
- `WorkerRoster.lua`: `{ uuid, name, level, totalXP, totalHours, totalJobs, fatigue, hiredDay, assignedVehicleId }`.
- New save file `workerData.xml` in `savegameDirectory`, mirroring the existing
  `SettingsManager` save pattern.
- Persist via a server-only `FSCareerMissionInfo.saveToXMLFile` hook; load in
  `onMissionLoaded` where `savegameDirectory` is populated.
- Migration: none (no prior worker data). Default roster empty; created on first hire.

### Phase 1 — Event-driven job lifecycle (#57, corrected)
- Subscribe to `AI_JOB_STARTED` / `AI_JOB_STOPPED` via `g_messageCenter`.
- START: record start time, resolve vehicle + owning farm id from the payload
  (replaces the manual farm filter at `src/WorkerSystem.lua:198`), attribute to the
  assigned roster worker.
- STOP: finalize hours, award XP, emit the job-complete summary.
- Keep the per-frame accrual tick for live hourly billing and the HUD estimate.
  Events alone cannot show mid-job progress. This is a hybrid, not a rewrite.

### Phase 2 — Worker profiles + XP/levels (#55)
- XP as a function of hours worked; tiers Novice / Experienced / Master.
- Constraint conflict to resolve: the proposed Master perks ("tighter turning radii",
  "reduced fuel consumption") are vehicle behaviour, which contradicts the stated
  "no vehicle stats" rule and risks Courseplay/AutoDrive conflicts. Replace with
  economic-only perks (lower effective wage at high level, immune to fatigue
  surcharge, faster job acceptance).

### Phase 3 — Advanced wage logic (#56)
- Refactor `calculateWorkerWage` (`src/WorkerSystem.lua:269`) into `calculateLaborCost`
  with an ordered modifier pipeline: base retainer + hourly x (level -> fatigue ->
  night -> weather -> overtime). Define the additive-vs-multiplicative order once to
  avoid double-dipping.
- Night/weather read from `g_currentMission.environment` (already used in `checkMonthEnd`).
- Integrates with the existing monthly salary dialog.

### Phase 4 — In-game menu UI refresh (extend, not rebuild)
- Extend existing `WCDashboardFrame` / `WCWorkerStatsFrame` / `WCWageSettingsFrame`
  with level, fatigue, and payroll-breakdown columns from Phases 2-3.

### Phase 5 — Farm Tablet app (#58 + #59, cross-repo -> FS25_FarmTablet)
- #58 and #59 describe the same tablet app. Collapse to one (#59 closed as duplicate).
- Roster dashboard, hire/fire + severance, vehicle assignment, payroll breakdown as a
  tablet app icon.
- Requires a read API exposed from WorkerCosts (e.g. `g_workerManager:getRosterSnapshot()`)
  so FarmTablet does not reach into internals. This is a cross-repo contract.

## 5. Cross-cutting concerns

- **Multiplayer:** roster + XP live server-side. Clients need sync events
  (hire/fire/assign/level-up) plus a full-roster snapshot on join. The mod has no
  network layer today; this is the largest hidden cost of the series.
- **Severance / hire pool (#58):** economic balance plus MP event treatment.
- **Performance:** events trim the active-jobs scan but the tick stays. Net neutral,
  not the win #57 implies.

## 6. Suggested milestones

| Release | Contents |
|---------|----------|
| 2.0.0 | Phase 0 + 1 (identity, persistence, event lifecycle). Invisible to players, unlocks everything. |
| 2.1.0 | Phase 2 + 3 (XP, advanced wages) + Phase 4 UI. |
| 2.2.0 | Phase 5 Farm Tablet app + MP sync. |

## 7. Issue housekeeping

- Close #59 as a duplicate of #58.
- #58 belongs to FS25_FarmTablet; relabel/transfer.
- #57: note the corrected API names and the hybrid scope.
