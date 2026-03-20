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
      Step 4: Market Maker
      (independent fair values)
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
```

### Parallelism

- Steps 2 and 3 run in parallel (no dependency on each other)
- Step 3 dispatches one Pregame Researcher subagent per game (parallel)
- All other steps are sequential

### Gates

- Step 1: If drawdown > 20%, pipeline halts
- Step 4: Games with edge < 3% are marked PASS and excluded from Steps 5-7
- Step 5: Games with < 3 books pricing them are flagged "thin market" and sizing is reduced 50%

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

## Dispatch Prompts

### Step 1 — State Manager (gate)

**Agent:** State Manager
**Depends on:** none
**Dispatch mode:** foreground

**Dispatch prompt:**
> Activate State Manager. Read the current bankroll state from ~/.syndicate/bankroll.db. Report: current balance, starting balance, P&L, drawdown percentage, and whether any sport-specific exposure limits apply for {sport}. If drawdown exceeds 20%, output HALT with the reason. Otherwise output CLEAR with the bankroll summary.

**Expected output:** Bankroll balance, drawdown %, CLEAR/HALT status, sport config.

**Checkpoint:**
> Bankroll: $X | Drawdown: X% | Status: CLEAR/HALT | Sport: {sport} enabled
> *Proceed? (yes / halt)*

---

### Step 2 — Odds Scraper (parallel with Step 3)

**Agent:** Odds Scraper
**Depends on:** Step 1 CLEAR
**Dispatch mode:** background (parallel with Step 3)

**Dispatch prompt:**
> Activate Odds Scraper. Pull current odds for {sport} games on {date} from The Odds API. Use the ODDS_API_KEY environment variable. Markets: h2h, spreads, totals. Region: us. Return a structured table per game showing: matchup, spread (home perspective), total, and moneyline for each available book. Flag any games with fewer than 3 books pricing them as "thin market."

**Expected output:** Structured odds data per game per book. Thin market flags. API quota remaining.

**Checkpoint:**
> Pulled odds for N games across N books | Thin markets: N | API calls remaining: N
> *Games listed*
> *Proceed? (yes / drop [game] / add context)*

---

### Step 3 — Pregame Researcher (parallel with Step 2, one per game)

**Agent:** Pregame Researcher
**Depends on:** Step 1 CLEAR
**Dispatch mode:** background (parallel with Step 2; one subagent per game)

**Dispatch prompt (per game):**
> Activate Pregame Researcher. Run your full pregame checklist for {away_team} vs {home_team} on {date}. Sport: {sport}. Cover: injury report, situational angles (rest/travel/schedule spot), key trends (ATS, O/U recent), and public betting lean if available. Do NOT generate a bet recommendation -- that comes downstream. Output a structured research brief.

**Expected output:** Per-game research brief with injury flags, situational angles, and key trends.

**Checkpoint:**
> Research complete for N games | Key flags:
> - [game]: [top flag]
> *Proceed? (yes / deep dive [game] / skip [game])*

---

### Step 4 — Market Maker

**Agent:** Market Maker
**Depends on:** Steps 2 + 3
**Dispatch mode:** foreground

**Dispatch prompt:**
> Activate Market Maker. Build independent fair-value lines for these games. Here are the current market odds: {odds_output}. Here is the pregame research for situational adjustments: {pregame_output}. For each game, output: fair-value spread, fair-value total, no-vig moneylines, implied win probabilities, and edge percentage vs the market consensus line. Do NOT look at the market lines until after you've formed your own number from power ratings and situational factors.

**Expected output:** Per-game fair-value spread, total, MLs, win probs, edge %.

**Checkpoint:**
> Fair values built | Edges found:
> - [game]: market [X] -> fair value [Y] ([Z]% edge)
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
> Activate Kelly Criterion Manager. Size bets for the following edges using fractional Kelly (1/4). Bankroll: {bankroll_balance}. For each pick: edge percentage is {edge_pct}, best available odds are {best_odds}. Apply drawdown protection rules. Enforce 3-unit max per bet and 10-unit portfolio cap. Output: game, side, units, dollar amount, and total portfolio exposure.

**Expected output:** Sized picks with units, dollars, and total exposure.

**Checkpoint:**
> Sizing complete | Total exposure: Nu ($X / X% of bankroll)
> - [game]: [side] Nu ($X)
> *Generate final betslip? (yes / adjust [game] units)*

---

### Step 7 — Sharp Orchestrator (synthesis, no dispatch)

The orchestrator itself assembles the final betslip from all upstream outputs. No agent dispatch needed.

**Action:** Combine outputs from all steps into a final betslip. For each pick: matchup, recommended side, best book + line, fair value, edge %, units, dollar stake, and a 2-3 sentence thesis drawing from the pregame research. For passed games, show why (edge below 3%, thin market, etc.). End with exposure summary and responsible gambling disclaimer.

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
3. **Parallel dispatch** — Steps 2+3 run concurrently; Step 3 dispatches one agent per game
4. **No Python code** — the entire pipeline runs through Claude Code agent dispatching, not subprocess execution
5. **Placeholder substitution** — `{placeholders}` in dispatch prompts are replaced with actual upstream output at runtime
6. **Scope limited to Daily Picks** — other workflows (arb scan, pregame research, DFS, morning sync) are out of scope and will be converted later using the same pattern
