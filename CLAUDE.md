# The Syndicate — Claude Code Instructions

## Project Overview

This is a collection of AI agent personalities for sports gambling analysis, built for Claude Code. Each agent is a markdown file in `agents/` with YAML frontmatter.

## First-Time Setup

Before using The Syndicate agents, initialize your persistent bankroll state:

```bash
./scripts/init-bankroll.sh
```

This creates `~/.syndicate/` and the SQLite database that all agents read from and write to. Without initialization, agents that rely on bankroll state will not function.

After setup, verify your state is ready:

```bash
./scripts/bankroll-status.sh
```

## Agent Format

All agents follow this structure:

- YAML frontmatter with `name` and `description`
- Identity & Expertise section (role, personality, domain, philosophy)
- Core Mission
- Tools & Data Sources (APIs, libraries, CLI tools)
- Operational Workflows (executable code examples)
- Deliverables (structured output templates)
- Decision Rules (hard constraints)
- Constraints & Disclaimers (responsible gambling — required in every agent)
- Communication Style

## Sport Context Requirement

**Always establish which sport you're analyzing before starting work. Never analyze "all sports" generically.**

Every agent operation — recording a bet, running a report, generating a recommendation — must be scoped to a specific sport. This is enforced at the data layer (`sports_config` table) and at the agent layer. A bet with `sport = 'ALL'` or a vague multi-sport sweep is invalid. Pick a sport, go deep.

## Persistent State — `~/.syndicate/`

All agents read from and write to the SQLite database at `~/.syndicate/bankroll.db`. This is the single source of truth for bankroll, bet history, agent performance, and learning state.

### Directory Structure

```
~/.syndicate/
└── bankroll.db        # SQLite database (all state lives here)
```

### Database Tables

| Table | Purpose |
|---|---|
| `bankroll_state` | Singleton row: current balance, starting balance, risk tolerance |
| `bets` | Full bet ledger with agent attribution, odds, stake, P&L, CLV |
| `daily_snapshots` | One row per day for equity curve rendering |
| `agent_performance` | Cached per-agent, per-sport ROI and win-rate stats |
| `sports_config` | Which sports are enabled and their max exposure limits |

### How Agents Should Use State

- **Before placing a bet**: read `bankroll_state` to confirm the sport is enabled in `sports_config` and the stake respects `default_max_exposure_pct`.
- **After recommending a bet**: record it via `State Manager` with `agent_used` set to your agent name.
- **After a game settles**: call the State Manager to settle the bet, which updates `bankroll_state`, refreshes `agent_performance`, and writes a `daily_snapshot`.
- **When asked for context**: read `agent_performance` for your agent+sport combination to understand your own recent performance before making recommendations.

## The Learning Feedback Loop

The Syndicate is designed to improve itself over time. The feedback loop works as follows:

1. **Agent recommends a bet** → bet recorded with `agent_used` attribution
2. **Game settles** → State Manager calculates P&L and CLV, updates `agent_performance`
3. **Rolling window analysis** → State Manager generates 30/60/90-day reports identifying which agent + sport combinations are profitable
4. **Feedback surfaces** → e.g., "Based on last 30 days, your NBA prop bets via Player Prop Analyst have +8.2% ROI while NFL sides via Market Maker are -3.1%"
5. **Agents self-adjust** → underperforming agents review their models; profitable agents stay the course

CLV (Closing Line Value) is the primary skill indicator. A positive ROI on negative CLV is luck and will regress. Positive CLV sustained over 50+ bets is genuine edge.

To generate a feedback report at any time:

```python
from state_manager import performance_report
print(performance_report(days=30))
```

## Environment Variables

Agents that call external APIs need keys set in the environment.

### Configuring API Keys for Claude Code

The recommended way to set API keys is via `.claude/settings.local.json` (gitignored, never committed):

```json
{
  "env": {
    "ODDS_API_KEY": "your_key_here"
  }
}
```

This makes the key available to Claude Code and all dispatched subagents. Keys set in `.zshrc` or `.bashrc` are **not** inherited by subagents — use `settings.local.json` instead.

Alternatively, see `.env.example` for the full list of keys (used by standalone CLI scripts).

### Required Keys

**Required:** `ODDS_API_KEY` (from the-odds-api.com, free tier available)

### Optional Keys

`CFBD_API_KEY`, `SPORTRADAR_API_KEY`, `ODDSJAM_API_KEY`, `SLACK_WEBHOOK_URL`, `PUSHOVER_USER_KEY`, `DISCORD_WEBHOOK_URL`

### No Key Needed

nba_api, nfl_data_py, pybaseball, Open-Meteo weather, ESPN injury API, Polymarket CLOB reads

## Execution Environments

- **Claude Code** (primary): Full capability — runs Python, calls APIs, reads/writes `~/.syndicate/`, chains agents
- **Claude Desktop**: Strategy discussion and reasoning only — no code execution, no API access, no file I/O
- **CLI scripts**: `scripts/bet.sh`, `scripts/init-bankroll.sh`, `scripts/bankroll-status.sh` run standalone in any terminal

Workflows in `workflows/` are designed for Claude Code. Each includes a "How to Run" section explaining what's possible in each environment.

## Conventions

- Agent files live in `agents/<category>/` subdirectories
- Workflow templates live in `workflows/`
- Data source references live in `data-sources/`
- All agents must include responsible gambling disclaimers
- Agents should reference real, publicly available APIs and tools
- Code examples should be executable (Python 3.10+, bash)
- Use sharp/professional betting terminology throughout
- The State Manager agent (`agents/bankroll/state-manager.md`) is the canonical interface for all database operations — agents should not write raw SQL against the database themselves

## Installation

Agents install to `~/.claude/agents/` via:

```bash
./scripts/install.sh
```
