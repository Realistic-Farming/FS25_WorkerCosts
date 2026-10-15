# Changelog

All notable changes to FS25_WorkerCosts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

## [2.3.0.1] - 2026-10-15

> **This is not a final release.** It gives everyone, testers and players, new or returning, everything we have built so far, so nobody has to wait on an old version any longer. The Realistic Farming suite is far from done: we are still building and expanding every mod, and completing it could take months, possibly a year. Expect changes and rough edges along the way, and please report anything that looks wrong.

### Fixed
- **Paying or declining the monthly salary after sleeping no longer leaves you without controls.** When the month ended while you slept, the salary summary opened during sleep, and after Pay or Decline the game kept running with no controls except the console. The summary now opens when you wake up.

## [2.3.0.0] - 2026-10-12

> **This is not a final release.** It gives everyone, testers and players, new or returning, everything we have built so far, so nobody has to wait on an old version any longer. The Realistic Farming suite is far from done: we are still building and expanding every mod, and completing it could take months, possibly a year. Expect changes and rough edges along the way, and please report anything that looks wrong.

### Changed
- **Payroll follows the game's calendar.** The monthly bill is issued on the last day of each month whatever the month length (a short month used to issue no bill), each farm is billed only for its own workers, and a bill is frozen when issued: Pay and Decline act on that exact bill, and declining no longer compounds the late penalty into the amount owed.
- The Worker Costs page on the Realistic Farming Esc menu now holds hiring, firing, wage options, Reset and the crew board on one page; the old Worker Manager footer is gone.
- The emergency loan in Income Mod can read your upcoming payroll bill.

### Fixed
- A save sitting on the last day of a month no longer opens the salary dialog on the loading screen, which could stop the game from starting.
- Setting the clock backwards within a day no longer bills the "missed" hours.
- Multiplayer: hiring and firing charge the farm of the player who did it; players see the host's Worker Costs settings within about a second; an admin's change applies for everyone from any settings screen or the console, and those settings are locked for non-admins.
- The hire hall keeps its place when the roster grows.
- Key presses are registered only where they belong (on foot or in a vehicle), and the roster key has a default and shows the live key.
- Translations: the Cost Mode and Wage Level settings have their labels and Monthly Salary its tooltip, accented letters show correctly in seven languages, the settings labels reach all 26 languages, the Korean "Field Detail" label is fixed, the page legend shows a plain dot between page names, and the title and description read correctly in the mod manager.

### Added
- Changelog file established (suite ruling 2026-08-22).
- Playtest fixes: wage rate reads plain level/custom rates directly, dropping the option-scaling spine multiplier.
- Control Center action: `WC_OPEN_ROSTER` opens the Worker Costs roster from the suite Control Center (requires SettingsHub).

### Fixed
- RSF-F282 follow-up: a clock set backwards is logged once, not twice when the mod's debug mode is on; the code and test comments now say that the console setter holding the day is the design brief's reading of an engine branch that decompiles empty. No change to billing. (MAINTENANCE rows 102 and 103.)
- **Multiplayer security: hiring and firing now charge the farm of the player who asked, never a farm named by the client.** A modified client could hire into another farm's roster at that farm's cost, or fire at its cost; on both network routes the server now takes the farm from its own record of the sender, refuses a sender it cannot place or a spectator, and refuses a request that names a different farm. The host's own hiring and firing are unchanged.
- Monthly cost summary read server-snapshot `monthlyCosts` entries as raw numbers; they are tables with an `amount` field. The accrued monthly total now reads correctly.
- RSF-F201: cab and on-foot controls stay valid across vehicle entry and exit. Each input context now registers through its own private target, so the PLAYER and VEHICLE registrations no longer share one engine identifier that a cab rebuild wiped. Membership is checked in the wrap's own context, a complete set costs no registration work, and the input wrappers install once per session instead of being restored on every mission teardown. The vehicle hook no longer clears the PLAYER roster handle on every seat change.

## [2.2.3.45] - 2026-08-22

- First entry under changelog tracking.
