# Arb Scan Workflow

> **Hybrid pipeline:** Claude Code auto-chains agents and surfaces checkpoints
> between steps. Supports one-shot scans and continuous polling mode.

## How to Run

Activate the **Sharp Orchestrator** agent in Claude Code and prompt:

    Run the arb scan workflow for [SPORT]. Poll every 60 seconds, minimum 0.5% profit.

For a one-shot scan (no continuous polling):

    Scan for [SPORT] arbitrage opportunities right now across all books and Polymarket.

The orchestrator reads this workflow and executes each step.

## Inputs

- `{sport}` — The Odds API sport key (e.g., `americanfootball_nfl`, `basketball_nba`)
- `{poll_interval}` — Seconds between scans in continuous mode (default: 60)
- `{min_profit_pct}` — Minimum guaranteed profit % to alert (default: 0.5)

## Agents Involved

| Step | Agent | Role |
|------|-------|------|
| 1 | Odds Scraper | Pull multi-book odds + Polymarket CLOB |
| 2 | Arb Scanner | Detect two-way and three-way arb conditions |
| 3 | Middle Finder | Scan for middling opportunities on spread divergence |
| 4 | Kelly Criterion Manager | Size arb stakes from bankroll |
| 5 | (orchestrator) | Emit alerts and log to database |

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
# Polymarket prices are 0-1 (probability).
# Convert to American moneyline for arb math:
def poly_prob_to_american(prob: float) -> float:
    if prob >= 0.5:
        return -(prob / (1 - prob)) * 100
    else:
        return ((1 - prob) / prob) * 100
```

**Polymarket integration notes:**
- Bid/ask spread on Polymarket is the effective juice. Use the BID price for "Yes" (buying the outcome).
- Polymarket settles on game result. No live withdrawal once position is open.
- Maximum effective size: ~$5,000 per position before significant market impact.
- Best arbs appear 30-60 minutes before game time when sportsbooks shade lines but Polymarket lags.

---

## Step 1 — Odds Scraper

**Agent:** Odds Scraper
**Depends on:** none
**Dispatch mode:** foreground

**Purpose:** Pull current odds from all sportsbooks and Polymarket simultaneously.

**Dispatch prompt:**
> Activate Odds Scraper. Pull current odds for {sport} from The Odds
> API. Use the `ODDS_API_KEY` environment variable. Markets: h2h,
> spreads, totals. Regions: us, uk, eu. Odds format: american. Also
> fetch Polymarket CLOB prices for any matching {sport} event
> contracts. Return a unified odds snapshot with: each game, each
> book's prices (including Polymarket converted to American odds),
> and a fetch timestamp. Flag the snapshot timestamp — if older than
> 120 seconds, it must be re-fetched before scanning.

**Expected output:** Unified odds snapshot across all books + Polymarket with timestamps per game.

**Checkpoint:**

    Odds snapshot: N games, N books + Polymarket | Timestamp: HH:MM:SS UTC
    Freshness: OK (< 120s) or STALE (re-fetch required)
    Proceed? (yes / re-fetch / halt)

---

## Step 2 — Arb Scanner

**Agent:** Arb Scanner
**Depends on:** Step 1 (fresh snapshot)
**Dispatch mode:** foreground

**Purpose:** Detect guaranteed-profit arbitrage opportunities across all book combinations.

**Dispatch prompt:**
> Activate Arb Scanner. Scan this odds snapshot for arbitrage
> opportunities: {odds_snapshot}. For each event and market (h2h,
> spreads, totals), find the best price per outcome across all
> sources (sportsbooks + Polymarket). Calculate arb coefficient as
> sum(1/decimal_odds_i) for each outcome set. If coefficient < 1.0,
> an arb exists with profit % = (1 - coefficient) * 100. Include
> book-vs-book and book-vs-Polymarket combinations. Filter to arbs
> with profit >= {min_profit_pct}%. Output all qualifying arbs
> sorted by profit % descending. For three-way markets (soccer h2h),
> apply 1.0% minimum profit threshold.

**Expected output:** List of qualifying arbs with event, market, legs (outcome + book + odds), arb coefficient, and profit %.

**Checkpoint:**

    Arbs found: N qualifying (profit >= {min_profit_pct}%)
    Top arb: [event] [market] — [profit]% guaranteed
    Sources: N book-vs-book, N book-vs-Polymarket
    Proceed? (yes / skip to middles / halt)

---

## Step 3 — Middle Finder

**Agent:** Middle Finder
**Depends on:** Step 1 (odds snapshot)
**Dispatch mode:** foreground

**Purpose:** Identify middling opportunities where spread divergence creates a window to win both sides.

**Dispatch prompt:**
> Activate Middle Finder. Scan the spread data from this odds
> snapshot: {odds_snapshot}. For each event, find the highest
> available dog number and lowest available favorite number across
> all books. If (best_dog_spread - best_fav_spread) > 0, a middle
> window exists. Calculate the middle width, identify if it's
> centered on a key number (NFL: 3, 7, 10, 14; NBA: 5, 7), and
> estimate the EV based on historical probability of landing in the
> window. Filter by sport-specific thresholds: NFL >= 1.0 point
> window, NBA >= 2.0 points, MLB >= 0.5 runs.

**Expected output:** List of middle opportunities with event, window, key number flag, legs (book + spread + odds), and estimated EV.

**Checkpoint:**

    Middles found: N opportunities
    Top middle: [event] — [spread range] ([width] pt window, key number: [yes/no])
    Proceed to sizing? (yes / skip / halt)

---

## Step 4 — Kelly Criterion Manager (Arb Sizing)

**Agent:** Kelly Criterion Manager
**Depends on:** Steps 2 + 3 + bankroll state
**Dispatch mode:** foreground

**Purpose:** Size arb and middle stakes from current bankroll with per-book exposure limits.

**Dispatch prompt:**
> Activate Kelly Criterion Manager. Size stakes for the following
> arb and middle opportunities. Read bankroll from
> ~/.syndicate/bankroll.db. For arbs, use guaranteed-profit sizing
> (not Kelly fraction — arbs have locked profit). Allocate max 15%
> of current bankroll per arb execution, hard cap $1,000 per arb.
> Enforce per-book daily exposure limit of $500. For middles, size
> based on EV using quarter-Kelly with the estimated middle
> probability. Arbs: {arbs_detected}. Middles: {middles_detected}.
> Output: per-leg stakes, total staked, guaranteed profit (arbs) or
> expected profit (middles), and remaining per-book exposure.

**Expected output:** Sized arb and middle stakes with per-leg dollar amounts, total exposure, and profit calculations.

**Checkpoint:**

    Arbs sized: N | Total staked: $X | Guaranteed profit: $X
    Middles sized: N | Total staked: $X | Expected profit: $X
    Per-book exposure: [book]: $X/$500 remaining
    Execute? (yes / adjust / skip [arb/middle] / halt)

---

## Step 5 — Alert and Log (no agent dispatch)

**Depends on:** Step 4

**Purpose:** Emit structured alerts and log all detected opportunities.

**Action:** For each sized arb and middle, emit a structured alert using the formats below. Log every detected opportunity (executed or not) to `~/.syndicate/bankroll.db` via State Manager.

**Execution priority:** Place soft book leg first (DraftKings, FanDuel, BetMGM, Caesars), sharp book second (Pinnacle, Circa, BetOnline), Polymarket last.

**Checkpoint:**

    Alerts emitted: N arbs, N middles
    Logged to database: N opportunities
    Next scan in {poll_interval} seconds (continuous mode) or DONE (one-shot)

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
  [ ] Log execution in ~/.syndicate/bankroll.db
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
  Win one:   Final margin ≠ 6-7 → -$[XX.XX] (standard single-side loss)
  Push one:  Final margin = 6.5 or 7.5 → roughly break even

Middle EV (assuming 12% P(middle) on key number 7):
  EV = 0.12 * $XX + 0.88 * (-$XX) = [+/- $X.XX]
================================================================================
```

