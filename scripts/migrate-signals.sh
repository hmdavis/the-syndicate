#!/usr/bin/env bash
set -euo pipefail

# ── Migrate existing ~/.syndicate/bankroll.db to support bet signals ──
# Safe to run multiple times — all operations are idempotent.

DB_PATH="${SYNDICATE_DB:-$HOME/.syndicate/bankroll.db}"

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found at $DB_PATH"
    echo "Run ./scripts/init-bankroll.sh first."
    exit 1
fi

echo "Migrating $DB_PATH for bet signals support..."

# Add signals column if it doesn't exist
HAS_SIGNALS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM pragma_table_info('bets') WHERE name='signals';")
if [ "$HAS_SIGNALS" = "0" ]; then
    sqlite3 "$DB_PATH" "ALTER TABLE bets ADD COLUMN signals JSON;"
    echo "  Added 'signals' column to bets table."
else
    echo "  'signals' column already exists — skipping."
fi

# Create partial index
sqlite3 "$DB_PATH" "CREATE INDEX IF NOT EXISTS idx_bets_has_signals ON bets(sport) WHERE signals IS NOT NULL;"
echo "  Partial index idx_bets_has_signals ensured."

# Create/replace view
sqlite3 "$DB_PATH" <<'ENDSQL'
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
ENDSQL
echo "  bet_signals_v view created."

# Create signal_performance table
sqlite3 "$DB_PATH" <<'ENDSQL'
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
ENDSQL
echo "  signal_performance table ensured."

echo ""
echo "Migration complete. Existing bets have signals=NULL (excluded from signal analysis)."
echo "Signal tracking begins with the next pipeline run."
