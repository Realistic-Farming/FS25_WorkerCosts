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
- [x] Server-authoritative wage path (Point 7): wage-charge chain gated with `getIsServer()`. DONE (8c70f45), shipped v2.2.2.2.
- [x] Monthly-salary double-charge gremlin (100d3c6): monthly-salary mode no longer double-charges wages. DONE.
- [x] Legendary tier (fast-track F1): 4th tier with the LOCKED values. DONE (d20da2f), shipped v2.2.2.2.
- [!] ProStaff modifiers (Point 5): read getWageModifier / getFatigueRecoveryBonus / getFatigueMitigation in calculateLaborCost and fatigue recovery; neutral 1.0 when ProStaff absent. Blocked on the ProStaff build (brief pulled, under re-review).
- [x] 2026-07-26 bug sweep: WC-001 / WC-002 / WC-003 fixed and merged to main.

## Mid-term (this season)
- [x] Bedrock migration: StateLedger (4328920), NetworkSync v2 (c179141), MasterHUD roster panel (4b10bd5), SettingsHub (ff35ed0). DONE, shipped v2.2.2.2, addMoney hook intact. (ESC WorkerSettingsUI removal still open.)
- [~] Companion read API: 6 functions on `workerCostsManager`. Partial: getWorkersForFarm shipped (90ce2e1); the rest pending DairyCore/ProStaff.

## Long-term / aspirational
- [x] Billing-model change: real-time to per-in-game-day billing on the day tick. DONE (0c808d1), shipped v2.2.2.2.

## Cross-mod / ecosystem dependencies
- [!] Reads ProStaff (`proStaffManager`): getLevel, getWageModifier, getFatigueRecoveryBonus, getFatigueMitigation. Pending the ProStaff build.
- [ ] Read by DairyCore (worker tier), TaxMod (wage totals), WorkplaceTriggers.
- [x] All four bedrock migrations DONE (StateLedger / NetworkSync / MasterHUD / SettingsHub), shipped v2.2.2.2.

## Deferred / parked
- Billing-model decision RESOLVED (per-in-game-day, middle path) and built; no longer parked.

## 2026-08-06 (Fred): Esc RF deep-desk door restored
- [x] When the RF Esc door is live, the Worker Manager (all four tabs: Dashboard, Wage Settings, Worker Stats, About) was unreachable without the Farm Tablet. A bottom-bar "Open Worker Manager" button (MENU_ACTIVATE) on the Esc panel now calls `g_gui:showGui("WCGui")` when `g_wcGui` is present. The button is present in every mod's RfPdaMenuPage copy so it works whether WorkerCosts hosts the Esc door or is a guest. In-game observation still pending.

## 2026-08-07 (Fred): module page dots always visible
- [x] The Esc RF module selector hid its page dots when Worker Costs or Market Dynamics was the active module. Soil and Crop Stress always showed theirs, so WC never read as the 3rd module and the left panel was inconsistent. All four RfPdaMenuPage copies now keep the dots visible (dots = N, chrome unchanged, per the esc-rf-pda umbrella brief). Built, deployed, PR open.

## 2026-10-04 (Fred): the shared RF Esc door at the suite's STOCK page set (Wizard, #147)

- [x] The four shared Esc door files (`xml/gui/RfPdaMenuPage.xml`, `src/gui/RfPdaMenuPage.lua`, `src/gui/RfEscModules.lua`, `xml/gui/rfEscProfiles.xml`) are at the set every door mod carries, byte-same in all ten (Wizard's STOCK page chain build, #147, merged at 61c11b9a): wider sheet cells, the explanation band at up to four lines, the ids and callbacks StockGuard's STOCK page uses (inert without StockGuard), the hidden ids and profiles of DairyCore's herd-advisory panel, ProStaff in the closed-module list, and Soil Fertilizer's AUTO target card kept. The same PR has `build.py` pack the mod's `textures/` folder as well.
- The door's in-game check is TESTING row 421. Docs by Fred's catch-up, on Tyson's word of 2026-10-04.

## 2026-10-05 (Fred): the Esc side panel's info box clear of the selected tab (Wizard, #149)

- [x] The shared Esc door file `xml/gui/RfPdaMenuPage.xml`, byte-same in all ten door mods (Wizard, #149, merged at 4d4d9fd6): the side info boxes (`rfSideInfoShell`, `wcSideInfoShell`, `mdSideInfoShell`, `csSideInfoShell`) take an explicit position and size, 16 px further right and 16 px narrower (384 to 368 px), so the dark box starts clear of the selected tab's lime edge and its right edge stays where it was. The side text bodies narrow by the same 16 px, to 352 px (the main side text, from 368) and 348 px (the Worker Costs and Market Dynamics side help, from 364), so the text starts 16 px further right and each line ends where it did.
- The change's in-game check is TESTING row 443. Docs by Fred's catch-up, on Tyson's word of 2026-10-05.

## 2026-10-06 (Fred): the mod's title and description readable again in every language (MAINTENANCE row 222)

- [x] `modDesc.xml`: 14 title and description lines (French, Polish, Czech, Ukrainian, Russian, German, Spanish, Italian, Portuguese) had been saved through the Windows cp1252 code page twice, so the mod manager showed garbled text such as "CoÃƒÂ»ts". Each is decoded back to the exact text the file held before the damage (it matches the file at the parent of 4b33dfb, 2026-08-10, line for line). Row 143 had repaired only the inline l10n block, which is why these were left. No other line changes; an XML comment further down keeps its old bytes, since no player sees it.

## 2026-10-08 (Fred): a joining player sees the host's Worker Costs settings (MAINTENANCE row 271)

- [x] In multiplayer, a client's Worker Costs screens (the dashboard, menu page, About, Stats, the Esc PDA page, the editing screens' current values) read the client's own settings, which the roster sync never carried, so a client showed its own file's values (the last server it quit) or the defaults. The roster snapshot now carries the five admin settings (on/off, cost mode, wage level, custom rate, monthly salary) on both wires, NetworkSync and the mod's own event; a pure client applies them; and every settings write on the host sends the sync, so a change reaches clients within about a second instead of at the next hire or fire. Notifications and Debug Mode stay each player's own. Design origin none (Bob's R-15).
- The in-game check is TESTING row 523. A client's own edit of an admin setting reverting at the next sync is MAINTENANCE row 290, next.
