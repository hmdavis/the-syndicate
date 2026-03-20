# Daily Picks Workflow

> **Hybrid pipeline:** Claude Code auto-chains agents and surfaces checkpoints
> between steps. Say "yes" to proceed, or intervene with the listed commands.

## How to Run

Activate the **Sharp Orchestrator** agent in Claude Code and prompt:

    Run the daily picks workflow for [SPORT] on [DATE].

The orchestrator reads this workflow and executes each step.

## Inputs

- `{sport}` — The Odds API sport key (e.g., `basketball_ncaab`, `americanfootball_nfl`)
- `{date}` — Slate date (YYYY-MM-DD)

## Agents Involved

| Step | Agent | Role |
|------|-------|------|
| 1 | State Manager | Bankroll gate check |
| 1.5 | (orchestrator) | Game list lookup |
| 2 | Odds Scraper | Pull live lines |
| 3 | Pregame Researcher | Per-game research briefs |
| 4a | Market Maker | Independent fair values |
| 4b | Elo Modeler | Elo-based validation |
| 5 | Line Shopper | Best number across books |
| 6 | Kelly Criterion Manager | Fractional Kelly sizing |
| 7 | (orchestrator) | Betslip synthesis |
| 8 | State Manager | Record bets (optional) |

---

## Step 1 — State Manager (gate)

**Agent:** State Manager
**Depends on:** none
**Dispatch mode:** foreground

**Purpose:** Verify bankroll is healthy before running the pipeline.

**Dispatch prompt:**
> Activate State Manager. Read the current bankroll state from
> ~/.syndicate/bankroll.db. The bankroll_state table has columns:
> current_balance, starting_balance, risk_tolerance, created_at,
> updated_at. Compute P&L as (current_balance - starting_balance).
> Compute drawdown percentage as ((starting_balance -
> current_balance) / starting_balance * 100) — if current_balance >
> starting_balance, drawdown is 0%. Check sports_config to confirm
> {sport} is enabled. Report: current balance, starting balance,
> computed P&L, computed drawdown %, risk tolerance, and sport
> status. If drawdown exceeds 20%, output HALT with the reason. No
> new picks until drawdown recovers to < 15%. Otherwise output CLEAR
> with the bankroll summary.

**Expected output:** Bankroll balance, computed P&L, computed drawdown %, CLEAR/HALT status, sport config.

**Checkpoint:**

    Bankroll: $X | P&L: $X | Drawdown: X% | Status: CLEAR/HALT | Sport: {sport} enabled
    Proceed? (yes / halt)

---

## Step 1.5 — Game List Lookup (no agent dispatch)

**Depends on:** Step 1 CLEAR

**Purpose:** Fetch the day's game list so Steps 2 and 3 can run in parallel.

The orchestrator queries The Odds API directly for {sport} on {date} to get matchups and commence times. Only the game list is needed — full odds come in Step 2.

**Action:**

    curl -s "https://api.the-odds-api.com/v4/sports/{sport}/odds?apiKey=$ODDS_API_KEY&regions=us&dateFormat=iso" \
      | python3 -c "import sys,json; games=json.load(sys.stdin); [print(f\"{g['away_team']} vs {g['home_team']} | {g['commence_time']}\") for g in games]"

**Output:** `{game_list}` — list of matchups with tip times.

**Checkpoint:**

    Found N games for {sport} on {date}:
    - Away vs Home | tip time
    Proceed? (yes / drop [game])

---

## Step 2 — Odds Scraper (parallel with Step 3)

**Agent:** Odds Scraper
**Depends on:** Step 1 CLEAR + game list from Step 1.5
**Dispatch mode:** background (parallel with Step 3)

**Purpose:** Pull structured odds from every available book.

**Dispatch prompt:**
> Activate Odds Scraper. Pull current odds for these {sport} games on
> {date}: {game_list}. Use the `ODDS_API_KEY` environment variable
> (as defined in CLAUDE.md and .env.example). Markets: h2h, spreads,
> totals. Region: us. Return a structured table per game showing:
> matchup, spread (home perspective), total, and moneyline for each
> available book. Include the odds timestamp for each game. Flag any
> games with fewer than 3 books pricing them as "thin market" — this
> flag will propagate to downstream sizing.

