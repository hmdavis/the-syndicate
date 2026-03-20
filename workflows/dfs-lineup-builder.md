# DFS Lineup Builder Workflow

> **Hybrid pipeline:** Claude Code auto-chains agents and surfaces checkpoints
> between steps. Full DFS pipeline from slate to CSV export.

## How to Run

Activate the **Sharp Orchestrator** agent in Claude Code and prompt:

    Build 50 GPP lineups for DraftKings NFL main slate, [DATE].

For cash games:

    Build 3 cash lineups for FanDuel NBA tonight.

The orchestrator reads this workflow and executes each step.

## Inputs

- `{sport}` — Sport key (`NFL`, `NBA`, `MLB`, `NHL`)
- `{platform}` — `DraftKings` or `FanDuel`
- `{contest_type}` — `GPP` or `CASH`
- `{slate_date}` — Slate date (YYYY-MM-DD)
- `{slate_type}` — `main`, `afternoon`, `primetime`, or `showdown`
- `{n_lineups}` — Number of lineups to build (GPP: 20-150, Cash: 1-5)

## Agents Involved

| Step | Agent | Role |
|------|-------|------|
| 1 | (orchestrator) | Load slate — player pool, salaries, game info |
| 2 | Injury Monitor | Confirm availability, remove OUT/DOUBTFUL |
| 3 | DFS Projector | Monte Carlo projections (10,000+ sims) |
| 4 | DFS Lineup Optimizer | ILP/heuristic construction under salary cap |
| 5 | (orchestrator) | Apply correlation stacks |
| 6 | (orchestrator) | Apply ownership leverage |
| 7 | (orchestrator) | Export CSV for platform upload |

Supporting agents invoked by DFS Projector in Step 3:
- Meteorologist — weather adjustments for NFL outdoor (wind kills passing ceilings)
- Stats Collector — recent performance, matchup grades, usage rates

---

## Platform Roster Configurations

### DraftKings NFL
| Slot | Count | Notes |
|------|-------|-------|
| QB | 1 | |
| RB | 2 | |
| WR | 3 | |
| TE | 1 | |
| FLEX | 1 | RB / WR / TE |
| DST | 1 | |
| Salary Cap | — | $50,000 |

### FanDuel NFL
| Slot | Count | Notes |
|------|-------|-------|
| QB | 1 | |
| RB | 2 | |
| WR | 3 | |
| TE | 1 | |
| FLEX | 1 | RB / WR / TE |
| K | 1 | |
| Salary Cap | — | $60,000 |

### DraftKings NBA
| Slot | Count | Notes |
|------|-------|-------|
| PG | 1 | |
| SG | 1 | |
| SF | 1 | |
| PF | 1 | |
| C | 1 | |
| G | 1 | PG / SG |
| F | 1 | SF / PF |
| UTIL | 1 | Any |
| Salary Cap | — | $50,000 |

### FanDuel NBA
| Slot | Count | Notes |
|------|-------|-------|
| PG | 2 | |
| SG | 2 | |
| SF | 2 | |
| PF | 1 | |
| C | 1 | |
| Salary Cap | — | $60,000 |

---

## Step 1 — Load Slate (no agent dispatch)

**Depends on:** none

**Purpose:** Pull player pool, salaries, and game information from the platform.

**Action:** Fetch the player pool for {platform} {sport} {slate_type} slate on {slate_date}. Data needed per player: name, team, position, salary, projected ownership %, game (opponent, time, O/U line), and injury status.

Sources:
- DraftKings: `GET https://api.draftkings.com/lineups/v1/games/{contest_id}/draftables`
- FanDuel: `GET https://api.fanduel.com/contests/{contest_id}/players`
- Or export CSV from the platform's Lineup Tool

**Checkpoint:**

    Slate loaded: {platform} {sport} {slate_type} | {slate_date}
    Players: N | Games: N | Salary cap: $X
    Proceed? (yes / switch slate / halt)

---

## Step 2 — Injury Monitor

**Agent:** Injury Monitor
**Depends on:** Step 1
**Dispatch mode:** foreground

**Purpose:** Confirm player availability before projecting.

**Dispatch prompt:**
> Activate Injury Monitor. Check injury status for all players in
> this {sport} slate: {slate_players}. Remove from player pool: all
> OUT designations and DOUBTFUL (< 30% active rate historically in
> NFL). Flag for manual review: QUESTIONABLE within 6 hours of lock
> time, and players with limited practice participation. Do not
> project any QUESTIONABLE player until confirmed active. Output:
> removed players, flagged players, and the cleaned player pool.

