# Roadmap: FS25_WorkerCosts

> Ecosystem role: **Labor** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline.
> Forward-looking only. Shipped history lives in CHANGELOG.md and the releases.

## How to use this file
- Populate the milestones below from the audit baseline once it lands.
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: v2.2.2.0
- Audit reference: ecosystem-dev-tracking Point 1-7 (FS25_WorkerCosts, 2026-06-30 / 2026-07-01)
- Baseline date: 2026-07-01

## Near-term (next release cycle)
- [ ] Server-authoritative wage path (Point 7): gate `workerSystem:update` and `hireHall:update` at the call site with `getIsServer()`; leave rosterPanel:update and the client roster-sync retry outside.
- [ ] Legendary tier (fast-track F1): add the 4th tier with the LOCKED values XP_LEGENDARY=400, LEVEL_WAGE_FACTOR[4]=0.85, HIRE_COST_HOURS[4]=120, SEVERANCE_LEVEL_FACTOR[4]=2.5 (no design latitude).
- [ ] ProStaff modifiers (Point 5): read getWageModifier / getFatigueRecoveryBonus / getFatigueMitigation in calculateLaborCost and fatigue recovery; neutral 1.0 when ProStaff absent.

## Mid-term (this season)
- [ ] Bedrock migration: StateLedger (workerData + hireHallCore), NetworkSync (3 event classes), MasterHUD (roster panel), SettingsHub (remove ESC WorkerSettingsUI). Keep the addMoney hook intact.
- [ ] Companion read API: 6 functions on `workerCostsManager` (DairyCore worker tier, TaxMod wage totals).

## Long-term / aspirational
- [ ] Billing-model change: real-time to flat daily rate on onDayChange (pending the design decision below), for ecosystem coherence.

## Cross-mod / ecosystem dependencies
- [ ] Reads ProStaff (`proStaffManager`): getLevel, getWageModifier, getFatigueRecoveryBonus, getFatigueMitigation.
- [ ] Read by DairyCore (worker tier), TaxMod (wage totals), WorkplaceTriggers.
- [ ] All four bedrock migrations (blocks on: StateLedger, NetworkSync, MasterHUD, SettingsHub).

## Deferred / parked
- Real-time billing model: flagged as wrong for the ecosystem, but the change is a design decision (TysonK/Arissani) that must land before companions wire in.