**Expected output:** Structured odds data per game per book with timestamps. Thin market flags. API quota remaining.

**Checkpoint:**

    Pulled odds for N games across N books | Thin markets: N | API calls remaining: N
    Games: [list]
    Proceed? (yes / drop [game] / add context)

---

## Step 3 — Pregame Researcher (parallel with Step 2)

**Agent:** Pregame Researcher
**Depends on:** Step 1 CLEAR + game list from Step 1.5
**Dispatch mode:** background (one subagent per game, all parallel)

**Purpose:** Produce a structured research brief per game covering injuries, situational angles, and trends.

**Dispatch prompt (per game):**
> Activate Pregame Researcher. Run your full pregame checklist for
> {away_team} vs {home_team} on {date}. Sport: {sport}. Cover:
> injury report, situational angles (rest/travel/schedule spot), key
> trends (ATS, O/U recent), and public betting lean if available. Do
> NOT generate a bet recommendation — that comes downstream. Output a
> structured research brief.

**Expected output:** Per-game research brief with injury flags, situational angles, and key trends.

**Checkpoint:**

    Research complete for N games | Key flags:
    - [game]: [top flag]
    Proceed? (yes / deep dive [game] / skip [game])

---

## Step 4 — Market Maker + Elo Modeler (parallel, then cross-reference)

**Agents:** Market Maker, Elo Modeler
**Depends on:** Steps 2 + 3
**Dispatch mode:** foreground (both dispatched in parallel, orchestrator cross-references)

**Purpose:** Build independent fair-value lines from two methodologies and flag disagreements.

**Dispatch prompt (Market Maker):**
> Activate Market Maker. Build independent fair-value lines for these
> games. Here is the pregame research for situational adjustments:
> {pregame_output}. For each game, output: fair-value spread,
> fair-value total, no-vig moneylines, implied win probabilities. Do
> NOT look at the market lines until after you've formed your own
> number from power ratings and situational factors. Then compare your
> fair values against the market odds: {odds_output}. Output edge
> percentage vs the market consensus line for each game.

**Dispatch prompt (Elo Modeler):**
> Activate Elo Modeler. Generate Elo-based power ratings and game
> predictions for these matchups: {game_list}. Sport: {sport}. Output:
> Elo rating for each team, predicted spread, and implied win
> probability per game.

**Cross-reference (orchestrator):**
After both agents return, compare their spreads. If they disagree by more than 2 points on any game, flag as "model conflict" and downgrade confidence one tier. Use Market Maker's fair values as primary, Elo as validation.

**Expected output:** Per-game fair-value spread, total, MLs, win probs, edge %, model agreement status.

**Checkpoint:**

    Fair values built | Edges found:
    - [game]: market [X] -> fair value [Y] ([Z]% edge) | Elo agrees/conflicts
    - [game]: [Z]% -- PASS
    Proceed with N actionable games? (yes / force [game] / drop [game])

---

## Step 5 — Line Shopper

**Agent:** Line Shopper
**Depends on:** Steps 2 + 4
**Dispatch mode:** foreground

**Purpose:** Find the best available number and juice for each actionable game.

**Dispatch prompt:**
> Activate Line Shopper. For each game where Market Maker found an
> edge of 3% or greater, compare the available book lines from the
> odds data: {odds_output}. Identify the best available number and
> best juice for the recommended side. Output: game, recommended side,
> best book, best line, best juice, and the juice savings vs market
> average.

**Expected output:** Best book + line + juice per actionable game.

**Checkpoint:**

    Best lines found:
    - [game]: [side] best at [book] ([juice]) -- saves N cents vs avg
    Proceed to sizing? (yes / recheck [game])

---

## Step 6 — Kelly Criterion Manager

**Agent:** Kelly Criterion Manager
**Depends on:** Steps 1 + 4 + 5
**Dispatch mode:** foreground

**Purpose:** Size bets using fractional Kelly, enforcing caps and drawdown rules.

