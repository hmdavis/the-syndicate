# Daily Picks Workflow

Full pipeline: research → model → line comparison → sizing → pick report. Run once per day, 3–4 hours before the first game of the slate.

---

## How to Run

This is a **Claude Code workflow**. You run it by starting Claude Code and prompting it with the Sharp Orchestrator agent.

### Claude Code (recommended)

Open Claude Code in the `the-syndicate` repo and select the **Sharp Orchestrator** agent, then prompt:

```
Run the daily picks workflow for NFL, Sunday November 24 2024.
```

Claude Code will execute each pipeline step — invoking the relevant agents, writing intermediate outputs, and producing the final pick report. You can also run individual steps:

```
Run Step 3 of the daily picks workflow for Bills at Chiefs.
```

### Claude Desktop

Not directly supported. Claude Desktop does not have filesystem access or the ability to execute code. Use these workflow docs as reference to structure your own prompts — copy the output templates and ask Claude to fill them in with data you provide.

### CLI (standalone)

The workflow references Python code blocks throughout. To run steps independently outside Claude Code:

```bash
# Install dependencies
pip install nba_api nfl-data-py pybaseball requests pandas

# Set your Odds API key
export ODDS_API_KEY=your_key_here

# Individual steps use code blocks from this doc and the agent files.
# There is no single `run_daily_picks.py` script — the orchestration
# happens through Claude Code agent chaining.
```

To record picks after the workflow completes:
```bash
./scripts/bet.sh place
```

---

## Sport Context

**Set your sport before running.** This workflow operates within a single sport per session. Do not mix sports in one pipeline run — each sport has distinct data sources, key numbers, and model parameters.

```
SPORT: [NFL | NBA | MLB | NHL | NCAAF | NCAAB]
SLATE_DATE: [YYYY-MM-DD]
BANKROLL_DB: ~/.syndicate/bankroll.db
```

---

## Agents Involved

| Agent | Role | Output |
|-------|------|--------|
| `pregame-researcher` | Injuries, line movement, situational data per game | Research brief per game |
| `market-maker` | Independent fair-value spread, total, and moneyline | `fair_values.json` |
| `elo-modeler` | Elo-based win probability, margin estimate | `elo_estimates.json` |
| `line-shopper` | Best available price across 10+ books | `best_lines.json` |
| `kelly-criterion` | Fractional Kelly stake sizing from bankroll | `picks.json` |

---

## Pipeline Steps

### Step 1 — Load Bankroll State

Read current bankroll from `~/.syndicate/bankroll.db` before sizing anything. All unit calculations are anchored to this state.

```bash
sqlite3 ~/.syndicate/bankroll.db \
  "SELECT current_bankroll, peak_bankroll, unit_size, drawdown_pct FROM bankroll_state LIMIT 1;"
```

**Gate check:** If `drawdown_pct >= 20`, do not run the pipeline. Output:
```
PIPELINE PAUSED: 20%+ drawdown protection active.
Current: $X,XXX | Peak: $X,XXX | Drawdown: XX.X%
No new picks until drawdown recovers to < 15%.
```

---

### Step 2 — Load Today's Slate

Fetch the game schedule for the sport and date. Filter to games starting within 24 hours.

```python
# For NFL — nfl_data_py
import nfl_data_py as nfl
schedule = nfl.import_schedules([2024])
todays_games = schedule[schedule["gameday"] == SLATE_DATE]

# For NBA — nba_api
from nba_api.stats.endpoints import ScoreboardV2
scoreboard = ScoreboardV2(game_date=SLATE_DATE)
```

---

### Step 3 — Run Pregame Researcher (per game)

Invoke **pregame-researcher** on each game. Each brief must complete before model inputs are assembled. Briefs run in parallel — one per game, not sequentially.

**Inputs per game:**
- Home/away team
- Kickoff/tip time
- Sport key

**Outputs per game:**
- Injury report (both sides)
- Line movement summary (open → current, +movement)
- Public betting percentages (bets %, money %)
- Sharp signals (steam, RLM flags)
- Weather block (NFL/MLB outdoor only)
- Rest/schedule spot analysis
- Situational angles (divisional, primetime, revenge, look-ahead)

Store briefs as `research/[away]_at_[home].md`.

---

### Step 4 — Run Market Maker + Elo Modeler (per game)

Invoke **market-maker** and **elo-modeler** independently. Each produces a fair-value number from different methodologies. Cross-reference outputs — agreement increases confidence.

