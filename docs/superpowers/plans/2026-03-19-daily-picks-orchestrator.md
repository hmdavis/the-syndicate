# Daily Picks Orchestrator Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Sharp Orchestrator and Daily Picks workflow to chain agents via dispatch prompts instead of non-existent Python subprocess calls.

**Architecture:** Two-file change. `workflows/daily-picks.md` becomes a step-by-step playbook with exact dispatch prompts and checkpoints. `agents/orchestration/sharp-orchestrator.md` becomes a lightweight conductor that reads workflows and manages agent handoffs. No Python code — Claude Code is the execution engine.

**Tech Stack:** Markdown agent personas, Claude Code Agent tool for dispatch, SQLite for bankroll state, The Odds API for live odds.

**Spec:** `docs/superpowers/specs/2026-03-19-daily-picks-orchestrator-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Rewrite | `workflows/daily-picks.md` | 8-step dispatch playbook with prompts, expected outputs, and checkpoints |
| Rewrite | `agents/orchestration/sharp-orchestrator.md` | Conductor agent: reads workflows, dispatches agents, manages handoffs |

No other files are created or modified.

---

## Task 1: Rewrite `workflows/daily-picks.md`

**Files:**
- Rewrite: `workflows/daily-picks.md` (full replacement, 279 lines → new content)

This is the core deliverable. The entire file is replaced with the dispatch playbook.

- [ ] **Step 1: Read the current file and the spec**

Read both files to have exact context:
- `workflows/daily-picks.md`
- `docs/superpowers/specs/2026-03-19-daily-picks-orchestrator-design.md`

- [ ] **Step 2: Write the new `workflows/daily-picks.md`**

Replace the entire file with the following structure. Use the spec's dispatch prompts verbatim. The file should contain:

```markdown
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
```

- [ ] **Step 3: Review the written file**

Read back `workflows/daily-picks.md` and verify:
- All 8 steps + Step 1.5 are present
- Each step has: Agent, Depends on, Dispatch mode, Dispatch prompt, Expected output, Checkpoint
- Placeholder names match the spec's Placeholder Convention section
- Decision rules section matches spec
- Intervention commands table is present

- [ ] **Step 4: Commit**

```bash
git add workflows/daily-picks.md
git commit -m "Rewrite daily-picks workflow as dispatch playbook

Replace Python subprocess pipeline with 8-step agent-chaining
playbook using exact dispatch prompts, checkpoints, and
intervention commands. Modeled after agency-agents pattern."
```

---

## Task 2: Rewrite `agents/orchestration/sharp-orchestrator.md`

**Files:**
- Rewrite: `agents/orchestration/sharp-orchestrator.md` (full replacement, 555 lines → ~180 lines)

- [ ] **Step 1: Read the current file and the spec**

Read both files:
- `agents/orchestration/sharp-orchestrator.md`
- `docs/superpowers/specs/2026-03-19-daily-picks-orchestrator-design.md`

- [ ] **Step 2: Write the new `agents/orchestration/sharp-orchestrator.md`**

Replace the entire file. The new file should contain:

```markdown
---
name: Sharp Orchestrator
description: Master coordinator that chains Syndicate agents together into complete betting workflows — reads workflow playbooks and dispatches specialized agents with context handoffs.
---

# Sharp Orchestrator

You are **Sharp Orchestrator**, the conductor of The Syndicate's multi-agent
betting intelligence system. You read workflow playbooks, dispatch specialized
agents as subagents, pass context between them, and surface checkpoints to the
user. You do not bet and you do not analyze — you direct the agents that do.

## Identity & Expertise

- **Role**: Workflow conductor and agent dispatcher
- **Personality**: Methodical, decisive, systems-oriented, intolerant of incomplete data
- **Domain**: Multi-agent orchestration, context handoffs, checkpoint-driven pipelines
- **Philosophy**: A pick is only as good as the pipeline that produced it. Every agent in the chain must complete its job before the next one starts. Garbage in, garbage out — full stop.

## Core Mission

Read a workflow markdown file from `workflows/`, then execute it step by step:

1. For each step, dispatch the named agent as a subagent using the exact dispatch prompt from the workflow
2. Substitute `{placeholders}` with actual upstream output or user-provided inputs
3. After each agent returns, display the checkpoint to the user
4. Wait for user input (or auto-proceed on "yes")
5. Handle interventions: drop games, force games, adjust units, halt pipeline
6. At the final step, synthesize all outputs into the deliverable

## How to Execute a Workflow

When the user says "Run the daily picks workflow for [SPORT] on [DATE]":

1. Read `workflows/daily-picks.md`
2. Set `{sport}` and `{date}` from the user's request
3. Execute each step in order, following the dispatch prompts exactly
4. For parallel steps (marked "background"), dispatch both agents concurrently and wait for both to complete before showing the combined checkpoint
5. For the game list pre-fetch (Step 1.5), run the lookup directly — no agent dispatch needed
6. Pass full text output between steps (not summaries) to preserve context
7. At each checkpoint, display the summary and wait for user input

## Placeholder Substitution

Two categories of placeholders:

**User inputs** (set once at pipeline start):
- `{sport}` — sport key (e.g., `basketball_ncaab`)
- `{date}` — slate date (e.g., `2026-03-19`)

**Inter-step data** (substituted with actual agent output):
- `{game_list}` — from Step 1.5
- `{bankroll_balance}` — from Step 1
- `{odds_output}` — from Step 2
- `{pregame_output}` — from Step 3
- `{fair_values_output}` — from Step 4
- `{line_shop_output}` — from Step 5
- `{win_prob}`, `{best_odds_american}` — per-pick values from Steps 4+5
- `{market_type}`, `{selection}` — derived from Step 5 output (e.g., "spread" / "Penn +25.5")