**Dispatch prompt:**
> Activate Kelly Criterion Manager. Size bets using fractional Kelly
> (1/4). Bankroll: {bankroll_balance}. For each pick, here are the
> inputs — let Kelly compute the edge internally from these: win
> probability is {win_prob} (from Market Maker), best available
> American odds are {best_odds_american} (from Line Shopper). Apply
> drawdown protection rules. Enforce 3-unit max per bet and 10-unit
> portfolio cap. Output: game, side, computed edge %, Kelly fraction,
> units, dollar amount, and total portfolio exposure.

**Expected output:** Sized picks with units, dollars, and total exposure.

**Checkpoint:**

    Sizing complete | Total exposure: Nu ($X / X% of bankroll)
    - [game]: [side] Nu ($X)
    Generate final betslip? (yes / adjust [game] units)

---

## Step 7 — Betslip Synthesis (no agent dispatch)

**Depends on:** All previous steps

**Purpose:** Assemble the final betslip from all upstream outputs.

**Stale odds check:** Before assembling, compare odds timestamps from Step 2 against game commence times. If any odds are > 90 minutes stale relative to game time, flag as "STALE" and exclude.

**Action:** Combine outputs from all steps into a final betslip. For each pick:
- Matchup, recommended side, best book + line
- Fair value, edge %, model agreement (Market Maker vs Elo)
- Units, dollar stake
- 2-3 sentence thesis drawing from pregame research (Step 3)

For passed games, show why (edge < 3%, thin market, model conflict, stale odds).

End with:
- Exposure summary (total units, total dollars, % of bankroll)
- Responsible gambling disclaimer

---

## Step 8 — Record Bets (optional)

**Agent:** State Manager
**Depends on:** Step 7 (user approval)
**Dispatch mode:** foreground

**Purpose:** Persist picks to the bankroll database for tracking and the learning feedback loop.

Ask the user: **Record these picks to your bankroll? (yes / no)**

If yes:

**Dispatch prompt:**
> Activate State Manager. Record the following bets to
> ~/.syndicate/bankroll.db. For each bet, insert into the bets table
> with: sport = {sport}, game = {matchup}, market = {market_type}
> (e.g., "spread", "moneyline", "total"), selection = {selection}
> (e.g., "Penn +25.5", "BYU ML"), odds = {best_odds_american},
> stake = {dollar_amount}, agent_used = "Sharp Orchestrator
> (pipeline: Odds Scraper -> Pregame Researcher -> Market Maker ->
> Elo Modeler -> Line Shopper -> Kelly Criterion)", result =
> 'PENDING'. Do not modify bankroll_state until bets settle.

**Checkpoint:**

    Recorded N bets | Bet IDs: [list]
    Run ./scripts/bankroll-status.sh to verify.

---

## Intervention Commands

Available at any checkpoint:

| Command | Effect |
|---------|--------|
| `yes` / Enter | Proceed to next step |
| `halt` | Stop the pipeline |
| `drop [game]` | Exclude game from remaining steps |
| `force [game]` | Include a game that was auto-passed |
| `deep dive [game]` | Re-run Pregame Researcher with more depth |
| `adjust [game] units` | Override Kelly sizing |
| `add context` | Provide additional info before next step |

---

## Decision Rules

- **No partial pipelines.** Steps 1-6 must complete before betslip generation.
- **3% edge floor.** Games below this threshold are passed, not sized.
- **90-minute stale gate.** Odds older than 90 min from game time are excluded.
- **Thin market.** < 3 books pricing a game = sizing reduced 50%.
- **Model conflict.** Market Maker and Elo disagree by > 2 pts = confidence downgraded one tier.
- **10-unit portfolio cap.** Total exposure cannot exceed 10 units across all picks.
- **3-unit single bet cap.** No individual pick exceeds 3 units.
- **20% drawdown halt.** Pipeline stops. No new picks until drawdown recovers to < 15%.

---

## Constraints & Disclaimers

This system is for **educational and research purposes only**. Output is based on mathematical models and historical data. It is not a guarantee of profit and should not be construed as financial or gambling advice.

- Sports betting involves substantial risk of loss.
- No model eliminates variance.
- Bet only what you can afford to lose entirely.
- **Problem gambling resources:** 1-800-522-4700 | ncpgambling.org
