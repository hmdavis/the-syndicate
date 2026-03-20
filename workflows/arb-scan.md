# Arb Scan Workflow

Continuous polling workflow: pull odds across books and Polymarket → detect arbitrage → find middles → size stakes → alert. Designed to run as a persistent background process.

---

## How to Run

### Claude Code (recommended)

Open Claude Code in the `the-syndicate` repo, select the **Sharp Orchestrator** or **Arb Scanner** agent, then prompt:

```
Run the arb scan workflow for NFL. Poll every 60 seconds, minimum 0.5% profit.
```

Claude Code will write and execute the polling loop, scan for arbs across books + Polymarket, and output structured alerts. It can also record found arbs to your bankroll state.

For a one-shot scan (no continuous polling):
```
Scan for NFL arbitrage opportunities right now across all books and Polymarket.
```

### Claude Desktop

Not directly supported. You can paste odds from multiple sportsbooks into Claude Desktop and ask it to check for arbs using the formulas in this doc, but it cannot poll APIs or maintain a persistent loop.

### CLI (standalone)

The code blocks in this doc and the agent files (`agents/arbitrage/arb-scanner.md`, `agents/arbitrage/middle-finder.md`) contain working Python. To run the scan loop independently:

```bash
pip install requests aiohttp
export ODDS_API_KEY=your_key_here

# Build a script from the code blocks in arb-scanner.md and this workflow,
# or prompt Claude Code to generate a standalone arb_scan.py for you.
```

To record arb bets:
```bash
./scripts/bet.sh place    # Leg 1
./scripts/bet.sh place    # Leg 2
```

---

## Sport Context

Set sport before launching. The scanner targets one sport per process instance. Run multiple instances for multi-sport coverage — one process per sport key.

```
SPORT_KEY: [americanfootball_nfl | basketball_nba | baseball_mlb | icehockey_nhl | ...]
POLL_INTERVAL: 60  # seconds between scans
BANKROLL_DB: ~/.syndicate/bankroll.db
MIN_PROFIT_PCT: 0.5  # minimum guaranteed profit % to alert
```

---

## Agents Involved

| Agent | Role | Output |
|-------|------|--------|
| `odds-scraper` | Pulls multi-book odds from The Odds API; fetches Polymarket CLOB | `odds_snapshot.json` |
| `arb-scanner` | Detects two-way and three-way arb conditions across books | `arbs_detected.json` |
| `middle-finder` | Scans for middling opportunities on spread divergence | `middles_detected.json` |
| `kelly-criterion` | Sizes arb stakes from bankroll; applies max per-book exposure limits | `arb_stakes.json` |

---

## Odds Sources

### Primary: The Odds API

```python
# Books covered (us region):
BOOKS_US = [
    "draftkings", "fanduel", "betmgm", "caesars", "pointsbet",
    "betrivers", "unibet", "wynnbet", "barstool", "espnbet",
]

# Markets scanned:
MARKETS = "h2h,spreads,totals"

# Endpoint:
GET https://api.the-odds-api.com/v4/sports/{sport_key}/odds
    ?apiKey={ODDS_API_KEY}
    &regions=us,uk,eu
    &markets={MARKETS}
    &oddsFormat=american
```

### Secondary: Polymarket CLOB API

Polymarket offers event contract markets on game outcomes (moneylines). These are prediction market prices, not sportsbook prices — they regularly diverge from book lines, creating arb windows.

```python
# Polymarket CLOB REST API (no auth required for reads)
POLYMARKET_BASE = "https://clob.polymarket.com"

# Fetch active NFL/NBA markets
GET {POLYMARKET_BASE}/markets?active=true&tag_slug=nfl

# Fetch best bid/ask for a specific market
GET {POLYMARKET_BASE}/book?token_id={condition_id}

# Price interpretation:
# Polymarket prices are 0–1 (probability).
# Convert to American moneyline for arb math:
def poly_prob_to_american(prob: float) -> float:
    if prob >= 0.5:
        return -(prob / (1 - prob)) * 100
    else:
        return ((1 - prob) / prob) * 100
```

