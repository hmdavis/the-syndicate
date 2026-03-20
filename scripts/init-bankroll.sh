#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# The Syndicate — Bankroll Initialization Script
# Creates ~/.syndicate/ and initializes the SQLite state DB
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SYNDICATE_DIR="$HOME/.syndicate"
DB_PATH="$SYNDICATE_DIR/bankroll.db"

echo -e "${BOLD}${CYAN}"
echo "  ████████╗██╗  ██╗███████╗    ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗ ██████╗ █████╗ ████████╗███████╗"
echo "     ██╔══╝██║  ██║██╔════╝    ██╔════╝╚██╗ ██╔╝████╗  ██║██╔══██╗██║██╔════╝██╔══██╗╚══██╔══╝██╔════╝"
echo "     ██║   ███████║█████╗      ███████╗ ╚████╔╝ ██╔██╗ ██║██║  ██║██║██║     ███████║   ██║   █████╗  "
echo "     ██║   ██╔══██║██╔══╝      ╚════██║  ╚██╔╝  ██║╚██╗██║██║  ██║██║██║     ██╔══██║   ██║   ██╔══╝  "
echo "     ██║   ██║  ██║███████╗    ███████║   ██║   ██║ ╚████║██████╔╝██║╚██████╗██║  ██║   ██║   ███████╗"
echo "     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝"
echo -e "${NC}"
echo -e "${BOLD}  Bankroll State Initialization${NC}"
echo "  ─────────────────────────────────────────"
echo ""

# ── Guard: already initialized ──────────────────────────────
if [[ -f "$DB_PATH" ]]; then
    echo -e "${YELLOW}Warning:${NC} A bankroll database already exists at ${BOLD}$DB_PATH${NC}"
    echo ""
    read -rp "  Re-initialize and ERASE existing data? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}No changes made.${NC} Run ${BOLD}bankroll-status.sh${NC} to view current state."
        exit 0
    fi
    echo ""
fi

# ── Step 1: Starting bankroll ────────────────────────────────
echo -e "${BOLD}Step 1 of 3 — Starting Bankroll${NC}"
while true; do
    read -rp "  Enter your starting bankroll amount (\$): " raw_bankroll
    # Strip leading $ if provided
    raw_bankroll="${raw_bankroll#\$}"
    raw_bankroll="${raw_bankroll//,/}"  # remove commas
    if [[ "$raw_bankroll" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]] && (( $(echo "$raw_bankroll > 0" | bc -l) )); then
        STARTING_BANKROLL="$raw_bankroll"
        break
    else
        echo -e "  ${RED}Invalid amount.${NC} Please enter a positive number (e.g. 1000 or 2500.00)"
    fi
done
echo ""

# ── Step 2: Risk tolerance ───────────────────────────────────
echo -e "${BOLD}Step 2 of 3 — Risk Tolerance${NC}"
echo "  Controls default unit sizing and max single-bet exposure."
echo ""
echo "    1) conservative  — 1% max per bet, 5% max exposure per sport"
echo "    2) moderate      — 2% max per bet, 10% max exposure per sport"
echo "    3) aggressive    — 3% max per bet, 20% max exposure per sport"
echo ""
while true; do
    read -rp "  Choose risk tolerance [1/2/3 or name]: " risk_input
    case "${risk_input,,}" in
        1|conservative) RISK_TOLERANCE="conservative"; break ;;
        2|moderate)     RISK_TOLERANCE="moderate";     break ;;
        3|aggressive)   RISK_TOLERANCE="aggressive";   break ;;
        *) echo -e "  ${RED}Invalid choice.${NC} Enter 1, 2, 3, conservative, moderate, or aggressive." ;;
    esac
done
echo ""

# ── Step 3: Sports of interest ───────────────────────────────
echo -e "${BOLD}Step 3 of 3 — Sports of Interest${NC}"
echo "  Available sports:"
echo ""
echo "    NFL    NCAAF   NBA    NCAAB"
echo "    MLB    NHL     MLS    WNBA"
echo "    UFC    TENNIS  GOLF   BOXING"
echo ""
echo "  Enter sports separated by spaces or commas (e.g. NFL NBA MLB)."
echo "  Press ENTER with no input to enable all sports."
echo ""
read -rp "  Sports: " sports_input

