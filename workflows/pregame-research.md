# Pregame Research Workflow

> **Hybrid pipeline:** Claude Code auto-chains agents and surfaces checkpoints
> between steps. Deep research for a single game — produces a comprehensive
> brief with confidence tier and bet recommendation.

## How to Run

Activate the **Sharp Orchestrator** agent in Claude Code and prompt:

    Run the pregame research workflow for [AWAY] at [HOME], [SPORT], [DATE TIME].

For targeted sub-steps:

    Run just the injury and weather checks for Bills at Chiefs.

The orchestrator reads this workflow and executes each step.

## Inputs

- `{sport}` — Sport key (e.g., `NFL`, `NBA`, `MLB`, `NHL`, `NCAAF`, `NCAAB`)
- `{away_team}` — Away team name or abbreviation
- `{home_team}` — Home team name or abbreviation
- `{game_time}` — Game date and time (e.g., `2026-03-19 16:25 ET`)

## Agents Involved

| Step | Agent | Role |
|------|-------|------|
| 1 | Injury Monitor | Official designations + beat reporter updates |
| 2 | Meteorologist | Weather forecast (outdoor sports only) |
| 3 | Situational Analyst | Rest, travel, schedule spots, angles |
| 4 | The Insider | Breaking news, locker room intel |
| 5 | Stats Collector | ATS/O-U records, efficiency, H2H |
| 6 | Market Maker | Independent fair-value spread, total, ML |
| 7 | (orchestrator) | Synthesis into research brief |

---

## Step 1 — Injury Monitor (parallel with Steps 2-5)

**Agent:** Injury Monitor
**Depends on:** none
**Dispatch mode:** background (parallel with Steps 2-5)

**Purpose:** Pull official injury designations and beat reporter updates for both teams.

**Dispatch prompt:**
> Activate Injury Monitor. Pull the current injury report for
> {away_team} vs {home_team}. Sport: {sport}. Check official league
> injury reports, ESPN injury API, Rotowire live updates, and beat
> reporter cross-checks. For each injured player, report: name,
> position, status (OUT/DOUBTFUL/QUESTIONABLE/PROBABLE), description,
> and impact tier (CRITICAL/HIGH/MODERATE/LOW). CRITICAL = starting QB
> or franchise player (30+ min/g). HIGH = WR1/RB1/TE1 or starting
> PG/SF. MODERATE = OL starter or key defender. LOW = backup or
> special teams. If a CRITICAL injury is unresolved within 90 minutes
> of game time, flag for confidence downgrade.

**Expected output:** Injury report for both teams with impact tiers and point adjustments.

**Checkpoint:**

    Injuries: [away_team] N players listed | [home_team] N players listed
    Impact: [CRITICAL/HIGH/MODERATE/NONE] — [summary]
    Gate: [CLEAR / CRITICAL INJURY — confidence capped at C]
    Proceed? (yes / re-check [team] / halt)

---

## Step 2 — Meteorologist (parallel with Steps 1, 3-5)

**Agent:** Meteorologist
**Depends on:** none
**Dispatch mode:** background (parallel with Steps 1, 3-5)
**Skip for:** NBA, NHL, indoor arenas, dome stadiums

**Purpose:** Forecast game-time weather and quantify impact on scoring.

**Dispatch prompt:**
> Activate Meteorologist. Pull the weather forecast for {away_team}
> vs {home_team} at game time {game_time}. Sport: {sport}. Use the
> Open-Meteo API (free, no key needed) with the venue's GPS
> coordinates. Report: temperature, wind speed + direction,
> precipitation probability. Quantify impact on total (O/U) and
> spread using these thresholds: wind 15-24 mph = lean under 0.5-1.5
> pts; wind 25+ mph = strong under 2-3 pts + favors run game;
> temp <= 20F = slight under + favors home; precip >= 40% = moderate
> under; precip >= 70% = strong under 1-2 pts + slight home lean.
> Note any venue-specific concerns (open end zones, altitude).

**Expected output:** Weather forecast with quantified O/U and spread impact in points.

**Checkpoint:**

    Weather at [venue]: [temp]F, wind [speed] mph [dir], precip [pct]%
    O/U impact: [SEVERE/MODERATE/MINIMAL] — [+/- X pts]
    Spread impact: [description]
    Proceed? (yes / skip / halt)

---

## Step 3 — Situational Analyst (parallel with Steps 1-2, 4-5)

**Agent:** Situational Analyst
**Depends on:** none
**Dispatch mode:** background (parallel with Steps 1-2, 4-5)

**Purpose:** Identify schedule spots, rest edges, and motivational factors.

**Dispatch prompt:**
> Activate Situational Analyst. Analyze the situational context for
> {away_team} vs {home_team} on {game_time}. Sport: {sport}. Check:
> rest days for both teams, travel (time zones, coast-to-coast),
> schedule spot (short week, off-bye, look-ahead, letdown,
> sandwich), divisional rivalry, primetime factors, revenge spots
> (former coach/QB), and desperation (playoff positioning). For NBA,
> specifically check back-to-back and 3-in-4 fatigue. For MLB,
> check SP rest days and getaway day. Output a rest edge in points,
> schedule spot flags, and any motivational angles with historical
> cover rate impact.