**Expected output:** Cleaned player pool with removals and flags.

**Checkpoint:**

    Removed: N players (OUT/DOUBTFUL)
    Flagged: N players (QUESTIONABLE — awaiting confirmation)
    Clean pool: N players remaining
    Proceed? (yes / exclude [player] / include [player] / halt)

---

## Step 3 — DFS Projector

**Agent:** DFS Projector
**Depends on:** Step 2 (cleaned player pool)
**Dispatch mode:** foreground

**Purpose:** Run Monte Carlo simulations to build full projection distributions per player.

**Dispatch prompt:**
> Activate DFS Projector. Run 10,000+ Monte Carlo simulations for
> each player in this cleaned pool: {cleaned_pool}. Sport: {sport}.
> Platform: {platform}. Use base projections from recent form +
> matchup grades. Model positively skewed distributions (upside
> unlimited, floor is 0). Include positional correlations (NFL:
> QB+WR1 stack correlation 0.55-0.65; MLB: SP+hitter stack). Apply
> weather adjustments for NFL outdoor if wind >= 15 mph (reduce
> QB/WR ceilings 15-25%). Use snap/minutes/usage from injury
> confirmations. Output per player: projection mean, median, floor
> (P10), ceiling (P90), ownership projected, value score
> (mean / salary per 1000), ceiling leverage score, and stack
> correlations with teammates.

**Expected output:** Projection distributions per player with value scores and correlation data.

**Checkpoint:**

    Projections complete: N players | Sport: {sport}
    Top value plays:
    - [player] ([pos]) $[salary] | proj: [mean] | own: [pct]% | value: [X]x
    Proceed? (yes / adjust [player] projection / exclude [player] / halt)

---

## Step 4 — DFS Lineup Optimizer

**Agent:** DFS Lineup Optimizer
**Depends on:** Step 3 (projections)
**Dispatch mode:** foreground

**Purpose:** Construct optimal lineups under salary cap and position constraints.

**Dispatch prompt:**
> Activate DFS Lineup Optimizer. Build {n_lineups} lineups for
> {platform} {sport} {contest_type}. Salary cap: {salary_cap}.
> Roster config: {roster_config}. Projections: {projections_output}.
> For CASH: maximize expected median score using integer linear
> programming. For GPP: maximize ceiling-weighted score with
> ownership leverage factor (1 / sqrt(projected_ownership)). Apply
> constraints: salary cap, position slots, max players from single
> team. For GPP, force at least one correlation stack per lineup
> (NFL: QB+WR pair; NBA: 3+ players from highest-total game;
> MLB: 4-player stack vs weakest SP).

**Expected output:** N lineups meeting all constraints with projected scores.

**Checkpoint:**

    Lineups built: {n_lineups} | Type: {contest_type}
    Avg projected score: [X] | Salary usage: [X]% avg
    Primary stack: [QB + WR pair or game stack]
    Proceed to leverage? (yes / rebuild with [constraint] / halt)

---

## Step 5 — Correlation Stacks (no agent dispatch)

**Depends on:** Step 4

**Purpose:** Validate and enforce correlation structures across the lineup set.

**Action:** For GPP lineups, verify each lineup contains at least one correlation stack:

**NFL stacks:**
- Primary: QB + WR1 or WR2 from same team (correlation 0.55-0.65)
- Bring-back: WR or RB from opposing team (benefits from trailing game script)
- Mini-stack: TE from primary QB's team (correlation 0.45-0.60)

**NBA stacks:**
- Game stack: 3-4 players from highest projected total game
- Spread across both teams in the featured game

**MLB stacks:**
- 4-player minimum stack against weakest SP on slate
- Batting order correlation: positions 1-4 correlate more strongly

Rotate stacks across the lineup set to maximize ownership differentiation.

**Checkpoint:**

    Stacks validated: N/{n_lineups} lineups have correlation stack
    Primary stack: [description] — used in [pct]% of lineups
    Bring-back: [player] — used in [pct]% of lineups
    Proceed? (yes / force stack [players] / halt)

---

## Step 6 — Ownership Leverage (no agent dispatch)

**Depends on:** Step 5

**Purpose:** Differentiate GPP lineups through ownership-based leverage.

**Action:** Apply leverage tiers to the lineup set:
- CONTRARIAN (ownership < 5%): high leverage, significant differentiation
- LOW-OWNED (5-12%): good leverage
- MEDIUM (12-25%): standard
- CHALK (25%+): negative leverage in large GPP fields

