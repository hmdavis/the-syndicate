# Daily Picks Pipeline — Orchestrator Redesign

**Date:** 2026-03-19
**Status:** Approved
**Scope:** Rewrite Sharp Orchestrator + Daily Picks workflow to use agent-chaining dispatch pattern (modeled after [agency-agents](https://github.com/msitarzewski/agency-agents))

---

## Problem

The Sharp Orchestrator defines a 5-step Python subprocess pipeline (`stats_collector.py`, `odds_scraper.py`, `market_maker.py`, etc.) but none of those Python files exist. The agents are markdown persona files, not executable code. When the orchestrator runs as a subagent, it falls back to a single monolithic LLM doing web searches instead of chaining the specialized agents.

## Solution

Rewrite the orchestrator and workflow to use the agency-agents pattern:

- Agents remain markdown persona files (no change)
- Workflows become step-by-step playbooks with **exact dispatch prompts**
- The Sharp Orchestrator reads the workflow, dispatches each agent as a Claude Code subagent, passes context between them, and surfaces checkpoints to the user
- **Hybrid mode:** auto-chains agents but shows output at each step so the user can intervene

## Approach

**Approach 1: Workflow-as-Script** (selected over Monolithic Orchestrator and Thin Dispatcher Script)

- `workflows/daily-picks.md` = the playbook (single source of truth for the pipeline)
- `agents/orchestration/sharp-orchestrator.md` = the conductor (reads workflows, manages handoffs)
- Agent files = unchanged personas dispatched with context

---

## Pipeline: 7 Steps

```
Step 1: State Manager          Step 2: Odds Scraper
  (bankroll check)               (live lines)
        |                              |
        v                              v
   drawdown gate              odds by game + book
   bankroll balance           spreads, MLs, totals
        |                              |
        |         +--------------------+
        |         |                    |
        |         v                    |
        |   Step 3: Pregame            |
        |   Researcher                 |
        |   (parallel per game)        |
        |         |                    |
        |         v                    |
        |   injuries, situational      |
        |   angles, trends             |
        |         |                    |
        v         v                    v
      Step 4: Market Maker + Elo Modeler
      (independent fair values, cross-referenced)
                |
                v
        fair-value spreads,
        totals, win probs
                |
                v
      Step 5: Line Shopper
      (best number per bet)
                |
                v
        best book + price
        per side per game
                |
                v
      Step 6: Kelly Criterion
      (bet sizing)
                |
                v
        sized picks with
        units + exposure
                |
                v
      Step 7: Sharp Orchestrator
      (synthesize betslip)
                |
                v
      Step 8: State Manager
      (record bets, optional)
```

### Parallelism

- Steps 2 and 3 run in parallel — Step 2 (Odds Scraper) produces the game list, Step 3 (Pregame Researcher) uses it. To resolve this dependency while preserving parallelism: the orchestrator itself fetches the game list from The Odds API as a lightweight lookup between Steps 1 and 2/3 (just game names + tip times, not full odds). Both Steps 2 and 3 then receive the game list as input and run concurrently.
- Step 3 dispatches one Pregame Researcher subagent per game (parallel)
- Step 4 dispatches both Market Maker and Elo Modeler in parallel, then cross-references their outputs
- All other steps are sequential

### Gates

- Step 1: If drawdown > 20%, pipeline halts. No new picks until drawdown recovers to < 15%.
- Step 4: Games with edge < 3% are marked PASS and excluded from Steps 5-7
- Step 4: If Market Maker and Elo Modeler disagree by > 2 points on a spread, flag as "model conflict" and downgrade confidence one tier
- Step 5: Games with < 3 books pricing them are flagged "thin market" — this flag originates in Step 2 and propagates through to Step 6 where sizing is reduced 50%
- Step 7: If odds timestamp is > 90 minutes old relative to game time, flag as "stale" and exclude from betslip

---

## Workflow Step Template

Each step in `workflows/daily-picks.md` follows this structure:

```markdown
### Step N: [Step Name]

**Agent:** [Agent Name]
**Depends on:** Step N-1 output (or "none")
**Dispatch mode:** [foreground / background]

**Purpose:** One sentence on what this step accomplishes.

**Dispatch prompt:**
> [Exact prompt with {placeholders} for upstream output]

**Expected output:** What the agent returns.

**Checkpoint:** What the user sees before proceeding.
```

---

## Placeholder Convention

Placeholders in dispatch prompts use `{curly_braces}`. Two categories:

**User-provided inputs** (set once at pipeline start):
- `{sport}` — sport key (e.g., `basketball_ncaab`)
- `{date}` — game date (e.g., `2026-03-19`)

**Inter-step data flow** (substituted with actual agent output at runtime):
- `{game_list}` — game names + tip times from pre-Step-2 lookup
- `{bankroll_balance}` — from Step 1
- `{odds_output}` — full output from Step 2
- `{pregame_output}` — combined output from Step 3 (all games)
- `{fair_values_output}` — from Step 4 (Market Maker + Elo Modeler)
- `{line_shop_output}` — from Step 5
- `{win_prob}`, `{best_odds_american}` — per-pick values extracted from Steps 4+5

The orchestrator passes **full text output** between steps (not summaries) to preserve context for downstream agents.

---

## Dispatch Prompts

### Step 1 — State Manager (gate)

**Agent:** State Manager
**Depends on:** none
**Dispatch mode:** foreground

**Dispatch prompt:**
> Activate State Manager. Read the current bankroll state from ~/.syndicate/bankroll.db. The bankroll_state table has columns: current_balance, starting_balance, risk_tolerance, created_at, updated_at. Compute P&L as (current_balance - starting_balance). Compute drawdown percentage as ((starting_balance - current_balance) / starting_balance * 100) — if current_balance > starting_balance, drawdown is 0%. Check sports_config to confirm {sport} is enabled. Report: current balance, starting balance, computed P&L, computed drawdown %, risk tolerance, and sport status. If drawdown exceeds 20%, output HALT with the reason. No new picks until drawdown recovers to < 15%. Otherwise output CLEAR with the bankroll summary.

**Expected output:** Bankroll balance, computed P&L, computed drawdown %, CLEAR/HALT status, sport config.

**Checkpoint:**
> Bankroll: $X | P&L: $X | Drawdown: X% | Status: CLEAR/HALT | Sport: {sport} enabled
> *Proceed? (yes / halt)*

---

### Step 1.5 — Game List Lookup (orchestrator, no agent dispatch)

The orchestrator fetches the day's game list as a lightweight lookup before dispatching Steps 2 and 3. This resolves the dependency: both Odds Scraper and Pregame Researcher need the game list, but they run in parallel.

**Action:** Query The Odds API for {sport} on {date} to get game matchups and commence times. Use `ODDS_API_KEY` environment variable. Only the game list is needed here — full odds are pulled in Step 2.

**Output:** `{game_list}` — list of matchups with tip times, passed to Steps 2 and 3.

---

### Step 2 — Odds Scraper (parallel with Step 3)

**Agent:** Odds Scraper
**Depends on:** Step 1 CLEAR + game list from Step 1.5
**Dispatch mode:** background (parallel with Step 3)

**Dispatch prompt:**
> Activate Odds Scraper. Pull current odds for these {sport} games on {date}: {game_list}. Use the `ODDS_API_KEY` environment variable (as defined in CLAUDE.md and .env.example). Markets: h2h, spreads, totals. Region: us. Return a structured table per game showing: matchup, spread (home perspective), total, and moneyline for each available book. Include the odds timestamp for each game. Flag any games with fewer than 3 books pricing them as "thin market" — this flag will propagate to downstream sizing.

**Expected output:** Structured odds data per game per book with timestamps. Thin market flags. API quota remaining.

**Checkpoint:**
> Pulled odds for N games across N books | Thin markets: N | API calls remaining: N
> *Games listed*
> *Proceed? (yes / drop [game] / add context)*

---

### Step 3 — Pregame Researcher (parallel with Step 2, one per game)

**Agent:** Pregame Researcher
**Depends on:** Step 1 CLEAR + game list from Step 1.5
**Dispatch mode:** background (parallel with Step 2; one subagent per game)

**Dispatch prompt (per game):**
> Activate Pregame Researcher. Run your full pregame checklist for {away_team} vs {home_team} on {date}. Sport: {sport}. Cover: injury report, situational angles (rest/travel/schedule spot), key trends (ATS, O/U recent), and public betting lean if available. Do NOT generate a bet recommendation -- that comes downstream. Output a structured research brief.

**Expected output:** Per-game research brief with injury flags, situational angles, and key trends.

**Checkpoint:**
> Research complete for N games | Key flags:
> - [game]: [top flag]
> *Proceed? (yes / deep dive [game] / skip [game])*

---

### Step 4 — Market Maker + Elo Modeler (parallel, then cross-reference)

**Agents:** Market Maker, Elo Modeler
**Depends on:** Steps 2 + 3
**Dispatch mode:** foreground (both dispatched in parallel, then orchestrator cross-references)

**Dispatch prompt (Market Maker):**
> Activate Market Maker. Build independent fair-value lines for these games. Here is the pregame research for situational adjustments: {pregame_output}. For each game, output: fair-value spread, fair-value total, no-vig moneylines, implied win probabilities. Do NOT look at the market lines until after you've formed your own number from power ratings and situational factors. Then compare your fair values against the market odds: {odds_output}. Output edge percentage vs the market consensus line for each game.

**Dispatch prompt (Elo Modeler):**
> Activate Elo Modeler. Generate Elo-based power ratings and game predictions for these matchups: {game_list}. Sport: {sport}. Output: Elo rating for each team, predicted spread, and implied win probability per game.

**Cross-reference (orchestrator):**
> After both agents return, compare their spreads. If they disagree by more than 2 points on any game, flag as "model conflict" and downgrade confidence one tier for that game. Use the Market Maker's fair values as primary, with Elo as a validation signal.

**Expected output:** Per-game fair-value spread, total, MLs, win probs, edge %, model agreement status.

**Checkpoint:**
> Fair values built | Edges found:
> - [game]: market [X] -> fair value [Y] ([Z]% edge) | Elo agrees/conflicts
> - [game]: [Z]% -- PASS
> *Proceed with N actionable games? (yes / force [game] / drop [game])*

---

### Step 5 — Line Shopper

**Agent:** Line Shopper
**Depends on:** Steps 2 + 4
**Dispatch mode:** foreground

**Dispatch prompt:**
> Activate Line Shopper. For each game where Market Maker found an edge of 3% or greater, compare the available book lines from the odds data: {odds_output}. Identify the best available number and best juice for the recommended side. Output: game, recommended side, best book, best line, best juice, and the juice savings vs market average.

**Expected output:** Best book + line + juice per actionable game.

**Checkpoint:**
> Best lines found:
> - [game]: [side] best at [book] ([juice]) -- saves N cents vs avg
> *Proceed to sizing? (yes / recheck [game])*

---

### Step 6 — Kelly Criterion Manager

**Agent:** Kelly Criterion Manager
**Depends on:** Steps 1 + 4 + 5
**Dispatch mode:** foreground

**Dispatch prompt:**
> Activate Kelly Criterion Manager. Size bets using fractional Kelly (1/4). Bankroll: {bankroll_balance}. For each pick, here are the inputs — let Kelly compute the edge internally from these: win probability is {win_prob} (from Market Maker), best available American odds are {best_odds_american} (from Line Shopper). Apply drawdown protection rules. Enforce 3-unit max per bet and 10-unit portfolio cap. Output: game, side, computed edge %, Kelly fraction, units, dollar amount, and total portfolio exposure.

**Expected output:** Sized picks with units, dollars, and total exposure.

**Checkpoint:**
> Sizing complete | Total exposure: Nu ($X / X% of bankroll)
> - [game]: [side] Nu ($X)
> *Generate final betslip? (yes / adjust [game] units)*

---

### Step 7 — Sharp Orchestrator (synthesis, no dispatch)

The orchestrator itself assembles the final betslip from all upstream outputs. No agent dispatch needed.

**Action:** Before assembling the betslip, check odds timestamps from Step 2 against game commence times. If any odds are > 90 minutes stale relative to game time, flag as "STALE" and exclude from the betslip. Then combine outputs from all steps into a final betslip. For each pick: matchup, recommended side, best book + line, fair value, edge %, model agreement (Market Maker vs Elo), units, dollar stake, and a 2-3 sentence thesis drawing from the pregame research. For passed games, show why (edge below 3%, thin market, model conflict, stale odds, etc.). End with exposure summary and responsible gambling disclaimer.

---

### Step 8 — Bet Recording (optional, user-initiated)

**Agent:** State Manager
**Depends on:** Step 7 (user approval of betslip)
**Dispatch mode:** foreground

After presenting the betslip, ask the user: *"Record these picks to your bankroll? (yes / no)"*

If yes:

**Dispatch prompt:**
> Activate State Manager. Record the following bets to ~/.syndicate/bankroll.db. For each bet, insert into the bets table with: sport = {sport}, game = {matchup}, side = {side}, odds = {best_odds_american}, stake = {dollar_amount}, agent_used = "Sharp Orchestrator (pipeline: Odds Scraper -> Pregame Researcher -> Market Maker -> Elo Modeler -> Line Shopper -> Kelly Criterion)". Set status to "open". Do not modify bankroll_state until the bets settle.

**Expected output:** Confirmation of recorded bets with bet IDs.

**Checkpoint:**
> Recorded N bets | Bet IDs: [list]
> *Run `./scripts/bankroll-status.sh` to verify.*

---

## Checkpoint Design

Consistent format across all steps:
1. Data summary (what was produced)
2. Actionable flags (edges, thin markets, key injuries)
3. User prompt with specific intervention options

Interventions available:
- `yes` / Enter — proceed to next step
- `halt` — stop the pipeline
- `drop [game]` — exclude a game from remaining steps
- `force [game]` — include a game that was auto-passed
- `deep dive [game]` — re-run Pregame Researcher with more depth
- `adjust [game] units` — override Kelly sizing
- `add context` — provide additional info before next step

---

## File Changes

### 1. `workflows/daily-picks.md` — Full Rewrite

Replace the current Python subprocess workflow with the 7-step dispatch playbook described above.

### 2. `agents/orchestration/sharp-orchestrator.md` — Streamlined Rewrite

Remove:
- All Python pipeline code (bash scripts, asyncio orchestration, arb scanner code, DFS builder code, morning sync code)
- Workflow-specific logic embedded in the agent

Replace with:
- Updated identity section (conductor, not coder)
- Core mission: read workflow files, dispatch agents, manage handoffs, surface checkpoints
- Workflow execution protocol: how to read a workflow markdown, substitute placeholders, dispatch agents, handle interventions
- Decision rules (kept: 3% edge floor, 10-unit cap, stale odds, thin market rules)
- Reference to other workflows (arb scan, pregame research, DFS, morning sync) noted as "not yet converted to dispatch format"

### 3. Agent files — No Changes

The existing agent personas work as-is when dispatched with the right prompts.

---

## Design Decisions

1. **Hybrid execution mode** — auto-chains agents but surfaces output at each step for user intervention
2. **Workflow-as-Script pattern** — modeled after agency-agents workflow examples where each step has the exact activation prompt
3. **Parallel dispatch** — Steps 2+3 run concurrently; Step 3 dispatches one agent per game; Step 4 dispatches Market Maker + Elo Modeler concurrently
4. **No Python code** — the entire pipeline runs through Claude Code agent dispatching, not subprocess execution
5. **Placeholder substitution** — `{placeholders}` in dispatch prompts are replaced with actual upstream output at runtime (see Placeholder Convention section)
6. **Game list pre-fetch** — orchestrator fetches game list between Steps 1 and 2/3 to resolve the parallel dependency without adding a full agent dispatch
7. **Kelly computes its own edge** — dispatch prompt passes win_prob and odds, not pre-computed edge, to avoid formula inconsistencies between Market Maker and Kelly
8. **Dual model validation** — Market Maker + Elo Modeler run independently; disagreement > 2 points flags model conflict and downgrades confidence
9. **Stale odds gate** — Step 7 checks odds timestamps; > 90 minutes stale = excluded from betslip
10. **Bet recording is opt-in** — Step 8 only fires if the user confirms, per CLAUDE.md convention that State Manager is the canonical DB interface
11. **Scope limited to Daily Picks** — other workflows (arb scan, pregame research, DFS, morning sync) are out of scope and will be converted later using the same pattern
