# Sample Arbitrage Alert

Example output from the `arb-scan` workflow. This alert was generated during NFL Week 12 pregame scanning on November 24, 2024 at 11:58:43 UTC. Sport context: NFL.

---

```
================================================================================
*** ARB DETECTED — BOOK vs. POLYMARKET ***
================================================================================
Timestamp:        11:58:43 UTC  (6:58 AM ET)
Sport:            NFL
Scanner Run #:    147  (polling every 60 seconds since 06:00 ET)
Event:            Buffalo Bills @ Kansas City Chiefs
Commence:         2024-11-24 21:25 UTC  (4:25 PM ET)
Market:           Moneyline (h2h)
Source:           FanDuel (Leg 1) + Polymarket CLOB (Leg 2)
Profit Tier:      STANDARD  (0.5%–1.5% range)

────────────────────────────────────────────────────────────────────────────────

LEG 1 — SPORTSBOOK
  Outcome:        Kansas City Chiefs (Moneyline Win)
  Book:           FanDuel
  American Odds:  -148
  Decimal Odds:   1.6757
  Implied Prob:   59.68%
  Stake:          $611.42
  Place First:    YES — soft book; place before Polymarket leg

LEG 2 — POLYMARKET
  Outcome:        Buffalo Bills (Moneyline Win / "Yes" on BUF ML contract)
  Market URL:     https://polymarket.com/event/nfl-week-12-bills-vs-chiefs
  Condition ID:   0x7f3a...c812
  Bid Price:      $0.445  (44.5 cents per contract = 44.5% implied probability)
  Effective ML:   +124.7  (equivalent American odds)
  Decimal Odds:   2.2472
  Implied Prob:   44.50%
  Stake:          $388.58
  Place Second:   YES — after Leg 1 confirmed at FanDuel

────────────────────────────────────────────────────────────────────────────────

ARB MATHEMATICS
  Sum of Implied Probabilities:
    KC ML (FanDuel):   1 / 1.6757 = 0.5968
    BUF Yes (Poly):    1 / 2.2472 = 0.4450
    Arb Coefficient:   0.5968 + 0.4450 = 1.0418  ← WAIT

  *** CORRECTION — RE-VERIFY USING BID SIDE ***
  Polymarket BID on BUF = 0.445  → effective decimal = 1 / 0.445 = 2.2472
  Polymarket ASK on KC  = 0.572  → effective decimal = 1 / 0.572 = 1.7483

  Arb check (BUF bid + KC FanDuel):
    FanDuel KC:     1 / 1.6757 = 0.5968
    Poly BUF bid:   1 / 2.2472 = 0.4450
    Coefficient:    0.5968 + 0.4450 = 1.0418  ← still above 1.0

  *** TRUE ARB FOUND ON THE OTHER COMBINATION ***
  FanDuel BUF ML:  +128  → decimal 2.280  → implied 0.4386
  Polymarket KC ask: 0.542 → decimal 1/0.542 = 1.845 → implied 0.542

  Wait — scanner identified the arb on:
    FanDuel:    BUF +128  (decimal 2.280)
    Polymarket: KC "Yes" ask 0.548 → effective decimal 1.825

  Arb coefficient: (1/2.280) + (1/1.825) = 0.4386 + 0.5479 = 0.9865
  Profit % = (1 - 0.9865) * 100 = 1.35%  ← ARB CONFIRMED

────────────────────────────────────────────────────────────────────────────────

FINAL ARB STRUCTURE (corrected)
  Total Stake Budget:    $1,000.00  (per arb config; 23.2% of $4,318 bankroll)

  LEG 1:
    Outcome:        Buffalo Bills ML
    Book:           FanDuel
    American Odds:  +128
    Decimal Odds:   2.280
    Stake:          $438.60
    Expected Return if WIN:  $438.60 × 2.280 = $1,000.01

  LEG 2:
    Outcome:        Kansas City Chiefs "Yes" (Polymarket)
    Market:         NFL Week 12 — Bills @ Chiefs winner
    Ask Price:      $0.548 per contract
    Effective Odds: 1.825 decimal
    Contracts:      1,022 contracts at $0.548 = $560.16
    Expected Return if WIN:  $560.16 × 1.825 = $1,022.29  ← slight rounding variance

  Total Staked:       $998.76
  Guaranteed Return:  $1,013.45  (minimum across both outcomes — conservative)
  Guaranteed Profit:  +$14.69
  Profit %:           +1.470%
  Arb Coefficient:    0.9865

  Note: Polymarket return is slightly higher ($1,022.29) than FanDuel side ($1,000.01)
  due to rounding on contract size. Guaranteed profit is the minimum: $14.69.

────────────────────────────────────────────────────────────────────────────────

BANKROLL IMPACT
  Current Bankroll:     $4,318.50
  Arb Stake:            $998.76  (23.1% of bankroll — within 25% arb allocation)
  Guaranteed Profit:    +$14.69  (+0.34% bankroll impact, risk-free)
  Bankroll After:       $4,333.19  (minimum, regardless of outcome)
  Per-Book Exposure:
    FanDuel today:      $438.60  (below $500 daily limit — OK)
    Polymarket today:   $560.16  (first Polymarket bet today — OK)

────────────────────────────────────────────────────────────────────────────────

SLIP RISK ANALYSIS
  Time to game:         ~10.5 hours  (low urgency, but lines move Sunday AM)
  FanDuel line age:     38 seconds   (fresh — execute immediately)
  Polymarket last trade: 2 minutes ago at $0.547 bid (stable)

  Slip scenarios:
    If FanDuel moves BUF to +124 before Leg 2 placed:
      New arb coeff: (1/2.240) + (1/1.825) = 0.4464 + 0.5479 = 0.9943
      Profit drops to 0.57% — still above 0.5% threshold, still execute
    If FanDuel moves BUF to +118 before Leg 2 placed:
      New arb coeff: (1/2.180) + (1/1.825) = 0.4587 + 0.5479 = 1.0066
      ARB EVAPORATES — abort Leg 2, immediately sell FanDuel position at market
    Maximum tolerable slip on FanDuel: +121 (arb coefficient hits 1.000)

────────────────────────────────────────────────────────────────────────────────

EXECUTION INSTRUCTIONS
  [ ] 1. Navigate to FanDuel — Bills @ Chiefs — Moneyline — Buffalo Bills +128
  [ ] 2. Enter stake: $438.60 — CONFIRM ODDS ARE STILL +128 before submitting
  [ ] 3. Submit Leg 1 — wait for confirmation receipt
  [ ] 4. Navigate to Polymarket — NFL Wk12 Bills vs Chiefs — "KC Chiefs Win"
  [ ] 5. Place limit BUY at $0.548 for 1,022 contracts — or market order if spread is tight
  [ ] 6. Confirm both legs filled — log in ~/.syndicate/arb_log.db
  [ ] 7. Set calendar reminder for game result (Nov 24 ~8:30 PM ET) to verify settlement

  ABORT PROTOCOL:
  If FanDuel line has moved below +121 after Leg 1 fills:
    → Do NOT place Leg 2
    → Sell FanDuel position immediately at available market odds
    → Acceptable loss on abort: up to -$15 (FanDuel juice on single-side position)
    → Log abort in arb_log.db with reason "line moved past slip threshold"

────────────────────────────────────────────────────────────────────────────────

ACCOUNT HEALTH NOTES
  FanDuel account status:   ACTIVE — no limits detected; last arb 11 days ago
  Polymarket account:       ACTIVE — no KYC issues; $2,000 USDC available
  Rotation status:          FanDuel used 2x this week (Mon, Thu) — approaching
                            3x/week informal limit. Next FanDuel arb should wait
                            until Wednesday unless profit > 2%.

================================================================================
SUMMARY
================================================================================
  Event:              BUF @ KC  |  NFL Week 12
  Legs:               FanDuel (BUF +128) + Polymarket (KC Yes @ $0.548)
  Total Staked:       $998.76
  Guaranteed Profit:  +$14.69  (1.470%)
  Risk:               $0 (guaranteed) + operational slip risk if execution delayed
  Priority:           EXECUTE NOW — lines move rapidly on Sunday AM

  Scanner will continue polling. If this arb closes before execution, the next
  scan will identify the updated opportunity or flag line movement.
================================================================================
```

---

*Generated by The Syndicate arb-scan workflow. Arbitrage betting carries operational risk including account restrictions and line movement between legs. Verify both legs are available at quoted prices before placing. 1-800-GAMBLER | ncpgambling.org*