**Expected output:** Rest differential, schedule spot flags, motivational angles with point adjustments.

**Checkpoint:**

    Rest edge: [team] +[X] days — model adjustment [+/- X.X pts]
    Schedule spots: [list of flags]
    Motivation: [angles identified or "none"]
    Proceed? (yes / deep dive / halt)

---

## Step 4 — The Insider (parallel with Steps 1-3, 5)

**Agent:** The Insider
**Depends on:** none
**Dispatch mode:** background (parallel with Steps 1-3, 5)

**Purpose:** Surface breaking news not yet captured in official reports or pricing.

**Dispatch prompt:**
> Activate The Insider. Scan for breaking news on {away_team} vs
> {home_team}. Sport: {sport}. Game time: {game_time}. Check beat
> reporter feeds, practice participation reports, coaching changes,
> coordinator adjustments, player controversies, trade rumors, and
> contract disputes. Flag each item by betting relevance:
> HIGH (likely moves the line), MEDIUM (could affect game flow),
> LOW (background context). Timestamp each item. This data is highly
> perishable — note the scan time. If a HIGH-relevance item is found
> after the brief is issued, the full pipeline should be re-run.

**Expected output:** Timestamped news log flagged by relevance tier.

**Checkpoint:**

    News scan: N items found | HIGH: N | MEDIUM: N | LOW: N
    Top item: [timestamp] [summary] — relevance: [tier]
    Proceed? (yes / re-scan / halt)

---

## Step 5 — Stats Collector (parallel with Steps 1-4)

**Agent:** Stats Collector
**Depends on:** none
**Dispatch mode:** background (parallel with Steps 1-4)

**Purpose:** Pull structured statistical data for both teams.

**Dispatch prompt:**
> Activate Stats Collector. Pull stats for {away_team} vs
> {home_team}. Sport: {sport}. Collect: season ATS record (overall,
> home, away, as favorite, as dog), O/U record (overall, home, away),
> last 5 games ATS and O/U, H2H last 5 meetings (ATS and O/U),
> efficiency metrics (NFL: EPA/play, DVOA; NBA: offensive/defensive
> rating, pace; MLB: team ERA, bullpen availability), and situational
> splits matching this specific spot. Minimum 10-game sample for any
> trend cited. Output structured data, not narrative.

**Expected output:** Structured stats with ATS/O-U records, efficiency metrics, H2H, and situational splits.

**Checkpoint:**

    Stats pulled for both teams | ATS: [away] [W-L] / [home] [W-L]
    H2H last 5: [W-L ATS] | O/U last 5: [O-U]
    Key trend: [top finding]
    Proceed? (yes / pull more / halt)

---

## Step 6 — Market Maker

**Agent:** Market Maker
**Depends on:** Steps 1-5 (all data-gathering steps)
**Dispatch mode:** foreground

**Purpose:** Build independent fair-value lines using all research inputs.

**Dispatch prompt:**
> Activate Market Maker. Build an independent fair-value line for
> {away_team} vs {home_team}. Sport: {sport}. Inject these upstream
> inputs: injury adjustments from Step 1: {injury_output}. Weather
> impact from Step 2: {weather_output}. Rest differential from
> Step 3: {situational_output}. Use power ratings and the situational
> adjustments to produce: fair-value spread (home perspective),
> fair-value total, no-vig moneylines, and implied win probability
> for each side. Then compare against the current market line and
> output edge % on spread, total, and moneyline. If fair spread
> disagrees with market by <= 0.5 points, report "no edge."

**Expected output:** Fair spread, total, MLs, win probs, and edge vs market.

**Checkpoint:**

    Fair spread: [home] [+/- X.X] | Market: [+/- X.X] | Diff: [+/- X.X pts]
    Fair total: [X.X] | Market: [X.X] | Diff: [+/- X.X pts]
    Edge: [+X.X%] on [side] or "no edge"
    Proceed to synthesis? (yes / re-run with adjustments / halt)

---

## Step 7 — Synthesis (no agent dispatch)

**Depends on:** All previous steps

**Purpose:** Combine all agent outputs into the final research brief with confidence tier.

**Action:** Apply the confidence framework below. Combine outputs from all steps into the Research Brief Output Template. Include: injury report, weather, situational angles, breaking news, key stats, line data, Market Maker model output, and final verdict with confidence tier and unit sizing.

### Confidence Framework

| Grade | Criteria | Unit Sizing |
|-------|----------|-------------|
| A | 3+ independent signals converging, edge >= 5%, no conflicting data | 1.5-2 units |
| B | 2 strong signals, edge 3-5%, 1 minor conflict acceptable | 1 unit |
| C | 1 clear signal, edge 3-4%, 1-2 concerns but not disqualifying | 0.5 units |
| PASS | Edge < 3%, conflicting signals, key injury unresolved, or no thesis | 0 |

