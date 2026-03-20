# Pregame Research Workflow

Deep research workflow for a single game. Produces a comprehensive research brief covering injuries, weather, situational spots, breaking news, and model output — synthesized into a final verdict with confidence tier and CLV target.

---

## How to Run

### Claude Code (recommended)

Open Claude Code in the `the-syndicate` repo, select the **Pregame Researcher** or **Sharp Orchestrator** agent, then prompt:

```
Run the pregame research workflow for Bills at Chiefs, NFL, November 24 2024 4:25pm ET.
```

Claude Code will execute all 7 steps — pulling injury data, checking weather, analyzing the schedule spot, scanning for breaking news, collecting stats, running the market-maker model, and synthesizing a final research brief.

You can also run targeted sub-steps:
```
Run just the injury and weather checks for Bills at Chiefs.
```

### Claude Desktop

Partially supported. You can prompt Claude Desktop with game context and ask it to fill in the research brief template (copy the output template from this doc). It won't be able to call live APIs, but it can reason about matchups, situational angles, and betting strategy using its training data.

### CLI (standalone)

Individual steps use real APIs with working Python in the agent files. Key dependencies:

```bash
pip install nba_api nfl-data-py pybaseball requests
# Weather (no API key needed): Open-Meteo
# Injury data: ESPN undocumented API (no key)
# Odds: requires ODDS_API_KEY from the-odds-api.com
```

The pipeline steps reference code in `agents/research/pregame-researcher.md`, `agents/data/injury-monitor.md`, `agents/data/meteorologist.md`, etc. There is no single CLI script — the orchestration happens through Claude Code agent chaining.

---

## Sport Context

This workflow targets one specific game. Set context before running. Research depth and agent routing depend on the sport.

```
SPORT:      [NFL | NBA | MLB | NHL | NCAAF | NCAAB]
HOME_TEAM:  [team abbreviation]
AWAY_TEAM:  [team abbreviation]
GAME_TIME:  [YYYY-MM-DD HH:MM ET]
GAME_ID:    [internal ID, e.g. nfl_2024_wk12_buf_at_kc]
```

Example:
```
SPORT:      NFL
HOME_TEAM:  KC
AWAY_TEAM:  BUF
GAME_TIME:  2024-11-24 16:25 ET
GAME_ID:    nfl_2024_wk12_buf_at_kc
```

---

## Agents Involved

| Agent | Role | Invoked For |
|-------|------|-------------|
| `injury-monitor` | Official injury designations + beat reporter updates | All sports |
| `meteorologist` | Game-time weather forecast at venue | NFL, MLB, NCAAF outdoor only |
| `situational-analyst` | Rest, travel, schedule spots, divisional/revenge angles | All sports |
| `the-insider` | Breaking news, locker room intel, coaching changes | All sports |
| `stats-collector` | Recent form, ATS/O-U splits, efficiency metrics | All sports |
| `market-maker` | Independent fair-value spread, total, moneyline | All sports |

---

## Pipeline Steps

### Step 1 — Injury Monitor

Invoke **injury-monitor** for both teams. This step runs first because injury status is the most time-sensitive input and the most common reason to abort a bet.

**injury-monitor** pulls from:
- Official league injury report (NFL: Wednesday/Thursday/Friday designations)
- ESPN injury API (`site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams/{team}/injuries`)
- Rotowire live updates
- Beat reporter cross-check (Twitter/X search for team beat reporters)

**Injury impact tiers:**

| Tier | Player Type | Impact |
|------|-------------|--------|
| CRITICAL | Starting QB (NFL), franchise player (NBA: 30+ min/g) | Revisit model entirely |
| HIGH | WR1/RB1/TE1 (NFL), starting PG/SF (NBA) | Adjust model -1.5 to -3 pts |
| MODERATE | OL starter (NFL), key defender | Adjust model -0.5 to -1.5 pts |
| LOW | Backup, special teams | Note only, no model adjustment |

**Gate:** If CRITICAL injury is reported with no resolution within 90 minutes of game time, downgrade confidence to C or PASS.

---

### Step 2 — Meteorologist (outdoor sports only)

**Skip for:** NBA, NHL, indoor arenas, dome stadiums.

Invoke **meteorologist** for NFL outdoor venues, MLB (all parks), NCAAF outdoor.

**meteorologist** pulls from Open-Meteo API (free, no key):
```
GET https://api.open-meteo.com/v1/forecast
    ?latitude={LAT}&longitude={LON}
    &hourly=temperature_2m,precipitation_probability,windspeed_10m,winddirection_10m
    &temperature_unit=fahrenheit&windspeed_unit=mph
```

