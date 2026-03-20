# The Syndicate

A collection of 33 domain-specific AI agent personalities for sports gambling, built for [Claude Code](https://claude.ai/claude-code). Persistent bankroll tracking, bet logging, and a learning feedback loop that improves over time.

Inspired by [agency-agents](https://github.com/msitarzewski/agency-agents) — but focused exclusively on sharp sports betting with automated workflows.

## What Is This?

Each agent is a markdown file that gives Claude Code a specialized personality and toolkit for a specific sports betting task. Load an agent, and Claude becomes a focused expert — whether that's scanning for arbitrage, building DFS lineups, or tracking steam moves.

Every operation is **sport-specific** — you set the sport context (NFL, NBA, MLB, etc.) and all analysis stays within that sport. The Syndicate maintains persistent state in `~/.syndicate/` so it tracks your bankroll, records every bet, and learns which agents and strategies actually make money.

## Agent Categories

| Category | Agents | Focus |
|----------|--------|-------|
| [Odds Analysis](agents/odds-analysis/) | 4 | Opening lines, CLV, steam moves, fair-value pricing |
| [Bankroll](agents/bankroll/) | 4 | Kelly staking, risk management, P&L tracking, state management |
| [Line Shopping](agents/line-shopping/) | 2 | Cross-book comparison, alt line evaluation |
| [Props](agents/props/) | 3 | Player projections, correlations, line screening |
| [Parlays](agents/parlays/) | 2 | Correlated parlays, multi-leg EV calculation |
| [DFS](agents/dfs/) | 2 | Monte Carlo projections, lineup optimization |
| [Arbitrage](agents/arbitrage/) | 2 | Cross-book arbs, middling opportunities |
| [Live Betting](agents/live-betting/) | 2 | In-game odds tracking, live win probability |
| [Modeling](agents/modeling/) | 4 | Elo, regression, simulation, backtesting |
| [Data](agents/data/) | 4 | Odds scraping, stats collection, injuries, weather |
| [Research](agents/research/) | 3 | Pregame matchups, situational spots, breaking news |
| [Orchestration](agents/orchestration/) | 1 | Multi-agent workflow coordination |

## Quick Start

```bash
# Clone the repo
git clone https://github.com/hmdavis/the-syndicate.git
cd the-syndicate

# Install agents to Claude Code
./scripts/install.sh

# Initialize your bankroll (first time only)
./scripts/init-bankroll.sh

# Open Claude Code in any project and select an agent
```

## Installation

```bash
./scripts/install.sh
```

This copies all agent files to `~/.claude/agents/` where Claude Code can discover them. It will also prompt you to initialize your bankroll if you haven't already.

To remove:

```bash
./scripts/install.sh --uninstall
```

## Bankroll & Bet Tracking

The Syndicate maintains persistent state in `~/.syndicate/bankroll.db` — a SQLite database tracking your bankroll, every bet placed, and per-agent performance.

### First-Time Setup

```bash
# Interactive setup — sets starting balance, risk tolerance, enabled sports
./scripts/init-bankroll.sh
```

### Managing Your Betslips

There are two ways to manage bets. Use whichever fits the moment.

#### Option A: Natural Language in Claude Code (recommended)

Load the **State Manager** agent in Claude Code and talk to it. This is the primary interface — no commands to memorize.

**Placing a bet:**
> I put $55 on Chiefs -3.5 at -110 on DraftKings. Market Maker recommended it with 0.68 confidence. NFL.

**Settling a result:**
> Chiefs won 27-20, so bet #12 is a win. Closing line was Chiefs -4.

**Checking open bets:**
> What bets do I have pending?

**Reviewing performance:**
> How are my NBA agents performing over the last 30 days?

**Viewing history:**
> Show my last 10 settled bets and overall P&L.

**Voiding a bet:**
> Void bet #15 — the game was postponed.

**Adjusting bankroll:**
> I deposited $200 into my DraftKings account. Add that to my bankroll.

The State Manager records everything to `~/.syndicate/bankroll.db` with full agent attribution, CLV tracking, and P&L calculation.

#### Option B: CLI Scripts

For quick entries from the terminal without opening Claude Code.

```bash
# Place a new bet (interactive prompts)
./scripts/bet.sh place

# List open (unsettled) bets
./scripts/bet.sh open

# Settle a bet by ID
./scripts/bet.sh settle 12

# View a specific bet
./scripts/bet.sh view 12

# Recent settled history
./scripts/bet.sh history 20

# Void a pending bet
./scripts/bet.sh void 12

# Full dashboard: balance, P&L, agent performance, equity curve
./scripts/bankroll-status.sh
```

### Betslip Lifecycle

```
 ┌──────────┐      ┌──────────┐      ┌──────────────┐
 │  PLACE   │ ───► │ PENDING  │ ───► │  SETTLE      │
 │          │      │          │      │  win / loss / │
 │ record   │      │ bet is   │      │  push / void │
 │ the bet  │      │ open     │      │              │
 └──────────┘      └──────────┘      └──────────────┘
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │ BANKROLL     │
                                     │ UPDATED      │
                                     │              │
                                     │ P&L, CLV,    │
                                     │ agent perf   │
                                     │ all recorded │
                                     └──────────────┘
```

Every bet records: **sport, game, market, selection, odds, stake, agent used, confidence, and notes.** On settlement: **result, P&L, CLV (if closing odds provided), and timestamp.**

### Learning Feedback Loop

The Syndicate tracks which agent recommended each bet. Over time, it builds a performance profile per agent per sport — surfacing which combinations are profitable and which need review.

Ask the State Manager agent:
> Give me a 30-day performance report.

```
SYNDICATE LEARNING FEEDBACK — LAST 30 DAYS
========================================================
  Portfolio ROI:  +4.8%
  Total Wagered:  $8,240.00
  Net P&L:        +$395.52

  TOP PERFORMERS:
    + Player Prop Analyst (NBA): +8.2% ROI | 34 bets | avg CLV +1.8c → keep deploying
  UNDERPERFORMERS (review approach):
    - Market Maker (NFL): -3.1% ROI | 41 bets | avg CLV -0.4c
```

Or from the terminal:
```bash
./scripts/bankroll-status.sh
```

## Workflows

Pre-built multi-agent workflows. Each includes a "How to Run" section explaining Claude Code, Claude Desktop, and standalone CLI usage.

| Workflow | Run In | Description |
|----------|--------|-------------|
| [Daily Picks](workflows/daily-picks.md) | Claude Code | Full pipeline from research to sized picks |
| [Arb Scan](workflows/arb-scan.md) | Claude Code | Cross-book + Polymarket arbitrage detection |
| [Pregame Research](workflows/pregame-research.md) | Claude Code (partial in Desktop) | Deep single-game matchup analysis |
| [DFS Lineup Builder](workflows/dfs-lineup-builder.md) | Claude Code | Optimized DFS lineups with CSV export |

**Claude Code** is the primary execution environment — it can run Python, call APIs, read/write files, and chain agents together. **Claude Desktop** can reason about strategy but cannot execute code or access APIs. Each workflow doc explains what's possible in each environment.

## Environment Variables

Copy `.env.example` to `.env` and fill in your API keys:

```bash
cp .env.example .env
```

| Variable | Required | Source | Used By |
|----------|----------|--------|---------|
| `ODDS_API_KEY` | **Yes** | [the-odds-api.com](https://the-odds-api.com) (free tier: 500 req/mo) | odds-scraper, line-shopper, arb-scanner, steam-move-detector |
| `POLYMARKET_API_KEY` | No | [polymarket.com](https://polymarket.com) | arb-scanner (reads are free, no key needed) |
| `CFBD_API_KEY` | No | [collegefootballdata.com](https://collegefootballdata.com) | stats-collector (college football only) |
| `SPORTRADAR_API_KEY` | No | sportradar.com (paid) | stats-collector (premium tier) |
| `ODDSJAM_API_KEY` | No | [oddsjam.com](https://oddsjam.com) (paid) | odds-scraper (premium odds) |
| `SLACK_WEBHOOK_URL` | No | Slack app settings | arb alerts, pick report delivery |
| `PUSHOVER_USER_KEY` | No | [pushover.net](https://pushover.net) | mobile arb alerts |
| `DISCORD_WEBHOOK_URL` | No | Discord server settings | alert delivery |

**No key required:** nba_api, nfl_data_py, pybaseball, Open-Meteo weather, ESPN injury API — these are all free and unauthenticated.

## Data Sources

Reference docs for integrating with betting data:

- [Odds APIs](data-sources/odds-apis.md) — The Odds API, Polymarket CLOB, OddsJam, Pinnacle
- [Stats APIs](data-sources/stats-apis.md) — nba_api, nfl_data_py, pybaseball, etc.
- [Sportsbook Feeds](data-sources/sportsbook-feeds.md) — Direct book feeds, Polymarket as benchmark

## Responsible Gambling

These agents are tools for analysis and education. Sports betting involves real financial risk.

- Never bet more than you can afford to lose
- Set hard bankroll limits and stick to them
- No system guarantees profit — past performance does not predict future results
- If gambling stops being fun, visit [1-800-GAMBLER](https://www.1800gambler.net/) or [NCPG](https://www.ncpgambling.org/)

## License

[MIT](LICENSE)