For a {n_lineups}-lineup set:
- 30% of lineups: at least one CONTRARIAN play at premium position (QB or RB)
- 70% of lineups: mix of LOW-OWNED pivots from projected chalk
- 10% of lineups: full fade of the highest-owned player on slate

For CASH games, skip this step — cash optimizes for floor, not differentiation.

**Checkpoint:**

    Leverage applied: {contest_type}
    Chalk exposure (>25% own): [player] in [pct]% of lineups
    Contrarian plays (<8% own): [player] in [pct]% of lineups
    Full fades: [player] ([own]% ownership) in 0 lineups
    Proceed to export? (yes / adjust leverage / halt)

---

## Step 7 — Export CSV (no agent dispatch)

**Depends on:** Step 6 (or Step 5 for CASH)

**Purpose:** Export lineups in platform-specific CSV format for bulk upload.

**Action:** Format lineups for {platform} bulk upload:

DraftKings NFL: `QB,RB,RB,WR,WR,WR,TE,FLEX,DST`
FanDuel NFL: `QB,RB,RB,WR,WR,WR,TE,FLEX,K`
DraftKings NBA: `PG,SG,SF,PF,C,G,F,UTIL`
FanDuel NBA: `PG,PG,SG,SG,SF,SF,PF,C`

Save to `output/dfs/{slate_date}/lineups_{platform}_{sport}.csv`.

**Checkpoint:**

    Exported: {n_lineups} lineups to output/dfs/{slate_date}/lineups_{platform}_{sport}.csv
    Format: {platform} {sport} bulk upload
    Ready for upload. Verify platform before submitting.

---

## Lineup Set Output Summary

```
================================================================================
DFS LINEUP BUILDER -- SUMMARY
================================================================================
Sport:          [NFL / NBA / MLB]
Platform:       [DraftKings / FanDuel]
Slate:          [Slate Type] -- [YYYY-MM-DD]
Contest Type:   [GPP / CASH]
Lineups Built:  [N]
Generated:      [YYYY-MM-DD HH:MM ET]

TOP PROJECTED PLAYS (by ceiling leverage score):
  [POS]:  [Player] ([Team])    $[salary]  |  proj: [X] | own: [X]% | value: [X]x
  ...

PRIMARY STACK: [players] ([team]) -- correlation [X]
BRING-BACK: [player] ([team]) -- benefits from [game script]

OWNERSHIP EXPOSURE:
  Chalk plays (>25% own):   [players] used in [X]% of lineups
  Leverage plays (<8% own): [players] in [X]% of lineups
  Full fades:               [player] ([X]% own) in 0 lineups

OUTPUT: [filename] ([N] lineups, ready for bulk upload)
================================================================================
```

---

## Intervention Commands

Available at any checkpoint:

| Command | Effect |
|---------|--------|
| `yes` / Enter | Proceed to next step |
| `halt` | Stop the pipeline |
| `lock [player]` | Force player into all lineups |
| `exclude [player]` | Remove player from pool |
| `adjust [n_lineups]` | Change number of lineups |
| `switch [platform]` | Change target platform |
| `rebuild` | Re-run optimizer with new constraints |

---

## Decision Rules

- **No QUESTIONABLE players unless confirmed active within 2 hours of lock.** Do not project uncertain availability.
- **GPP lineups must include at least one player < 8% projected ownership per lineup.** Differentiation is mandatory.
- **Cash floor minimum.** Do not use players with P10 floor below 8 fantasy points in cash lineups.
- **Never cross-submit platforms.** DraftKings and FanDuel formats differ. Verify platform before exporting.
- **Recalculate on late scratch.** If a significant injury or late scratch is announced after Step 3, re-run from Step 2.
- **Value score minimums.** Cash: 3.0x minimum. GPP: 2.5x minimum (trades value for upside).
- **Log all lineups.** Log submitted lineups and contest results to `~/.syndicate/bankroll.db` for ROI tracking.

---

## Constraints & Disclaimers

This system is for **educational and research purposes only**. Output is based on Monte Carlo simulations and mathematical optimization. It is not a guarantee of profit and should not be construed as financial or gambling advice.

- DFS involves substantial risk of loss.
- No model eliminates variance.
- Bet only what you can afford to lose entirely.
- **Problem gambling resources:** 1-800-522-4700 | ncpgambling.org