**Weather betting impact thresholds:**

| Condition | Threshold | O/U Impact | Spread Impact |
|-----------|-----------|------------|---------------|
| Wind | 15–24 mph | Lean under 0.5–1.5 pts | Minimal |
| Wind | 25+ mph | Strong under, 2–3 pts | Favors run game (+ground team) |
| Temperature | ≤ 20°F | Slight under lean | Favors home team familiarity |
| Precipitation | ≥ 40% chance | Moderate under lean | Toss-up |
| Precipitation | ≥ 70% chance | Strong under 1–2 pts | Slight home lean |

---

### Step 3 — Situational Analyst

Invoke **situational-analyst** to identify schedule spots and motivational edges. These are the factors books price last and the public ignores most.

**situational-analyst** checks (sport-specific):

**NFL:**
- Rest days: short week (≤4 days), bye advantage (14 days), off-bye opponent
- Travel: time zone crossings, coast-to-coast road trip
- Divisional game: tighter spreads historically, higher variance
- Primetime: road teams cover at lower rate, top teams underperform vs. number
- Revenge spot: team facing former head coach, former franchise QB
- Look-ahead: game sandwiched between two marquee opponents
- Desperation: must-win for playoff positioning (cover rate +5% historically)

**NBA:**
- Back-to-back: second night of B2B — dogs cover at elevated rate vs. rested opponent
- 3-in-4: fatigue spot, especially road
- Rest differential: 3+ days rest vs. 1 day rest = 2–3 point model adjustment

**MLB:**
- Starting pitcher on short rest (< 4 days) → downgrade SP confidence
- Travel: east-to-west late arrival (affects first-inning scoring)
- Getaway day game: day game following night game (fatigue)

---

### Step 4 — The Insider

Invoke **the-insider** to surface breaking news not yet captured in official reports or pricing. This agent scans:
- Beat reporter feeds (Twitter/X)
- Injury report updates within 24 hours of game time
- Practice participation reports (full, limited, non-participant)
- Coaching changes, coordinator adjustments
- Motivational intel: player controversies, trade rumors, contract disputes
- Any news the line hasn't priced yet

**Output:** A timestamped news log for the game, flagged by potential betting relevance (HIGH / MEDIUM / LOW).

**Important:** The Insider output is the most perishable data in the pipeline. Run this step last among the data-gathering steps, as close to game time as operationally feasible, and re-run 30 minutes before kickoff/tip.

---

### Step 5 — Stats Collector

Invoke **stats-collector** to pull structured statistical data for both teams.

**stats-collector** targets (sport-specific):

**NFL stats pulled:**
- Season ATS record: overall, home, away, favorite, dog
- O/U record: overall, home, away, in outdoor games
- Efficiency: EPA/play offense/defense, DVOA, yards per play
- Recent form: ATS last 5 games
- H2H: ATS record last 5 meetings, O/U last 5 meetings
- Situational splits matching the spot (e.g., home as 3–7 point favorite)

**NBA stats pulled:**
- ATS record: overall, home, away, off rest, on B2B
- Pace: possessions per 48 minutes (both teams)
- Offensive/defensive efficiency ratings
- H2H last 5, ATS last 5

**MLB stats pulled:**
- Team ERA vs. lineup handedness splits
- Bullpen availability (days of rest for key arms)
- Recent batting performance: last 10 games runs scored/allowed
- Starting pitcher: recent ERA, WHIP, pitch count limits

---

### Step 6 — Market Maker

Invoke **market-maker** to produce an independent fair-value number using research brief inputs.

Inject the following from prior steps into **market-maker**'s inputs:
- Injury adjustments from Step 1 (point value per position)
- Weather adjustments from Step 2 (total impact in points)
- Rest differential from Step 3

**market-maker** outputs:
- Fair spread (home team perspective)
- Fair total
- No-vig moneylines
- Implied win probability each side
- Edge vs. current market line (if provided)

---

### Step 7 — Synthesis

Combine all agent outputs into the final research brief. Apply the confidence framework:

| Grade | Criteria | Unit Sizing |
|-------|----------|-------------|
| A | 3+ independent signals converging, edge ≥ 5%, no conflicting data | 1.5–2 units |
| B | 2 strong signals, edge 3–5%, 1 minor conflict acceptable | 1 unit |
| C | 1 clear signal, edge 3–4%, 1–2 concerns but not disqualifying | 0.5 units |
| PASS | Edge < 3%, conflicting signals, key injury unresolved, or no thesis | 0 |

---

