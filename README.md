<div align="center">
  <img src="icon.png" alt="Realistic Worker Costs" width="140" />
  <h1>Realistic Worker Costs</h1>
  <p><strong>Your workers aren't free. Now your game knows it.</strong></p>

  [![Version](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_WorkerCosts?style=for-the-badge&color=4caf50&label=VERSION)](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/releases/latest)
  [![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_WorkerCosts/total?style=for-the-badge&color=2196f3)](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/releases)
  [![License](https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge)](LICENSE)
  [![FS25](https://img.shields.io/badge/Farming%20Simulator-25-brightgreen?style=for-the-badge)](#)
  [![Multiplayer](https://img.shields.io/badge/Multiplayer-Supported-success?style=for-the-badge)](#)
  [![Languages](https://img.shields.io/badge/Languages-10-orange?style=for-the-badge)](#languages)
  <a href="https://paypal.me/TheCodingDad">
    <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate via PayPal" height="50">
  </a>

  <br/>

  [**Install**](#installation) · [**Configure**](#configuration) · [**Console Commands**](#console-commands) · [**Report a Bug**](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/issues/new/choose) · [**Request a Feature**](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/issues/new/choose)

</div>

---

## What This Mod Does

In vanilla FS25, hired AI workers cost nothing. That makes labor a free resource — which kills any incentive to manage your workforce strategically.

**Realistic Worker Costs** fixes that. Every AI worker you hire accumulates wages in real time and bills your farm at regular intervals. You choose how you want to pay them — by the hour or by the hectare — and you set the rate. Cheap labor, fair wages, or premium crew: the choice has consequences.

The mod ships with a full **in-game manager UI** (accessible from the pause menu), integrates with the vanilla settings screen, and exposes everything via console commands.

---

## Features

| | Feature | Detail |
|---|---|---|
| 💰 | **Two payment modes** | Hourly `$/h` or Per Hectare `$/ha` — switch at any time |
| 📊 | **Three wage tiers** | Low · Medium · High — with a custom rate override |
| 🧠 | **Skill-based multipliers** | Higher-skill workers earn 80 %–120 % of the base rate |
| 🖥️ | **In-game manager** | Dedicated pause-menu tab with 4 pages: Dashboard, Wage Settings, Worker Stats, About |
| ⚙️ | **Vanilla settings integration** | Controls also injected into the standard Settings screen |
| 🔔 | **Payment notifications** | HUD popup on every payment cycle (toggleable) |
| ⏱️ | **Real-time timing** | Wages scale with real elapsed time — not game speed |
| 👷 | **Dismissed-worker payouts** | Workers fired mid-interval still get paid for time worked |
| 🌐 | **10 languages** | EN · DE · FR · PL · ES · IT · CZ · PT · UK · RU |
| 🤝 | **Multiplayer ready** | Full support for co-op and dedicated servers |
| 💾 | **Per-savegame settings** | Each save has its own configuration |
| 🎮 | **Console commands** | Full control via the in-game developer console |

---

## Screenshots

> *The built-in manager — accessible from the pause menu.*

![Dashboard](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/assets/dashboard-preview.png)

<details>
<summary>More screenshots</summary>

> *Wage Settings tab — configure cost mode, wage level, and see the live rate preview.*

> *Worker Stats tab — per-worker cost breakdown refreshed every 500 ms.*

</details>

---

## Installation

### From a Release (recommended)

1. Go to the [**Releases page**](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/releases/latest)
2. Download `FS25_WorkerCosts.zip`
3. Drop the zip (do **not** extract) into your mods folder:

   ```
   Documents\My Games\FarmingSimulator2025\mods\
   ```

4. Launch FS25, enable the mod in the Mod Manager, and start your save

> **Steam users:** Right-click the game → Manage → Browse local files to find your mods path if it differs.

### From Source

```bash
git clone https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts.git
cd FS25_WorkerCosts
bash build.sh --deploy
```

---

## Configuration

### In-Game Manager

Open the pause menu → click the **Realistic Worker Costs** tab (the worker icon).

| Page | What's here |
|------|-------------|
| **Dashboard** | Live status: active workers, next payment countdown, farm balance |
| **Wage Settings** | Cost mode, wage level, notifications, debug toggle, reset button |
| **Worker Stats** | Per-worker cost breakdown, refreshed every 500 ms |
| **About** | How the mod works, wage reference table, current version |

### Vanilla Settings Screen

The mod also injects a **Worker Costs Mod** section into `Pause → Settings → Game` — useful if you prefer the native settings flow. A **Reset Settings** button is added to that screen's footer.

### Settings Reference

| Setting | Options | Default | Notes |
|---------|---------|---------|-------|
| **Mod Enabled** | On / Off | On | Master switch |
| **Cost Mode** | Hourly / Per Hectare | Hourly | See [Wage System](#wage-system) |
| **Wage Level** | Low / Medium / High | Medium | Ignored when Custom Rate > 0 |
| **Custom Rate** | Any number ≥ 0 | 0 | Set to 0 to use Wage Level |
| **Notifications** | On / Off | On | HUD popup on each payment |
| **Debug Mode** | On / Off | Off | Enables `[Worker Costs]` log lines |

---

## Wage System

### Payment Cycle

Workers are paid every **5 real-world minutes**. The timer runs in real time regardless of your in-game time-speed setting — 4× speed does not charge you 4× more.

Workers dismissed mid-interval are automatically settled at the next payment tick — no unpaid labour.

### Hourly Mode

```
wage = base_rate × hours_worked × skill_multiplier
```

| Tier | Base Rate | Min (skill 0%) | Standard (skill 50%) | Max (skill 100%) |
|------|-----------|----------------|----------------------|-----------------|
| Low | $15 /h | $12 /h | $15 /h | $18 /h |
| Medium | $25 /h | $20 /h | $25 /h | $30 /h |
| High | $40 /h | $32 /h | $40 /h | $48 /h |

> **Example:** 3 workers on Medium, running for the full 5-minute interval:
> `$25 × (5/60) hours × 1.0 skill × 3 workers = ~$6.25`

### Per-Hectare Mode

```
wage = base_rate × hectares_worked × skill_multiplier
```

Ideal for large field operations — you pay for output, not clock time. Note: implements that don't expose worked area data will report 0 ha and incur no charge.

### Custom Rate

Set any positive number in **Custom Rate** to bypass the tier system entirely. Set it back to `0` to resume using the Wage Level setting.

---

## Console Commands

Open the console with the **`~`** key:

| Command | Description |
|---------|-------------|
| `workerCosts` | List all available commands |
| `workerCostsStatus` | Show current mod status and active rate |
| `WorkerCostsEnable` | Enable the mod |
| `WorkerCostsDisable` | Disable the mod |
| `WorkerCostsSetWageLevel 1\|2\|3` | `1` = Low · `2` = Medium · `3` = High |
| `WorkerCostsSetCostMode 1\|2` | `1` = Hourly · `2` = Per Hectare |
| `WorkerCostsSetNotifications true\|false` | Toggle payment HUD popups |
| `WorkerCostsSetCustomRate <amount>` | Custom rate (`0` = use Wage Level) |
| `WorkerCostsTestPayment` | Deduct a $100 test charge |
| `WorkerCostsShowSettings` | Full settings dump |
| `WorkerCostsResetSettings` | Reset everything to defaults |
| `wcReloadGui` | Reload the mod GUI without restarting |

---

## Troubleshooting

<details>
<summary><strong>Workers aren't being charged</strong></summary>

1. Run `workerCostsStatus` — confirm `Enabled: true`
2. Make sure AI workers are actually hired and active (not just vehicles parked)
3. Turn on **Debug Mode** and watch `log.txt` for `[Worker Costs]` lines
4. Run `WorkerCostsTestPayment` — if $100 is deducted, the payment system is working fine and the issue is worker detection

</details>

<details>
<summary><strong>Mod doesn't appear in the Settings screen</strong></summary>

1. Confirm the mod is enabled in the Mod Manager before loading the save
2. Check `log.txt` for any load errors
3. The mod section appears under **Pause → Settings → Game** — scroll down if needed

</details>

<details>
<summary><strong>Settings aren't saving between sessions</strong></summary>

Settings are stored per-savegame at:
```
Documents\My Games\FarmingSimulator2025\saves\savegame<N>\FS25_WorkerCostsMod.xml
```
If that file is missing or can't be written, the mod falls back to defaults each load. Check folder permissions.

</details>

<details>
<summary><strong>Per-hectare mode charges nothing</strong></summary>

Not all implements expose worked-area data to the game's AI system. If the implement your worker is using doesn't report hectares, the mod has no area to bill — this is a limitation of the FS25 API, not a bug. Switch to Hourly mode for those workflows.

</details>

<details>
<summary><strong>Where is the log file?</strong></summary>

```
Documents\My Games\FarmingSimulator2025\log.txt
```
Search for `[Worker Costs]` — all mod activity (when Debug Mode is on) and any errors are tagged with this prefix.

</details>

---

## Changelog

### v2.1.0.0 — Pro-Staff Goes Multiplayer
- New: **full multiplayer** — the roster is host-authoritative and syncs to every client; clients can hire, fire, and assign and the result broadcasts back to everyone
- New: **recruitment pool** — a rotating set of candidates with their own level and one-off **signing cost**; hire a specific candidate or reroll the pool
- New: **cross-mod command + financial API** — `hireWorker` / `fireWorker` / `assignWorker` plus an enriched roster snapshot (per-worker effective rate, severance, and Pro-Staff cost impact) for the Farm Tablet **Personnel** app
- Change: the **Pro-Staff Panel** (ALT+H) now routes through the same command pipeline, so a host action also syncs to clients and hiring applies the signing cost everywhere

### v2.0.0.0 — Pro-Staff
- New: **Pro-Staff roster** — the mod now keeps a real list of hired workers that survives save/reload, instead of nameless one-off helpers
- New: workers gain **XP from hours worked** and rank up Novice → Experienced → Master (40h / 160h), with a promotion notice
- New: **fatigue** builds up as workers run jobs and recovers while they rest, feeding into the wage pipeline
- New: **advanced wage pipeline** — base retainer plus hourly rate modified by level, fatigue, night, weather, and overtime
- New: **hire / fire / severance** and **durable vehicle assignment** — pin a worker to a vehicle and the pin survives save/reload
- New: clickable **Pro-Staff Panel** — open with **ALT+H** (rebindable) or the `WorkerCostsRoster` console command to hire, fire, and assign without the console
- New: **Farm Tablet integration** — the WorkerCosts app now shows the roster (level, hours, jobs, fatigue) when FS25_FarmTablet is installed
- Note: roster management is host/single-player for now; multiplayer client sync is coming in a follow-up

### v1.0.9.5 — Settings Persistence & UI Wording
- Fixed: Payment Strategy and Compensation Tier reverted to defaults after a save/reload — settings are now reloaded once the savegame is available, so your choices stick
- Changed: renamed "Cost Mode" to **Payment Strategy** and "Wage Level" to **Compensation Tier** in the Wage Settings tab
- Polish: removed the duplicate row labels under each section header in the Wage Settings tab

### v1.0.4.0 — Audit & Polish
- Fixed: per-hectare mode showed mode-name string as a cost value in Worker Stats tab
- Fixed: worker cost rows showed a `+` prefix (implying income) — corrected to `-`
- Fixed: `farmId == 0` guard in payment system (spectator slot in multiplayer)
- Fixed: `WCAboutFrame` hardcoded fallback version — now reads live from `g_modManager`
- Polish: `workerCostsStatus` and `ShowSettings` commands now show `/h` or `/ha` correctly
- Polish: bare `print()` calls replaced with `Logging.info()` throughout
- Polish: all file header version numbers brought in sync

### v1.0.2.0 — Tabbed Manager UI
- Added: full in-game manager accessible from the pause menu
- Added: 4-tab inner UI — Dashboard, Wage Settings, Worker Stats, About
- Added: custom tab icon spritesheet with per-tab pictograms
- Added: per-page header icons
- Fixed: `addMoney` hook narrowed to only suppress `MoneyType.WORKER_WAGES`

### v1.0.1.x — Core Fixes
- Fixed: replaced `environment.dayTime` with real-time `dt` — eliminated ~20× overcharge at high game speeds
- Fixed: dismissed workers now receive a final payout at the next settlement tick
- Fixed: `WorkerSettingsUI` local `getTextSafe` restored after refactor

### v1.0.0.0 — Initial Release
- Hourly and per-hectare payment modes
- Three wage tiers with skill multipliers
- Vanilla settings screen integration
- Console commands
- 10-language support

---

## Languages

| Language | Code | Language | Code |
|----------|------|----------|------|
| English | `en` | Czech | `cz` |
| German | `de` | Portuguese (BR) | `br` |
| French | `fr` | Ukrainian | `uk` |
| Polish | `pl` | Russian | `ru` |
| Spanish | `es` | Italian | `it` |

---

## Contributing

Contributions are welcome! Please read [**CONTRIBUTING.md**](CONTRIBUTING.md) before opening a PR.

- Branch off `development` — never commit directly to `main`
- Test in-game before submitting
- Use the [issue templates](https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/issues/new/choose) for bug reports and feature requests

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

<div align="center">
  <sub>Made for the FS25 modding community · <a href="https://github.com/TheCodingDad-TisonK/FS25_WorkerCosts/issues/new/choose">Report an Issue</a></sub>
</div>