if [[ -z "$sports_input" ]]; then
    SPORTS_LIST="NFL NCAAF NBA NCAAB MLB NHL MLS WNBA UFC TENNIS GOLF BOXING"
    echo "  Enabling all sports."
else
    # Normalize: uppercase, replace commas with spaces, collapse whitespace
    SPORTS_LIST=$(echo "$sports_input" | tr ',' ' ' | tr '[:lower:]' '[:upper:]' | tr -s ' ')
fi

echo ""

# ── Create directory ─────────────────────────────────────────
mkdir -p "$SYNDICATE_DIR"

# ── Build SQLite database ─────────────────────────────────────
echo -e "${BOLD}Initializing database...${NC}"

# Remove existing DB if re-initializing
[[ -f "$DB_PATH" ]] && rm -f "$DB_PATH"

sqlite3 "$DB_PATH" <<'ENDSQL'
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- ── bankroll_state ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bankroll_state (
    id                  INTEGER PRIMARY KEY CHECK (id = 1),  -- singleton row
    current_balance     REAL    NOT NULL,
    starting_balance    REAL    NOT NULL,
    risk_tolerance      TEXT    NOT NULL CHECK (risk_tolerance IN ('conservative','moderate','aggressive')),
    created_at          TEXT    NOT NULL DEFAULT (datetime('now','utc')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now','utc'))
);

-- ── bets ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    sport           TEXT    NOT NULL,
    game            TEXT    NOT NULL,          -- "Chiefs vs Ravens"
    market          TEXT    NOT NULL,          -- spread|moneyline|total|prop|parlay|futures
    selection       TEXT    NOT NULL,          -- "Chiefs -3.5"
    odds            INTEGER NOT NULL,          -- American odds, e.g. -110
    stake           REAL    NOT NULL,          -- dollars wagered
    result          TEXT    CHECK (result IN ('WIN','LOSS','PUSH','VOID','PENDING')),
    pnl             REAL,                      -- net dollar P&L (null until settled)
    clv             REAL,                      -- closing line value in cents
    placed_at       TEXT    NOT NULL DEFAULT (datetime('now','utc')),
    settled_at      TEXT,
    agent_used      TEXT,                      -- which Syndicate agent recommended this
    confidence      REAL    CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    notes           TEXT,
    signals         JSON                       -- structured decision-point signals (pipeline bets only)
);

CREATE INDEX IF NOT EXISTS idx_bets_sport       ON bets(sport);
CREATE INDEX IF NOT EXISTS idx_bets_result      ON bets(result);
CREATE INDEX IF NOT EXISTS idx_bets_placed_at   ON bets(placed_at);
CREATE INDEX IF NOT EXISTS idx_bets_agent_used  ON bets(agent_used);
CREATE INDEX IF NOT EXISTS idx_bets_has_signals ON bets(sport) WHERE signals IS NOT NULL;

-- ── daily_snapshots ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_snapshots (
    date        TEXT    PRIMARY KEY,   -- YYYY-MM-DD
    balance     REAL    NOT NULL,
    total_bets  INTEGER NOT NULL DEFAULT 0,
    wins        INTEGER NOT NULL DEFAULT 0,
    losses      INTEGER NOT NULL DEFAULT 0,
    pushes      INTEGER NOT NULL DEFAULT 0,
    roi_pct     REAL    NOT NULL DEFAULT 0
);

-- ── agent_performance ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_performance (
    agent_name  TEXT    NOT NULL,
    sport       TEXT    NOT NULL,
    total_bets  INTEGER NOT NULL DEFAULT 0,
    win_rate    REAL    NOT NULL DEFAULT 0,
    roi_pct     REAL    NOT NULL DEFAULT 0,
    avg_clv     REAL,
    last_used   TEXT,
    PRIMARY KEY (agent_name, sport)
);