## Research Brief Output Template

```
================================================================================
PREGAME RESEARCH BRIEF
================================================================================
Sport:        [NFL / NBA / MLB / NHL]
Game:         [Away] @ [Home]
Date/Time:    [Day, Month DD YYYY — HH:MM ET]
Generated:    [YYYY-MM-DD HH:MM:SS]
Analyst:      pregame-researcher + [agents invoked]

--- INJURY REPORT ---
[AWAY TEAM]
  [Player] | [Pos] | [Status: OUT/DOUBTFUL/QUESTIONABLE/PROBABLE] | [Description]
  [Player] | [Pos] | [Status] | [Description]

[HOME TEAM]
  [Player] | [Pos] | [Status] | [Description]

Injury Impact:  [CRITICAL / HIGH / MODERATE / NONE] — [1-line summary]
Source:         [Official report + beat reporter, confirmed HH:MM ET]

--- WEATHER (outdoor only) ---
Venue:          [Stadium name, City]
Temperature:    [XX°F]
Wind:           [XX mph, direction]
Precipitation:  [XX% chance]
O/U Impact:     [SEVERE / MODERATE / MINIMAL]
Notes:          [Any specific wind direction concern re: open end zone, etc.]

--- SITUATIONAL ANGLES ---
Rest:
  [Away team]:  [X days rest | off bye | short week | B2B]
  [Home team]:  [X days rest | off bye | short week | B2B]
  Rest Edge:    [Team] has [X]-day advantage — model adjustment: [+/- X.X pts]

Schedule Spot:
  [ ] Short week
  [ ] Off-bye advantage
  [ ] Divisional game
  [ ] Primetime spot
  [ ] Look-ahead game
  [ ] Revenge spot: [detail]
  [ ] Desperation spot: [detail]

--- BREAKING NEWS (The Insider) ---
[Timestamp] [Team] [News item — relevance: HIGH/MEDIUM/LOW]
[Timestamp] [Team] [News item — relevance: HIGH/MEDIUM/LOW]

--- KEY STATS & TRENDS ---
ATS Records:
  [Away] overall:         [W-L ATS]   | Last 5: [W-L]   | Road: [W-L]
  [Home] overall:         [W-L ATS]   | Last 5: [W-L]   | Home: [W-L]
  H2H last 5:             [W-L ATS, from Away perspective]
  Situational split:      [Away as X-point dog road: W-L ATS]

O/U Records:
  [Away] last 10:         [O-U]
  [Home] last 10:         [O-U]
  H2H last 5:             [O-U]
  In weather conditions:  [O-U in wind > 15mph / outdoor cold games]

--- LINE DATA ---
Opening:        [Home] [spread]  |  Total: [X]
Current:        [Home] [spread]  |  Total: [X]
Movement:       [+/- X pts on spread | +/- X on total]
Sharp Signal:   [RLM / STEAM / NONE] — [description]
Public:         [XX%] bets on [Team] | [XX%] money on [Team]

--- MARKET MAKER MODEL ---
Fair Spread:    [Home] [±X.X]   (market: [±X.X] | diff: [±X.X pts])
Fair Total:     [X.X]           (market: [X.X] | diff: [±X.X pts])
Win Prob:       [Away] [XX%]  /  [Home] [XX%]
Prob Edge:      [Team]: [+X.X%] edge vs. market implied prob

--- FINAL VERDICT ---
Primary Bet:    [Team | Side] [Spread/ML/Total] @ [line] at [Book]
Confidence:     [A / B / C / PASS]
CLV Target:     Close at [X] or better vs. current [X]
Unit Sizing:    [X.X] units / $[XX.XX]

Rationale:
  [Primary edge driver — 1 sentence]
  [Supporting signal — 1 sentence]
  [Key risk to thesis — 1 sentence]
================================================================================
```

---

## Timing Requirements

| Step | Deadline Before Game |
|------|----------------------|
| Full brief issued | 3 hours |
| Injury re-check (The Insider) | 30 minutes |
| Line re-check | 15 minutes |
| Bet placed | Before line moves materially |

---

## Constraints

- Do not issue a brief graded above C without data from at least Steps 1, 5, and 6.
- Weather step is mandatory for all NFL outdoor games and all MLB games — no exceptions.
- If The Insider reports a CRITICAL news item after the brief is issued, re-run the full pipeline. Do not patch a stale brief.
- Stats Collector sample size minimum: 10 games for ATS/O-U trends. Do not cite trends with fewer samples.
- If market-maker fair spread disagrees with current market by ≤ 0.5 points, there is no edge — do not force a bet.
