# Viewing the ecom-intel vault in Obsidian on your desktop

**TL;DR — you do NOT install Obsidian on the VPS.** The VPS is headless (no screen),
and Obsidian is a GUI viewer. A "vault" is just a folder of Markdown files. The VPS
already *builds* that folder (`vault/`) from the scrape data and *pushes it to GitHub
3×/day*. You install Obsidian on your **desktop**, point it at a clone of that folder,
and let it auto-pull. That's the whole trick.

```
  VPS (terminal only)                         GitHub                 Your desktop
  ┌─────────────────────────┐                 ┌──────┐               ┌────────────────────┐
  │ scrape → data/*.csv      │                 │ ecom │               │ git clone           │
  │ tools/vault_build.py     │  git push 3×/day│ intel│  Obsidian Git │ Obsidian opens      │
  │ → vault/ (1300+ .md)     │ ───────────────▶│ repo │ ─── pull ────▶│ vault/ as a vault   │
  │ (cron 9/12/16 IST)       │                 └──────┘  every ~15min │ you SEE everything  │
  └─────────────────────────┘                                        └────────────────────┘
```

The vault is **regenerated deterministically from `data/<platform>/history.csv`**, so the
graph never drifts from the numbers. You never edit the generated notes — you just read them.

---

## One-time desktop setup (~5 minutes)

1. **Install Obsidian** on your desktop — https://obsidian.md/download (Windows/Mac/Linux).

2. **Install git** if you don't have it, then clone the repo somewhere stable:
   ```bash
   git clone https://github.com/daman8271/ecom-intel.git
   ```
   (Private repo → log in / use a token when prompted.)

3. **Open the vault.** In Obsidian: *Open folder as vault* → select the **`vault/`
   subfolder inside the clone** (i.e. `ecom-intel/vault`), **not** the repo root.
   - You'll get a warning about trusting the vault / "Trust author and enable plugins" — say yes (it's your own data).

4. **Auto-pull new data — install the *Obsidian Git* community plugin:**
   - Settings → *Community plugins* → *Turn on community plugins* → *Browse* →
     search **"Obsidian Git"** → Install → Enable.
   - In the plugin settings set:
     - **Pull updates on interval** → e.g. `15` (minutes)
     - **Pull before push** → on (safety)
     - Leave auto-commit/auto-push **off** — you are read-only on the generated data.
   - Now every VPS cron push shows up on your desktop automatically. You can also pull
     on demand with the command palette: *Obsidian Git: Pull*.

5. **(Recommended) Install *Dataview*** the same way (Community plugins → Browse →
   "Dataview" → Install → Enable). This powers the live price dashboards — see
   `analysis/price-intel-dashboard.md` inside the vault.

That's it. Open **`index.md`** for the home map, **`VAULT-SPEC.md`** for conventions,
and **`analysis/`** for the dashboards + your own notes.

---

## Where to put YOUR own notes (important)

The generator **rebuilds** everything under `skus/`, `runs/`, `locations/`,
`platforms/`, `daily|weekly|monthly/`, plus `index.md`. **Anything you type into those
files will be overwritten on the next cron run.**

Write your own analysis ONLY in **`vault/analysis/`** (and any other new folder you
make). The generator never touches it, so it survives forever and syncs both ways via git.
One rule from the vault spec: **every note filename must be globally unique** (Obsidian
resolves `[[links]]` by basename), so don't name a personal note the same as a generated
slug. Prefix them, e.g. `analysis-canola-thesis.md`.

If you edit notes in `analysis/` on the desktop and want them back on the VPS, turn on
the Obsidian Git plugin's *commit + push* — but keep it scoped to `analysis/` to avoid
racing the cron's pushes.

---

## Other sync methods (and why git is the pick here)

| Method | Headless-VPS friendly | Setup | Verdict |
|---|---|---|---|
| **Obsidian Git plugin** (this guide) | ✅ already pushing to GitHub | trivial | **Recommended** — zero new infra |
| **Syncthing** | ✅ daemon, no GUI | medium | Good runner-up; near-real-time, P2P, but another service to run |
| **SSHFS mount** the VPS `vault/` on desktop | ⚠️ | low | Works but laggy/fragile; Obsidian's index dislikes network FS, breaks if SSH drops |
| **Obsidian Sync** (official) | ❌ | n/a | Syncs between Obsidian *apps*; the VPS isn't running Obsidian — doesn't fit |
| **rsync/scp cron** desktop-pull | ✅ | low | Fine, but git already gives this + version history + conflict handling |

Because the VPS **already** commits + pushes the vault every sweep, the Obsidian Git
plugin gets you live data with essentially no extra moving parts.

---

## How the "price intelligence model" fits

Three layers, each doing what it's best at:

1. **Data** — `data/<platform>/history.csv`: every `run × SKU × location` observation.
2. **Model** — `tools/predict.py`: deterministic forecasting that appends a *Predictions*
   sheet to each Excel workbook (stock-out risk, price/discount moves, coverage trend).
3. **View** — the Obsidian vault: a linked graph of the same data, with **Dataview
   dashboards** (`analysis/price-intel-dashboard.md`) you can slice live, plus
   `analysis/` for your own written theses.

Obsidian is the exploration + writing surface. The math stays in Python; Obsidian shows it.