-- ── bet_signals_v (extracted view for signal queries) ────
DROP VIEW IF EXISTS bet_signals_v;
CREATE VIEW bet_signals_v AS
SELECT
    b.id              AS bet_id,
    b.sport,
    b.agent_used,
    b.result,
    b.pnl,
    b.stake,
    b.clv,
    b.placed_at,
    json_extract(b.signals, '$.model_edge_pct')       AS model_edge_pct,
    json_extract(b.signals, '$.fair_value')            AS fair_value,
    json_extract(b.signals, '$.model_conflict')        AS model_conflict,
    json_extract(b.signals, '$.conflict_pts')          AS conflict_pts,
    json_extract(b.signals, '$.best_available_line')   AS best_available_line,
    json_extract(b.signals, '$.books_pricing')         AS books_pricing,
    json_extract(b.signals, '$.kelly_fraction')        AS kelly_fraction,
    json_extract(b.signals, '$.thin_market')           AS thin_market,
    json_extract(b.signals, '$.human_override')        AS human_override
FROM bets b
WHERE b.signals IS NOT NULL;

-- ── signal_performance (cached signal-level stats) ───────
CREATE TABLE IF NOT EXISTS signal_performance (
    signal_name     TEXT    NOT NULL,
    signal_bucket   TEXT    NOT NULL,
    sport           TEXT    NOT NULL,
    total_bets      INTEGER NOT NULL DEFAULT 0,
    win_rate        REAL    NOT NULL DEFAULT 0,
    roi_pct         REAL    NOT NULL DEFAULT 0,
    avg_clv         REAL,
    last_updated    TEXT,
    PRIMARY KEY (signal_name, signal_bucket, sport)
);

-- ── sports_config ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sports_config (
    sport                   TEXT    PRIMARY KEY,
    enabled                 INTEGER NOT NULL DEFAULT 1,   -- boolean
    default_max_exposure_pct REAL   NOT NULL DEFAULT 10.0
);
ENDSQL

# ── Seed bankroll_state ───────────────────────────────────────
sqlite3 "$DB_PATH" \
    "INSERT INTO bankroll_state (id, current_balance, starting_balance, risk_tolerance)
     VALUES (1, $STARTING_BANKROLL, $STARTING_BANKROLL, '$RISK_TOLERANCE');"

# ── Set max_exposure_pct based on risk tolerance ──────────────
case "$RISK_TOLERANCE" in
    conservative) MAX_EXPOSURE=5.0  ;;
    moderate)     MAX_EXPOSURE=10.0 ;;
    aggressive)   MAX_EXPOSURE=20.0 ;;
esac

# ── Seed sports_config ────────────────────────────────────────
ALL_SPORTS="NFL NCAAF NBA NCAAB MLB NHL MLS WNBA UFC TENNIS GOLF BOXING"
for sport in $ALL_SPORTS; do
    if echo "$SPORTS_LIST" | grep -qw "$sport"; then
        enabled=1
    else
        enabled=0
    fi
    sqlite3 "$DB_PATH" \
        "INSERT INTO sports_config (sport, enabled, default_max_exposure_pct)
         VALUES ('$sport', $enabled, $MAX_EXPOSURE);"
done

# ── Write today's opening snapshot ───────────────────────────
TODAY=$(date +%Y-%m-%d)
sqlite3 "$DB_PATH" \
    "INSERT OR REPLACE INTO daily_snapshots (date, balance, total_bets, wins, losses, pushes, roi_pct)
     VALUES ('$TODAY', $STARTING_BANKROLL, 0, 0, 0, 0, 0.0);"

# ── Print summary ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Success! The Syndicate bankroll state initialized.${NC}"
echo ""
echo -e "  ${BOLD}Directory${NC}        $SYNDICATE_DIR/"
echo -e "  ${BOLD}Database${NC}         $DB_PATH"
echo ""
echo -e "  ${BOLD}Starting Balance${NC} \$$STARTING_BANKROLL"
echo -e "  ${BOLD}Risk Tolerance${NC}   $RISK_TOLERANCE (max ${MAX_EXPOSURE}% exposure per sport)"
echo -e "  ${BOLD}Sports Enabled${NC}   $SPORTS_LIST"
echo ""
echo "  Tables created:"
echo "    bankroll_state    — singleton row tracking current balance"
echo "    bets              — full bet ledger with agent attribution"
echo "    daily_snapshots   — daily equity curve data"
echo "    agent_performance — per-agent ROI and win-rate tracking"
echo "    sports_config     — enabled sports and exposure limits"
echo ""
echo -e "  Run ${BOLD}./scripts/bankroll-status.sh${NC} at any time to view your dashboard."
echo ""