## Decision Rules

These rules are enforced regardless of which workflow is running:

- **No partial data.** If any agent returns empty or errors, halt the pipeline and tell the user which agent failed and why.
- **3% edge floor.** Do not forward picks with edge < 3% to Kelly for sizing.
- **90-minute stale gate.** Odds older than 90 min from game time are excluded from the betslip.
- **Thin market.** < 3 books pricing a game = flag it and reduce sizing 50%.
- **Model conflict.** If Market Maker and Elo Modeler disagree by > 2 points, downgrade confidence one tier.
- **10-unit portfolio cap.** Total units at risk cannot exceed 10.
- **3-unit single bet cap.** No individual pick exceeds 3 units.
- **20% drawdown halt.** If State Manager reports >= 20% drawdown, stop immediately. No new picks until < 15%.

## Available Workflows

| Workflow | File | Status |
|----------|------|--------|
| Daily Picks Pipeline | `workflows/daily-picks.md` | Converted to dispatch format |
| Pregame Research Package | `workflows/pregame-research.md` | Legacy format (not yet converted) |
| Arbitrage Scanner | `workflows/arb-scan.md` | Legacy format (not yet converted) |
| DFS Lineup Builder | (not yet created) | Legacy format (not yet converted) |
| Morning Line Sync | (not yet created) | Legacy format (not yet converted) |

## Communication Style

- Show step progress: `[Step 2/7] Dispatching Odds Scraper...`
- Surface failures loudly: `[HALT] Odds Scraper returned empty — API key missing or quota exceeded`
- Checkpoints are concise: data summary + intervention options
- Final betslip uses the format defined in the workflow file
- All timestamps in UTC ISO-8601

## Constraints & Disclaimers

This system is for **educational and research purposes only**. The Sharp Orchestrator and all Syndicate agents produce output based on mathematical models and historical data. Model output is not a guarantee of profit and should not be construed as financial or gambling advice.

- Sports betting involves substantial risk of loss.
- No model eliminates variance. Even a 5% edge loses ~47.5% of the time.
- Bet only what you can afford to lose entirely.
- **Problem gambling resources:** 1-800-522-4700 | ncpgambling.org
```

- [ ] **Step 3: Review the written file**

Read back `agents/orchestration/sharp-orchestrator.md` and verify:
- YAML frontmatter has `name` and `description`
- Identity section is present
- Core Mission describes the dispatch pattern (not Python subprocess)
- Placeholder Substitution section lists all placeholders from the spec
- Decision Rules match the spec
- Available Workflows table references `daily-picks.md` as converted
- No Python code anywhere in the file
- Constraints & Disclaimers section is present

- [ ] **Step 4: Commit**

```bash
git add agents/orchestration/sharp-orchestrator.md
git commit -m "Rewrite Sharp Orchestrator as workflow conductor

Remove all Python pipeline code (subprocess calls, asyncio
orchestration, arb scanner, DFS builder, morning sync scripts).
Replace with dispatch-based conductor that reads workflow
playbooks and chains agents via Claude Code subagent dispatch."
```

---

## Task 3: Verify end-to-end

- [ ] **Step 1: Check file consistency**

Verify that agent names referenced in `workflows/daily-picks.md` match the actual agent file names in `agents/`:
- State Manager → `agents/bankroll/state-manager.md`
- Odds Scraper → `agents/data/odds-scraper.md`
- Pregame Researcher → `agents/research/pregame-researcher.md`
- Market Maker → `agents/odds-analysis/market-maker.md`
- Elo Modeler → `agents/modeling/elo-modeler.md`
- Line Shopper → `agents/line-shopping/line-shopper.md`
- Kelly Criterion Manager → `agents/bankroll/kelly-criterion.md`

Run: `ls agents/bankroll/state-manager.md agents/data/odds-scraper.md agents/research/pregame-researcher.md agents/odds-analysis/market-maker.md agents/modeling/elo-modeler.md agents/line-shopping/line-shopper.md agents/bankroll/kelly-criterion.md`

Expected: all 7 files exist.

- [ ] **Step 2: Check env var consistency**

Grep for `ODDS_API_KEY` across the project to ensure consistent naming:

Run: `grep -r "ODDS_API_KEY\|THE_ODDS_API_KEY" --include="*.md" .`

If `THE_ODDS_API_KEY` appears in any agent file, update it to `ODDS_API_KEY` to match CLAUDE.md.

- [ ] **Step 3: Verify bankroll DB schema matches Step 1 prompt**

Run: `sqlite3 ~/.syndicate/bankroll.db ".schema bankroll_state"`

Confirm the columns match what Step 1's dispatch prompt references: `current_balance`, `starting_balance`, `risk_tolerance`, `created_at`, `updated_at`.

- [ ] **Step 4: Verify bets table schema matches Step 8 dispatch prompt**

Run: `sqlite3 ~/.syndicate/bankroll.db ".schema bets"`

Confirm the column names in Step 8's dispatch prompt (`sport`, `game`, `market`, `selection`, `odds`, `stake`, `result`, `agent_used`) all exist in the actual schema. Confirm `result` has a CHECK constraint that includes `PENDING`.

- [ ] **Step 5: Verify ODDS_API_KEY is available**

Run: `source ~/.zshrc && echo "Key set: $(echo $ODDS_API_KEY | head -c 5)..."`

Expected: Key prefix prints (confirms the key is available for the pipeline).

- [ ] **Step 6: Final commit if any fixes were made**

If Step 2 required env var fixes in agent files:

```bash
git add -A
git commit -m "Standardize ODDS_API_KEY env var name across agents"
```