**market-maker inputs:** Power ratings, home field, rest differential, pace/tempo, injury-adjusted efficiency
**elo-modeler inputs:** Current Elo ratings, home field factor, rest multiplier

Both agents output to `models/[game_id]_fair_value.json`:

```json
{
  "game_id": "nfl_2024_wk12_buf_at_kc",
  "sport": "NFL",
  "home_team": "KC",
  "away_team": "BUF",
  "market_maker": {
    "fair_spread": -6.5,
    "fair_total": 48.5,
    "home_win_prob": 0.648,
    "away_win_prob": 0.352
  },
  "elo_model": {
    "fair_spread": -7.0,
    "home_win_prob": 0.661
  },
  "consensus_spread": -6.75,
  "consensus_win_prob": 0.655
}
```

---

### Step 5 — Line Shopping

Invoke **line-shopper** to pull current best prices across all available books. Compare each model fair value against the best available market line.

```python
# line-shopper pulls from The Odds API
# markets: spreads, h2h (moneyline), totals
# regions: us
# Compare model number vs. best available price
```

**Edge calculation:**
```
spread_edge = model_fair_spread - best_market_spread
prob_edge   = model_win_prob - market_implied_prob (no-vig)
```

**Bet threshold:** Edge ≥ 3% on probability OR ≥ 1.5 points on spread to qualify for sizing.

---

### Step 6 — Kelly Sizing

Pass all qualifying edges to **kelly-criterion** for fractional Kelly sizing against current bankroll.

```bash
python agents/bankroll/kelly_criterion.py size \
  --edges models/today_edges.json \
  --output picks/today_picks.json \
  --bankroll ~/.syndicate/bankroll.db
```

Kelly config defaults:
- Kelly fraction: 0.25 (quarter Kelly)
- Min edge: 3%
- Max single bet: 3 units
- Max portfolio exposure: 10 units

---

### Step 7 — Generate Pick Report

Compile all outputs into a structured pick report. Format defined below.

---

## Pick Report Output Template

```
================================================================================
THE SYNDICATE — DAILY PICKS
================================================================================
Sport:          [NFL / NBA / MLB / NHL]
Slate Date:     [YYYY-MM-DD]
Games on Card:  [N]
Generated:      [YYYY-MM-DD HH:MM ET]

BANKROLL STATUS
  Current:      $[X,XXX.XX]
  Peak:         $[X,XXX.XX]
  Drawdown:     [X.X%]
  Unit Size:    $[XX.XX]  (1% of starting bankroll)
  Open Units:   [X.X]u

================================================================================
PICKS ([N] plays, [X.X] total units)
================================================================================

PICK #1
  Game:         [Away] @ [Home]  |  [Day, Date, Time ET]
  Bet:          [Team] [Spread/ML/Total] @ [Book]
  Market Line:  [Odds]
  Fair Value:   [Model spread/prob]  (Market Maker: [X.X] | Elo: [X.X])
  Edge:         [+X.X%] probability / [+X.X pts] on spread
  CLV Target:   Beat closing line by [X] points / [X]%
  Kelly:        Full [X.Xu] → Quarter Kelly [X.Xu]
  Stake:        [X.X] units / $[XX.XX]
  Confidence:   [A / B / C]

  Key Signals:
    - [Injury/situational/weather/sharp signal — 1 line each]
    - [...]

  Rationale:
    [2-3 sentences: primary edge, supporting factors, key risk]

--------------------------------------------------------------------------------

[PICK #2, #3, #4 — same format]

================================================================================
PASSES ([N] games reviewed, no edge)
================================================================================
  [Away] @ [Home]  — [1-line reason: e.g. "edge 1.8%, below 3% floor"]
  [...]

================================================================================
PIPELINE NOTES
================================================================================
  [Any data quality issues, late scratches to monitor, line move alerts]
================================================================================
```

---

## Constraints

- Never issue picks without completing Steps 1–5. Partial pipelines produce noise.
- CLV target is mandatory — it is the only post-game accountability metric that matters.
- Re-run **pregame-researcher** for any game with a key player listed questionable within 2 hours of kickoff.
- If market-maker and elo-modeler disagree by more than 2 points, flag as "model conflict" and downgrade confidence one tier.
- Log all picks to `~/.syndicate/bet_log.db` immediately on report generation — before placement.
