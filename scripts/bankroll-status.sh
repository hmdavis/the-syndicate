#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# The Syndicate — Bankroll Status Dashboard
# Reads ~/.syndicate/bankroll.db and renders a terminal report
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

DB_PATH="$HOME/.syndicate/bankroll.db"

# ── Guard: DB must exist ─────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
    echo -e "${RED}${BOLD}No bankroll database found.${NC}"
    echo ""
    echo "  Expected: $DB_PATH"
    echo ""
    echo "  Run ${BOLD}./scripts/init-bankroll.sh${NC} to initialize your bankroll."
    exit 1
fi

# ── Helper: query with no header ─────────────────────────────
q() { sqlite3 "$DB_PATH" "$1"; }

# ── Helper: format number with sign ──────────────────────────
fmt_pnl() {
    local val="$1"
    local rounded
    rounded=$(printf "%.2f" "$val")
    if (( $(echo "$val >= 0" | bc -l) )); then
        echo "+\$$rounded"
    else
        echo "-\$${rounded#-}"
    fi
}

fmt_pct() {
    local val="$1"
    local rounded
    rounded=$(printf "%.2f" "$val")
    if (( $(echo "$val >= 0" | bc -l) )); then
        echo "+${rounded}%"
    else
        echo "${rounded}%"
    fi
}

color_pnl() {
    local val="$1"
    local formatted
    formatted=$(fmt_pnl "$val")
    if (( $(echo "$val >= 0" | bc -l) )); then
        echo -e "${GREEN}${formatted}${NC}"
    else
        echo -e "${RED}${formatted}${NC}"
    fi
}

color_pct() {
    local val="$1"
    local formatted
    formatted=$(fmt_pct "$val")
    if (( $(echo "$val >= 0" | bc -l) )); then
        echo -e "${GREEN}${formatted}${NC}"
    else
        echo -e "${RED}${formatted}${NC}"
    fi
}

# ── Fetch bankroll state ──────────────────────────────────────
read -r current_balance starting_balance risk_tolerance created_at <<< \
    "$(q "SELECT current_balance, starting_balance, risk_tolerance, created_at FROM bankroll_state WHERE id=1;" | tr '|' ' ')"

if [[ -z "$current_balance" ]]; then
    echo -e "${RED}Bankroll state table is empty. Run init-bankroll.sh.${NC}"
    exit 1
fi

total_pnl=$(echo "$current_balance - $starting_balance" | bc -l)
roi_pct=$(echo "scale=4; ($total_pnl / $starting_balance) * 100" | bc -l)

# ── Overall bet stats ─────────────────────────────────────────
read -r total_bets wins losses pushes pending <<< \
    "$(q "SELECT
            COUNT(*),
            SUM(CASE WHEN result='WIN'  THEN 1 ELSE 0 END),
            SUM(CASE WHEN result='LOSS' THEN 1 ELSE 0 END),
            SUM(CASE WHEN result='PUSH' THEN 1 ELSE 0 END),
            SUM(CASE WHEN result='PENDING' OR result IS NULL THEN 1 ELSE 0 END)
          FROM bets;" | tr '|' ' ')"

total_bets="${total_bets:-0}"
wins="${wins:-0}"
losses="${losses:-0}"
pushes="${pushes:-0}"
pending="${pending:-0}"

settled=$(( wins + losses + pushes ))
if (( settled > 0 )); then
    win_rate=$(echo "scale=4; ($wins / ($wins + $losses + $pushes)) * 100" | bc -l)
else
    win_rate="0"
fi

total_wagered=$(q "SELECT COALESCE(SUM(stake), 0) FROM bets WHERE result IN ('WIN','LOSS','PUSH');")
total_wagered="${total_wagered:-0}"

# ── HEADER ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║         THE SYNDICATE — BANKROLL DASHBOARD               ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── SECTION 1: Summary ───────────────────────────────────────
echo -e "${BOLD}${BLUE}▸ PORTFOLIO SUMMARY${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
printf "  %-24s %s\n"   "Current Balance:"    "$(echo -e "${BOLD}\$$current_balance${NC}")"
printf "  %-24s %s\n"   "Starting Balance:"   "\$$starting_balance"
printf "  %-24s %s\n"   "Total P&L:"          "$(color_pnl "$total_pnl")"
printf "  %-24s %s\n"   "Overall ROI:"        "$(color_pct "$roi_pct")"
printf "  %-24s %s\n"   "Risk Tolerance:"     "${BOLD}${risk_tolerance}${NC}"
printf "  %-24s %s\n"   "Initialized:"        "$created_at"
echo ""

# ── SECTION 2: Bet Record ─────────────────────────────────────
echo -e "${BOLD}${BLUE}▸ BET RECORD${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
printf "  %-24s %s\n"   "Total Bets:"         "$total_bets"
printf "  %-24s %s\n"   "Win / Loss / Push:"  "${GREEN}${wins}W${NC} / ${RED}${losses}L${NC} / ${YELLOW}${pushes}P${NC}"
printf "  %-24s %s\n"   "Pending:"            "$pending"
printf "  %-24s %s\n"   "Win Rate:"           "$(color_pct "$win_rate")"
printf "  %-24s %s\n"   "Total Wagered:"      "\$$total_wagered"
echo ""