**Polymarket integration notes:**
- Bid/ask spread on Polymarket is the effective juice. Use the BID price for "Yes" (buying the outcome) — this is what you can sell at if the bet loses its value.
- Polymarket settles on game result. No live withdrawal once position is open.
- Maximum effective size on Polymarket: ~$5,000 per position before significant market impact.
- Best arbs with Polymarket appear in the 30–60 minutes before game time when sportsbooks shade lines but Polymarket lags.

---

## Pipeline Steps

### Step 1 — Pull Odds Snapshot

Invoke **odds-scraper** to fetch current odds from all sources simultaneously.

```python
# Parallel fetch: The Odds API + Polymarket
odds_snap = {
    "sport_key":    SPORT_KEY,
    "fetched_at":   datetime.utcnow().isoformat(),
    "books":        fetch_odds_api(SPORT_KEY),       # odds-scraper
    "polymarket":   fetch_polymarket_markets(SPORT_KEY),  # odds-scraper
}
```

**Freshness gate:** If The Odds API snapshot is older than 120 seconds, re-fetch before scanning. Stale odds are worse than no odds — they produce phantom arbs that evaporate on execution.

---

### Step 2 — Run Arb Scanner

Invoke **arb-scanner** on the full odds snapshot. Scanner checks every book-vs-book combination and every book-vs-Polymarket combination.

```python
# arb-scanner logic:
# For each event, for each market (h2h, spreads, totals):
#   Find best price per outcome across all sources (books + Polymarket)
#   Calculate arb_pct = sum(1/decimal_odds_i for each outcome)
#   If arb_pct < 1.0: arb exists. Profit % = (1 - arb_pct) * 100
#   If profit_pct >= MIN_PROFIT_PCT: add to arbs_detected
```

**Polymarket arb check:**
```python
# Example: DraftKings has KC -160, Polymarket has BUF Yes @ 0.43 (implied +132)
# Leg 1: KC ML @ DraftKings -160 (decimal 1.625)
# Leg 2: BUF Yes @ Polymarket bid 0.43 → decimal 1/0.43 = 2.326
# arb_pct = 1/1.625 + 1/2.326 = 0.615 + 0.430 = 1.045  → NO ARB
# If BUF bid were 0.47: 1/1.625 + 1/(1/0.47) = 0.615 + 0.470 = 1.085 → still no
# True arb requires arb_pct < 1.0 — Polymarket must offer better than no-vig parity
```

Output: `arbs_detected.json` with all qualifying arbs sorted by `profit_pct` descending.

---

### Step 3 — Run Middle Finder

Invoke **middle-finder** on the spread data. Middles differ from arbs: you win both legs if the final margin lands in the middle window.

```python
# middle-finder logic:
# For each event's spread market:
#   Find the highest available number on Team A (e.g., +7.5 at FanDuel)
#   Find the lowest available number on Team B (e.g., -6.5 at DraftKings)
#   If (best_dog_spread - best_fav_spread) > 0: middle window exists
#   Middle window = [best_fav_spread, best_dog_spread]
#   Width = best_dog_spread - best_fav_spread (e.g., 1.0 pt = narrow middle)
#   EV calculation: P(middle lands) * (win_both_legs profit) - P(push one leg) * (lose one leg)
```

Middle alert threshold:
- NFL: window ≥ 1.0 point, centered on a key number (3, 7, 10, 14) → high priority
- NBA: window ≥ 2.0 points, centered on 5 or 7
- MLB: middle on run line is rare; filter to ≥ 0.5 run window

---

### Step 4 — Load Bankroll and Size Stakes

Read bankroll from `~/.syndicate/bankroll.db`. Calculate arb stakes using **kelly-criterion**'s arb sizing module.

```python
# For arbs: stake distribution to guarantee equal profit on all outcomes
# kelly-criterion handles arb sizing differently than edge bets:
# No Kelly fraction — arb profit is locked in. Stake = total_arb_budget / arb_pct.
# total_arb_budget = min(max_arb_stake, available_bankroll * arb_allocation_pct)

ARB_ALLOCATION_PCT = 0.15  # max 15% of current bankroll per arb
MAX_ARB_STAKE = 1000.0     # hard cap per arb execution

# Per-book exposure limit (account health):
MAX_PER_BOOK_PER_DAY = 500.0
```

---

### Step 5 — Alert

For each arb above threshold, emit a structured alert (see format below) and log to `~/.syndicate/arb_log.db`.