---

## Continuous Poll Loop

In continuous mode, the orchestrator repeats Steps 1-5 every `{poll_interval}` seconds. Between cycles:

    Cycle N complete | Arbs: X found, X sized | Middles: X found
    Next scan in {poll_interval}s | Total cycles: N | Session arbs: X
    Continue polling? (yes / pause / halt)

---

## Intervention Commands

Available at any checkpoint:

| Command | Effect |
|---------|--------|
| `yes` / Enter | Proceed to next step |
| `halt` | Stop the pipeline / polling |
| `re-fetch` | Re-pull odds (if stale) |
| `skip [arb/middle]` | Exclude a specific opportunity |
| `adjust` | Override stake sizing |
| `pause` | Pause continuous polling (resume with "yes") |

---

## Decision Rules

- **120-second freshness gate.** If odds snapshot is older than 120 seconds, re-fetch before scanning. Stale odds produce phantom arbs.
- **Minimum profit floor.** Only alert on arbs with profit >= `{min_profit_pct}%` (default 0.5%).
- **Three-way arb floor.** Soccer h2h (three outcomes) requires minimum 1.0% profit — added complexity and three-leg slip risk.
- **Per-book daily exposure.** Max $500 per book per day to preserve account longevity.
- **Same-game cap.** Do not arb the same game on the same book more than 3 times per week.
- **Polymarket fill confirmation.** Polymarket legs require 30-second confirmation of order fill before placing the sportsbook leg.
- **Single-sided position prohibition.** Never hold a single-sided position. If Leg 1 fills and Leg 2 moves out of arb range, exit Leg 1 immediately at market.
- **15% bankroll allocation cap.** Max 15% of current bankroll per arb execution, hard cap $1,000.
- **Log everything.** Log every detected arb regardless of execution — pattern analysis reveals optimal poll intervals and book combinations.

---

## Constraints & Disclaimers

This system is for **educational and research purposes only**. Output is based on mathematical models and real-time odds data. It is not a guarantee of profit and should not be construed as financial or gambling advice.

- Arb opportunities can disappear in seconds. Line movement between legs creates slip risk.
- Sports betting involves substantial risk of loss.
- Bet only what you can afford to lose entirely.
- **Problem gambling resources:** 1-800-522-4700 | ncpgambling.org