# ── SECTION 3: Recent Bets (last 10) ─────────────────────────
echo -e "${BOLD}${BLUE}▸ RECENT BETS (LAST 10)${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
printf "  ${BOLD}%-6s %-8s %-26s %-12s %8s %8s %s${NC}\n" \
    "ID" "SPORT" "GAME" "MARKET" "STAKE" "P&L" "RESULT"
echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"

while IFS='|' read -r id sport game market stake pnl result placed_at; do
    if [[ -z "$id" ]]; then continue; fi
    # Color result
    case "$result" in
        WIN)     result_col="${GREEN}WIN${NC}"  ;;
        LOSS)    result_col="${RED}LOSS${NC}"   ;;
        PUSH)    result_col="${YELLOW}PUSH${NC}" ;;
        PENDING) result_col="${CYAN}PEND${NC}"  ;;
        *)       result_col="${DIM}${result}${NC}" ;;
    esac
    # Truncate game name
    game_trunc="${game:0:25}"
    # Format P&L
    if [[ "$pnl" == "NULL" || -z "$pnl" ]]; then
        pnl_col="${DIM}—${NC}"
    elif (( $(echo "$pnl >= 0" | bc -l) )); then
        pnl_col="${GREEN}+\$$(printf "%.2f" "$pnl")${NC}"
    else
        pnl_col="${RED}-\$$(printf "%.2f" "${pnl#-}")${NC}"
    fi
    printf "  %-6s %-8s %-26s %-12s %8s %8b %b\n" \
        "$id" "$sport" "$game_trunc" "${market:0:12}" "\$$stake" "$pnl_col" "$result_col"
done < <(q "SELECT id, sport, game, market, stake, COALESCE(CAST(pnl AS TEXT),'NULL'), COALESCE(result,'PENDING'), placed_at
            FROM bets ORDER BY placed_at DESC LIMIT 10;")

echo ""

# ── SECTION 4: Per-Sport Breakdown ───────────────────────────
echo -e "${BOLD}${BLUE}▸ SPORT BREAKDOWN${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
printf "  ${BOLD}%-10s %6s %5s %5s %5s %10s %10s %8s${NC}\n" \
    "SPORT" "BETS" "W" "L" "P" "WAGERED" "P&L" "ROI%"
echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"

sport_data=$(q "
    SELECT
        sport,
        COUNT(*) as bets,
        SUM(CASE WHEN result='WIN'  THEN 1 ELSE 0 END) as wins,
        SUM(CASE WHEN result='LOSS' THEN 1 ELSE 0 END) as losses,
        SUM(CASE WHEN result='PUSH' THEN 1 ELSE 0 END) as pushes,
        COALESCE(SUM(CASE WHEN result IN ('WIN','LOSS','PUSH') THEN stake ELSE 0 END), 0) as wagered,
        COALESCE(SUM(COALESCE(pnl, 0)), 0) as total_pnl
    FROM bets
    WHERE result IN ('WIN','LOSS','PUSH')
    GROUP BY sport
    ORDER BY total_pnl DESC;
")

if [[ -z "$sport_data" ]]; then
    echo -e "  ${DIM}No settled bets yet.${NC}"
else
    while IFS='|' read -r sport bets wins losses pushes wagered pnl; do
        if [[ -z "$sport" ]]; then continue; fi
        if (( $(echo "$wagered > 0" | bc -l) )); then
            roi=$(echo "scale=2; ($pnl / $wagered) * 100" | bc -l)
        else
            roi="0.00"
        fi
        if (( $(echo "$pnl >= 0" | bc -l) )); then
            pnl_col="${GREEN}+\$$(printf "%.2f" "$pnl")${NC}"
            roi_col="${GREEN}+${roi}%${NC}"
        else
            pnl_col="${RED}-\$$(printf "%.2f" "${pnl#-}")${NC}"
            roi_col="${RED}${roi}%${NC}"
        fi
        printf "  %-10s %6s %5s %5s %5s %10s %10b %8b\n" \
            "$sport" "$bets" "$wins" "$losses" "$pushes" "\$$wagered" "$pnl_col" "$roi_col"
    done <<< "$sport_data"
fi

echo ""

# ── SECTION 5: Agent Performance ─────────────────────────────
echo -e "${BOLD}${BLUE}▸ AGENT PERFORMANCE${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
printf "  ${BOLD}%-30s %-10s %6s %8s %8s %8s${NC}\n" \
    "AGENT" "SPORT" "BETS" "WIN%" "ROI%" "AVG CLV"
echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"

agent_data=$(q "
    SELECT
        COALESCE(agent_used, 'Unknown') as agent,
        sport,
        COUNT(*) as bets,
        ROUND(100.0 * SUM(CASE WHEN result='WIN' THEN 1 ELSE 0 END)
              / NULLIF(SUM(CASE WHEN result IN ('WIN','LOSS') THEN 1 ELSE 0 END), 0), 1) as win_rate,
        COALESCE(SUM(CASE WHEN result IN ('WIN','LOSS','PUSH') THEN stake ELSE 0 END), 0) as wagered,
        COALESCE(SUM(COALESCE(pnl, 0)), 0) as total_pnl,
        ROUND(AVG(COALESCE(clv, 0)), 2) as avg_clv
    FROM bets
    WHERE result IN ('WIN','LOSS','PUSH')
    GROUP BY agent_used, sport
    ORDER BY total_pnl DESC;
")

if [[ -z "$agent_data" ]]; then
    echo -e "  ${DIM}No settled bets with agent attribution yet.${NC}"
else
    while IFS='|' read -r agent sport bets win_rate wagered pnl avg_clv; do
        if [[ -z "$agent" ]]; then continue; fi
        if (( $(echo "$wagered > 0" | bc -l) )); then
            roi=$(echo "scale=2; ($pnl / $wagered) * 100" | bc -l)
        else
            roi="0.00"
        fi
        win_rate="${win_rate:-0.0}"
        if (( $(echo "$roi >= 0" | bc -l) )); then
            roi_col="${GREEN}+${roi}%${NC}"
        else
            roi_col="${RED}${roi}%${NC}"
        fi
        avg_clv_fmt=$(printf "%+.2f" "${avg_clv:-0}")
        printf "  %-30s %-10s %6s %7s%% %8b %8s\n" \
            "${agent:0:29}" "$sport" "$bets" "$win_rate" "$roi_col" "$avg_clv_fmt"
    done <<< "$agent_data"
fi

echo ""

# ── SECTION 6: Daily Equity Curve (last 30 days) ─────────────
echo -e "${BOLD}${BLUE}▸ EQUITY CURVE — LAST 30 DAYS${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"

snapshot_data=$(q "
    SELECT date, balance, total_bets, wins, losses, pushes, roi_pct
    FROM daily_snapshots
    WHERE date >= date('now', '-30 days')
    ORDER BY date ASC;
")

if [[ -z "$snapshot_data" ]]; then
    echo -e "  ${DIM}No daily snapshots yet. Snapshots are generated automatically each day.${NC}"
else
    printf "  ${BOLD}%-12s %12s %6s %4s %4s %4s %8s${NC}\n" \
        "DATE" "BALANCE" "BETS" "W" "L" "P" "ROI%"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${NC}"
    while IFS='|' read -r date balance bets wins losses pushes roi_pct; do
        if [[ -z "$date" ]]; then continue; fi
        if (( $(echo "$roi_pct >= 0" | bc -l) )); then
            roi_col="${GREEN}$(printf "%+.2f" "$roi_pct")%${NC}"
        else
            roi_col="${RED}$(printf "%.2f" "$roi_pct")%${NC}"
        fi
        printf "  %-12s %12s %6s %4s %4s %4s %8b\n" \
            "$date" "\$$balance" "$bets" "${wins:-0}" "${losses:-0}" "${pushes:-0}" "$roi_col"
    done <<< "$snapshot_data"
fi

echo ""

# ── SECTION 7: Learning Feedback ─────────────────────────────
echo -e "${BOLD}${BLUE}▸ 30-DAY LEARNING FEEDBACK${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"

feedback=$(q "
    SELECT
        COALESCE(agent_used, 'Unknown') as agent,
        sport,
        COUNT(*) as bets,
        COALESCE(SUM(CASE WHEN result IN ('WIN','LOSS','PUSH') THEN stake ELSE 0 END), 0) as wagered,
        COALESCE(SUM(COALESCE(pnl, 0)), 0) as total_pnl
    FROM bets
    WHERE result IN ('WIN','LOSS','PUSH')
      AND placed_at >= datetime('now', '-30 days')
    GROUP BY agent_used, sport
    HAVING bets >= 3
    ORDER BY total_pnl DESC;
")

if [[ -z "$feedback" ]]; then
    echo -e "  ${DIM}Not enough data yet. Need at least 3 settled bets per agent/sport combination.${NC}"
else
    echo -e "  Based on the last 30 days:"
    echo ""
    while IFS='|' read -r agent sport bets wagered pnl; do
        if [[ -z "$agent" ]]; then continue; fi
        if (( $(echo "$wagered > 0" | bc -l) )); then
            roi=$(echo "scale=1; ($pnl / $wagered) * 100" | bc -l)
        else
            roi="0.0"
        fi
        if (( $(echo "$pnl >= 0" | bc -l) )); then
            echo -e "  ${GREEN}+${NC} ${BOLD}${agent}${NC} (${sport}): ${GREEN}+${roi}% ROI${NC} over ${bets} bets — ${GREEN}keep deploying${NC}"
        else
            echo -e "  ${RED}-${NC} ${BOLD}${agent}${NC} (${sport}): ${RED}${roi}% ROI${NC} over ${bets} bets — ${YELLOW}review approach${NC}"
        fi
    done <<< "$feedback"
fi

echo ""
echo -e "${DIM}  Database: $DB_PATH${NC}"
echo -e "${DIM}  Run init-bankroll.sh to reset | Add bets via the State Manager agent${NC}"
echo ""