Alert channels (configure in `.env`):
- Terminal: always
- Slack webhook: if `SLACK_WEBHOOK_URL` is set
- Pushover mobile: if `PUSHOVER_TOKEN` is set

```bash
# Execution priority: place soft book first, sharp book second
# Soft books (recreational, higher slip risk): DraftKings, FanDuel, BetMGM, Caesars
# Sharp books (lower slip risk, harder to limit): Pinnacle, Circa, BetOnline
# Polymarket: place last — no line movement risk but settlement delay
```

---

## Arb Alert Format

```
================================================================================
*** ARB DETECTED ***
================================================================================
Timestamp:        [HH:MM:SS UTC]
Sport:            [NFL / NBA / MLB / NHL]
Event:            [Away] @ [Home]
Commence:         [YYYY-MM-DD HH:MM ET]
Market:           [h2h / spreads / totals]
Source:           [book-vs-book / book-vs-polymarket]

LEG 1:
  Outcome:        [Team A / Over / Yes]
  Book:           [DraftKings]
  Odds:           [+130] (decimal 2.300)
  Stake:          $[XXX.XX]
  Place First:    YES — soft book, place immediately

LEG 2:
  Outcome:        [Team B / Under / No]
  Book:           [Pinnacle / Polymarket]
  Odds:           [-115] (decimal 1.870) / [0.54 bid]
  Stake:          $[XXX.XX]
  Place Second:   YES — after Leg 1 confirmed

SUMMARY:
  Total Staked:         $[X,XXX.XX]
  Guaranteed Profit:    +$[XX.XX]
  Profit %:             [X.XXX%]
  Arb Coefficient:      [0.9XX]
  Bankroll Allocation:  [X.X%] of current $[X,XXX]
  Max Slip Risk:        $[X.XX] if 1 line moves 1 tick

EXECUTION:
  [ ] Place Leg 1 at [Book] — confirm fill before Leg 2
  [ ] Place Leg 2 at [Book] within 60 seconds of Leg 1
  [ ] Re-verify both lines have not moved before placing Leg 2
  [ ] Log execution in ~/.syndicate/arb_log.db
================================================================================
```

---

## Middle Alert Format

```
================================================================================
*** MIDDLE OPPORTUNITY ***
================================================================================
Event:            [Away] @ [Home]
Market:           Spread
Middle Window:    [+6.5] to [+7.5] — 1.0-point window centered on 7 (KEY NUMBER)

LEG 1:  [Home] -6.5 @ [DraftKings]  -110  |  Stake: $[XXX]
LEG 2:  [Away] +7.5 @ [FanDuel]     -110  |  Stake: $[XXX]

Scenarios:
  Win both:  Final margin = exactly 7 → +$[XXX.XX] (both legs win)
  Win one:   Final margin ≠ 6–7 → -$[XX.XX] (standard single-side loss)
  Push one:  Final margin = 6.5 or 7.5 → roughly break even

Middle EV (assuming 12% P(middle) on key number 7):
  EV = 0.12 * $XX + 0.88 * (-$XX) = [+/- $X.XX]
================================================================================
```

---

## Continuous Poll Loop

```python
while True:
    snap = fetch_odds_snapshot(SPORT_KEY)             # odds-scraper
    arbs = arb_scanner.scan(snap)                     # arb-scanner
    middles = middle_finder.scan(snap)                # middle-finder
    sized = kelly_criterion.size_arbs(arbs, bankroll) # kelly-criterion

    for arb in sized:
        emit_alert(arb)
        log_arb(arb, "~/.syndicate/arb_log.db")

    for middle in middles:
        emit_middle_alert(middle)

    sleep(POLL_INTERVAL)
```

---

## Constraints

- Never hold a single-sided position. If Leg 1 fills and Leg 2 moves out of arb range, exit Leg 1 immediately at market.
- Do not arb the same game on the same book more than 3 times per week — account longevity matters more than any single arb.
- Polymarket legs require 30-second confirmation of order fill before Leg 1 is placed on the sportsbook side.
- Three-way arbs (soccer h2h): minimum profit threshold is 1.0% — added complexity and three-leg slip risk demands higher floor.
- Log every detected arb regardless of execution. Pattern analysis of missed arbs reveals optimal poll intervals and book combinations.
