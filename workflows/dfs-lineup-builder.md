# DFS Lineup Builder Workflow

Full DFS pipeline: slate selection → player projections → lineup optimization → correlation stacks → ownership leverage → CSV export. Supports DraftKings and FanDuel.

---

## How to Run

### Claude Code (recommended)

Open Claude Code in the `the-syndicate` repo, select the **DFS Lineup Optimizer** or **Sharp Orchestrator** agent, then prompt:

```
Build 50 GPP lineups for DraftKings NFL main slate, November 24 2024.
```

Claude Code will run projections, optimize lineups with salary cap constraints and correlation stacks, apply ownership leverage, and export a CSV ready for bulk upload.

For cash games:
```
Build 3 cash lineups for FanDuel NBA tonight.
```

### Claude Desktop

Not supported for lineup optimization — requires PuLP/scipy for linear programming and filesystem access to export CSV. You can discuss strategy, stacking theory, and ownership leverage in Claude Desktop, but actual lineup generation requires Claude Code.

### CLI (standalone)

The optimizer uses PuLP for integer linear programming. To run independently:

```bash
pip install pulp numpy pandas scipy

# You'll need player salaries + projections as input.
# Export from DraftKings/FanDuel, or scrape via the API endpoints
# documented in Step 1 below.

# The optimization code is in agents/dfs/dfs-lineup-optimizer.md.
# The projection Monte Carlo is in agents/dfs/dfs-projector.md.
```

The exported CSV uploads directly to DraftKings or FanDuel via their bulk lineup import.

---

## Sport Context

DFS is slate-specific. Set sport and contest type before running. GPP (tournament) and cash (50/50, double-up) require different optimization strategies.

```
SPORT:        [NFL | NBA | MLB | NHL]
PLATFORM:     [DraftKings | FanDuel]
CONTEST_TYPE: [GPP | CASH]
SLATE_DATE:   [YYYY-MM-DD]
SLATE_TYPE:   [main | afternoon | primetime | showdown]
N_LINEUPS:    [1–150]  # GPP: 20–150, Cash: 1–5
```

Example:
```
SPORT:        NFL
PLATFORM:     DraftKings
CONTEST_TYPE: GPP
SLATE_DATE:   2024-11-24
SLATE_TYPE:   main
N_LINEUPS:    50
```

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

## Agents Involved

| Agent | Role | Output |
|-------|------|--------|
| `dfs-projector` | Monte Carlo fantasy point distributions per player | `projections.json` |
| `dfs-lineup-optimizer` | ILP/heuristic lineup construction under salary cap | `lineups.csv` |

Supporting data agents (invoked by dfs-projector):
- `injury-monitor` — confirm player availability and snap/minutes projections
- `meteorologist` — weather adjustments for NFL outdoor games (wind kills passing game value)
- `stats-collector` — recent performance, matchup grades, target share, usage rates

---

## Pipeline Steps

### Step 1 — Load Slate

Pull player pool, salaries, and game information from platform.

```python
# DraftKings: export player pool CSV from DK Lineup Tool
# FanDuel: export player pool CSV from FD Lineup Tool

# Or use unofficial APIs:
# DraftKings:
GET https://api.draftkings.com/lineups/v1/games/{contest_id}/draftables

# FanDuel:
GET https://api.fanduel.com/contests/{contest_id}/players
```

**Minimum data fields per player:**
- Name, team, position, salary, projected ownership %
- Game (home/away opponent, game time, total O/U line)
- Injury status

---

### Step 2 — Run Injury Monitor

Before projecting anyone, confirm availability via **injury-monitor**.

Remove from player pool:
- OUT designations
- DOUBTFUL (< 30% active rate historically in NFL)

Flag for manual review:
- QUESTIONABLE within 6 hours of games — do not project until confirmed active
- Limited practice participation (NFL Wed/Thu/Fri reps)

---

### Step 3 — Run DFS Projector

Invoke **dfs-projector** on the confirmed-available player pool. This is the core simulation step.

**dfs-projector** runs 10,000+ Monte Carlo simulations per player using:
- Base projection (mean fantasy points from recent form + matchup grade)
- Distribution shape (positively skewed — upside is unlimited, floor is 0)
- Positional correlations (QB + WR1 stack, SP + hitter stack in MLB)
- Weather adjustments (NFL outdoor: wind ≥ 15 mph reduces QB/WR ceilings by 15–25%)
- Snap/minutes/usage projections (confirmation from injury-monitor step)

**Output per player (projections.json):**
```json
{
  "player": "Patrick Mahomes",
  "team": "KC",
  "position": "QB",
  "platform": "DraftKings",
  "salary": 8400,
  "projection_mean": 28.4,
  "projection_median": 26.9,
  "projection_floor_p10": 14.2,
  "projection_ceiling_p90": 48.1,
  "ownership_projected": 0.24,
  "value_score": 3.38,
  "ceiling_leverage": 0.71,
  "stack_correlation": {
    "Travis Kelce": 0.62,
    "Rashee Rice": 0.58,
    "Hollywood Brown": 0.41
  }
}
```

**Value score** = `projection_mean / (salary / 1000)`. Cash game minimum: 3.0x. GPP minimum: 2.5x (lower bar trades value for upside).

---

### Step 4 — Run DFS Lineup Optimizer

Invoke **dfs-lineup-optimizer** to construct `N_LINEUPS` lineups meeting salary cap and position constraints.

**dfs-lineup-optimizer** uses integer linear programming (ILP) for cash lineups and a Monte Carlo / simulation-based heuristic for GPP:

```python
# Cash optimization: maximize expected median score
# Objective: max sum(projection_median_i * x_i)
# Constraints:
#   - Salary: sum(salary_i * x_i) <= cap
#   - Position slots filled (roster config above)
#   - Max players from single team: 8 (DK NFL), 8 (DK NBA)
#   - Injuries excluded

# GPP optimization: maximize ceiling-weighted score with ownership leverage
# Objective: max sum(projection_ceiling_weighted_i * leverage_factor_i * x_i)
# leverage_factor = 1 / sqrt(projected_ownership)
# Higher weight to low-ownership, high-upside players
```

---

### Step 5 — Correlation Stacks

For GPP lineups, force correlation stacks from the same game. Correlated players win together when a game script breaks favorably.

**NFL stack structures (DraftKings):**
- Primary stack: QB + WR1 or WR2 from same team (correlation 0.55–0.65)
- Bring-back: WR or RB from the opposing team (benefits from trailing/shooting game)
- Mini-stack: TE from primary QB's team (correlation 0.45–0.60)

**NBA stack structure (DraftKings):**
- Game stack: 3–4 players from highest projected total (fastest-paced game on slate)
- Avoid loading up one team — favor spreading across both teams in the featured game

**MLB stack structure (DraftKings):**
- 4-player minimum stack against the weakest starting pitcher on the slate
- Batting order correlation: batters in positions 1–4 correlate more strongly than 5–9

```python
# dfs-lineup-optimizer stack enforcement:
# For each lineup, require at least 1 QB+WR pair from the same team
# Optionally lock a bring-back from the opponent (game theory diversity)
# Rotate stacks across lineup set to maximize ownership differentiation
```

---

### Step 6 — Ownership Leverage

Apply ownership-based leverage to differentiate GPP lineups. Differentiation is the difference between cashing a tournament and min-cashing.

```python
# Leverage tiers:
# CONTRARIAN: ownership < 5% — high leverage, significant differentiation
# LOW-OWNED:  ownership 5–12% — good leverage
# MEDIUM:     ownership 12–25% — standard
# CHALK:      ownership 25%+ — negative leverage in large GPP fields

# For a 50-lineup set:
# - 30% of lineups: at least one CONTRARIAN play at premium position (QB or RB)
# - 70% of lineups: mix of LOW-OWNED pivots from projected chalk
# - 10% of lineups: full fade of the highest-owned player on slate
```

**Pivot logic:** Identify the highest-projected player at each position (likely chalk). For 30–40% of lineups, replace chalk with the best projection + lowest ownership alternative at that position.

---

### Step 7 — Export CSV

**dfs-lineup-optimizer** outputs a formatted CSV ready for bulk upload to DraftKings or FanDuel.

**DraftKings NFL bulk upload format:**
```csv
QB,RB,RB,WR,WR,WR,TE,FLEX,DST
Patrick Mahomes (KC),Jahmyr Gibbs (DET),Derrick Henry (BAL),...
...
```

**FanDuel NFL bulk upload format:**
```csv
QB,RB,RB,WR,WR,WR,TE,FLEX,K
...
```

```bash
# Export command
python agents/dfs/dfs_lineup_optimizer.py export \
  --projections projections.json \
  --platform draftkings \
  --sport nfl \
  --n-lineups 50 \
  --contest-type gpp \
  --output lineups_dk_nfl_2024-11-24.csv
```

---

## Lineup Set Output Summary

```
================================================================================
DFS LINEUP BUILDER — SUMMARY
================================================================================
Sport:          NFL
Platform:       DraftKings
Slate:          Main Slate — 2024-11-24
Contest Type:   GPP
Lineups Built:  50
Generated:      2024-11-24 10:15 ET

TOP PROJECTED PLAYS (by ceiling leverage score):
  QB:   Patrick Mahomes (KC)    $8,400  |  proj: 28.4 | own: 24% | value: 3.38x
  RB:   Jahmyr Gibbs (DET)      $7,800  |  proj: 24.1 | own: 18% | value: 3.09x
  WR:   Puka Nacua (LAR)        $6,200  |  proj: 19.8 | own: 8%  | value: 3.19x  [LEVERAGE]
  WR:   Travis Kelce (KC)       $6,900  |  proj: 17.2 | own: 31% | value: 2.49x  [CHALK]
  DST:  Ravens (BAL)            $3,800  |  proj: 12.1 | own: 14% | value: 3.18x

PRIMARY STACK: Mahomes + Rice + Kelce (KC) — correlation 0.61
BRING-BACK: Amon-Ra St. Brown (DET) — benefits from KC shootout game script

OWNERSHIP EXPOSURE:
  Chalk plays (>25% own):   Kelce, Mahomes used in 62% of lineups
  Leverage plays (<8% own): Puka Nacua in 28% of lineups, Gus Edwards in 18%
  Full fades:               CeeDee Lamb (38% own) in 0 lineups

OUTPUT: lineups_dk_nfl_2024-11-24.csv (50 lineups, ready for bulk upload)
================================================================================
```

---

## Constraints

- Never project a player with QUESTIONABLE status unless confirmed active within 2 hours of lock.
- GPP lineups must include at least one player with < 8% projected ownership per lineup.
- Cash lineups: do not use players with projection floors (P10) below 8 fantasy points. Cash requires floors, not ceilings.
- Recalculate projections if a significant injury or late scratch is announced after initial run — do not submit stale lineups.
- DraftKings and FanDuel bulk upload formats differ — never cross-submit. Verify platform before exporting.
- Log all submitted lineups and contest results to `~/.syndicate/dfs_log.db` for ROI tracking.