**Checkpoint:**

    Research brief complete for [away] at [home]
    Confidence: [A/B/C/PASS] | Edge: [X.X%] | Side: [recommendation]
    Units: [X.X] | CLV target: [X]
    Accept brief? (yes / re-run [step] / halt)

---

## Research Brief Output Template

```
================================================================================
PREGAME RESEARCH BRIEF
================================================================================
Sport:        [NFL / NBA / MLB / NHL]
Game:         [Away] @ [Home]
Date/Time:    [Day, Month DD YYYY -- HH:MM ET]
Generated:    [YYYY-MM-DD HH:MM:SS]
Analyst:      pregame-researcher + [agents invoked]

--- INJURY REPORT ---
[AWAY TEAM]
  [Player] | [Pos] | [Status: OUT/DOUBTFUL/QUESTIONABLE/PROBABLE] | [Description]

[HOME TEAM]
  [Player] | [Pos] | [Status] | [Description]

Injury Impact:  [CRITICAL / HIGH / MODERATE / NONE] -- [1-line summary]
Source:         [Official report + beat reporter, confirmed HH:MM ET]

--- WEATHER (outdoor only) ---
Venue:          [Stadium name, City]
Temperature:    [XX F]
Wind:           [XX mph, direction]
Precipitation:  [XX% chance]
O/U Impact:     [SEVERE / MODERATE / MINIMAL]
Notes:          [Any specific wind direction concern re: open end zone, etc.]

--- SITUATIONAL ANGLES ---
Rest:
  [Away team]:  [X days rest | off bye | short week | B2B]
  [Home team]:  [X days rest | off bye | short week | B2B]
  Rest Edge:    [Team] has [X]-day advantage -- model adjustment: [+/- X.X pts]

Schedule Spot:
  [ ] Short week
  [ ] Off-bye advantage
  [ ] Divisional game
  [ ] Primetime spot
  [ ] Look-ahead game
  [ ] Revenge spot: [detail]
  [ ] Desperation spot: [detail]

--- BREAKING NEWS (The Insider) ---
[Timestamp] [Team] [News item -- relevance: HIGH/MEDIUM/LOW]

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

--- LINE DATA ---
Opening:        [Home] [spread]  |  Total: [X]
Current:        [Home] [spread]  |  Total: [X]
Movement:       [+/- X pts on spread | +/- X on total]
Sharp Signal:   [RLM / STEAM / NONE] -- [description]
Public:         [XX%] bets on [Team] | [XX%] money on [Team]

--- MARKET MAKER MODEL ---
Fair Spread:    [Home] [+/- X.X]   (market: [+/- X.X] | diff: [+/- X.X pts])
Fair Total:     [X.X]           (market: [X.X] | diff: [+/- X.X pts])
Win Prob:       [Away] [XX%]  /  [Home] [XX%]
Prob Edge:      [Team]: [+X.X%] edge vs. market implied prob

--- FINAL VERDICT ---
Primary Bet:    [Team | Side] [Spread/ML/Total] @ [line] at [Book]
Confidence:     [A / B / C / PASS]
CLV Target:     Close at [X] or better vs. current [X]
Unit Sizing:    [X.X] units / $[XX.XX]

Rationale:
  [Primary edge driver -- 1 sentence]
  [Supporting signal -- 1 sentence]
  [Key risk to thesis -- 1 sentence]
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

## Intervention Commands

Available at any checkpoint:

| Command | Effect |
|---------|--------|
| `yes` / Enter | Proceed to next step |
| `halt` | Stop the pipeline |
| `skip [step]` | Skip a step (e.g., skip weather for indoor game) |
| `re-run [step]` | Re-run a specific step with fresh data |
| `deep dive` | Run additional analysis on current step |

---

## Decision Rules

- **No brief above C without Steps 1, 5, and 6.** Injury data, stats, and model output are mandatory.
- **Weather mandatory for NFL outdoor and all MLB.** No exceptions.
- **CRITICAL injury unresolved = confidence capped at C or PASS.** Do not issue an A or B brief with an unresolved franchise-player injury.
- **0.5-point spread agreement = no edge.** If Market Maker and market agree within 0.5 points, there is no actionable edge.
- **10-game sample minimum.** Do not cite ATS/O-U trends with fewer than 10 games.
- **Re-run on CRITICAL news.** If The Insider reports a HIGH-relevance item after the brief is issued, re-run the full pipeline.
- **Steps 1-5 run in parallel.** They are independent data-gathering steps with no dependencies on each other. Step 6 depends on all of them.

---

## Constraints & Disclaimers

This system is for **educational and research purposes only**. Output is based on mathematical models and historical data. It is not a guarantee of profit and should not be construed as financial or gambling advice.

- Sports betting involves substantial risk of loss.
- No model eliminates variance.
- Bet only what you can afford to lose entirely.
- **Problem gambling resources:** 1-800-522-4700 | ncpgambling.org
