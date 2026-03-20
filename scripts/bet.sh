#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# The Syndicate — Bet Management CLI
# Record bets, settle results, view open bets
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DB_PATH="$HOME/.syndicate/bankroll.db"

check_db() {
    if [[ ! -f "$DB_PATH" ]]; then
        echo -e "${RED}Error:${NC} Bankroll database not found at $DB_PATH"
        echo "Run ./scripts/init-bankroll.sh first."
        exit 1
    fi
}

usage() {
    echo -e "${BOLD}The Syndicate — Bet Manager${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  place         Record a new bet (interactive)"
    echo "  settle <id>   Settle a bet by ID"
    echo "  open          List all pending (unsettled) bets"
    echo "  history [n]   Show last N settled bets (default: 20)"
    echo "  view <id>     View details of a specific bet"
    echo "  void <id>     Void a pending bet (refund, no P&L)"
    echo "  help          Show this help"
}

get_balance() {
    sqlite3 "$DB_PATH" "SELECT current_balance FROM bankroll_state WHERE id=1;"
}

get_enabled_sports() {
    sqlite3 "$DB_PATH" "SELECT sport FROM sports_config WHERE enabled=1 ORDER BY sport;"
}

# ── PLACE a new bet ──────────────────────────────────────────
cmd_place() {
    check_db
    echo -e "${BOLD}${CYAN}Record New Bet${NC}"
    echo ""

    balance=$(get_balance)
    echo -e "  Current bankroll: ${GREEN}\$${balance}${NC}"
    echo ""

    # Sport
    echo -e "  ${BOLD}Enabled sports:${NC}"
    enabled=$(get_enabled_sports)
    echo "    $enabled" | tr '\n' '  '
    echo ""
    echo ""
    while true; do
        read -rp "  Sport: " sport
        sport="${sport^^}"
        if echo "$enabled" | grep -qw "$sport"; then
            break
        else
            echo -e "  ${RED}Sport '$sport' is not enabled.${NC} Pick from the list above."
        fi
    done

    # Game
    read -rp "  Game (e.g. Chiefs vs Ravens): " game

    # Market
    echo -e "  ${BOLD}Market types:${NC} spread, moneyline, total, prop, parlay, futures, other"
    read -rp "  Market: " market
    market="${market,,}"

    # Selection
    read -rp "  Selection (e.g. Chiefs -3.5, Over 47.5): " selection

    # Odds
    while true; do
        read -rp "  Odds (American, e.g. -110, +145): " odds_raw
        odds_raw="${odds_raw//+/}"
        if [[ "$odds_raw" =~ ^-?[0-9]+$ ]] && [[ "$odds_raw" -ne 0 ]]; then
            odds="$odds_raw"
            break
        else
            echo -e "  ${RED}Invalid odds.${NC} Enter American format (e.g. -110, +145, -200)."
        fi
    done

    # Stake
    while true; do
        read -rp "  Stake (\$): " stake_raw
        stake_raw="${stake_raw#\$}"
        stake_raw="${stake_raw//,/}"
        if [[ "$stake_raw" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]] && (( $(echo "$stake_raw > 0" | bc -l) )); then
            stake="$stake_raw"
            break
        else
            echo -e "  ${RED}Invalid stake.${NC} Enter a positive dollar amount."
        fi
    done

    # Agent (optional)
    read -rp "  Agent used (optional, e.g. Market Maker): " agent_used

    # Confidence (optional)
    confidence=""
    read -rp "  Confidence 0.0-1.0 (optional, press ENTER to skip): " conf_raw
    if [[ -n "$conf_raw" ]]; then
        if [[ "$conf_raw" =~ ^[01](\.[0-9]+)?$ ]]; then
            confidence="$conf_raw"
        else
            echo -e "  ${YELLOW}Invalid confidence, skipping.${NC}"
        fi
    fi

    # Notes (optional)
    read -rp "  Notes (optional): " notes

    # Build and execute INSERT
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    conf_val="NULL"
    [[ -n "$confidence" ]] && conf_val="$confidence"

    agent_val="NULL"
    [[ -n "$agent_used" ]] && agent_val="'$(echo "$agent_used" | sed "s/'/''/g")'"

    notes_val="NULL"
    [[ -n "$notes" ]] && notes_val="'$(echo "$notes" | sed "s/'/''/g")'"

    bet_id=$(sqlite3 "$DB_PATH" "
        INSERT INTO bets (sport, game, market, selection, odds, stake, result, agent_used, confidence, notes, placed_at)
        VALUES (
            '${sport}',
            '$(echo "$game" | sed "s/'/''/g")',
            '${market}',
            '$(echo "$selection" | sed "s/'/''/g")',
            ${odds},
            ${stake},
            'PENDING',
            ${agent_val},
            ${conf_val},
            ${notes_val},
            '${now}'
        );
        SELECT last_insert_rowid();
    ")

    echo ""
    echo -e "${GREEN}${BOLD}Bet #${bet_id} recorded${NC}"
    echo ""
    echo -e "  Sport:      ${sport}"
    echo -e "  Game:       ${game}"
    echo -e "  Market:     ${market}"
    echo -e "  Selection:  ${selection}"
    echo -e "  Odds:       ${odds}"
    echo -e "  Stake:      \$${stake}"
    [[ -n "$agent_used" ]] && echo -e "  Agent:      ${agent_used}"
    [[ -n "$confidence" ]] && echo -e "  Confidence: ${confidence}"
    [[ -n "$notes" ]]      && echo -e "  Notes:      ${notes}"
    echo -e "  Status:     ${YELLOW}PENDING${NC}"
    echo ""
}

# ── SETTLE a bet ─────────────────────────────────────────────
cmd_settle() {
    check_db
    local bet_id="$1"

    # Fetch the bet
    local bet_data
    bet_data=$(sqlite3 -separator '|' "$DB_PATH" "
        SELECT id, sport, game, market, selection, odds, stake, result, agent_used
        FROM bets WHERE id = ${bet_id};
    ")

    if [[ -z "$bet_data" ]]; then
        echo -e "${RED}Error:${NC} Bet #${bet_id} not found."
        exit 1
    fi

    IFS='|' read -r _ sport game market selection odds stake result agent_used <<< "$bet_data"

    if [[ "$result" != "PENDING" ]]; then
        echo -e "${RED}Error:${NC} Bet #${bet_id} already settled as ${result}."
        exit 1
    fi

    echo -e "${BOLD}${CYAN}Settle Bet #${bet_id}${NC}"
    echo ""
    echo -e "  Sport:     ${sport}"
    echo -e "  Game:      ${game}"
    echo -e "  Selection: ${selection} @ ${odds}"
    echo -e "  Stake:     \$${stake}"
    echo ""

    # Result
    while true; do
        read -rp "  Result (win/loss/push): " result_input
        case "${result_input,,}" in
            w|win)  result_val="WIN";  break ;;
            l|loss) result_val="LOSS"; break ;;
            p|push) result_val="PUSH"; break ;;
            *) echo -e "  ${RED}Enter win, loss, or push.${NC}" ;;
        esac
    done

    # Closing odds (optional, for CLV)
    clv_val="NULL"
    read -rp "  Closing odds (optional, for CLV calculation): " closing_raw
    if [[ -n "$closing_raw" ]]; then
        closing_raw="${closing_raw//+/}"
        if [[ "$closing_raw" =~ ^-?[0-9]+$ ]]; then
            # Calculate CLV: implied_prob(closing) - implied_prob(entry) in cents
            clv_val=$(python3 -c "
def to_impl(o):
    o = int(o)
    return abs(o) / (abs(o) + 100) if o < 0 else 100 / (o + 100)
clv = round((to_impl(${closing_raw}) - to_impl(${odds})) * 100, 2)
print(clv)
")
        fi
    fi

    # Calculate P&L
    pnl=$(python3 -c "
odds = int('${odds}')
stake = float('${stake}')
result = '${result_val}'
if result == 'WIN':
    pnl = stake * (odds / 100) if odds > 0 else stake * (100 / abs(odds))
elif result == 'LOSS':
    pnl = -stake
else:
    pnl = 0.0
print(round(pnl, 2))
")

    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update bet
    sqlite3 "$DB_PATH" "
        UPDATE bets SET result='${result_val}', pnl=${pnl}, clv=${clv_val}, settled_at='${now}'
        WHERE id=${bet_id};
    "

    # Update bankroll
    if [[ "$result_val" != "VOID" ]]; then
        sqlite3 "$DB_PATH" "
            UPDATE bankroll_state SET current_balance = current_balance + ${pnl}, updated_at='${now}'
            WHERE id=1;
        "
    fi

    new_balance=$(get_balance)

    # Color the P&L
    if (( $(echo "$pnl > 0" | bc -l) )); then
        pnl_display="${GREEN}+\$${pnl}${NC}"
    elif (( $(echo "$pnl < 0" | bc -l) )); then
        pnl_display="${RED}\$${pnl}${NC}"
    else
        pnl_display="\$${pnl}"
    fi

    echo ""
    echo -e "${BOLD}Bet #${bet_id} settled — ${result_val}${NC}"
    echo -e "  P&L:         ${pnl_display}"
    if [[ "$clv_val" != "NULL" ]]; then
        echo -e "  CLV:         ${clv_val} cents"
    fi
    echo -e "  New Balance: ${GREEN}\$${new_balance}${NC}"
    echo ""
}

# ── OPEN bets ────────────────────────────────────────────────
cmd_open() {
    check_db
    echo -e "${BOLD}Open (Pending) Bets${NC}"
    echo ""

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM bets WHERE result='PENDING';")

    if [[ "$count" -eq 0 ]]; then
        echo "  No pending bets."
        echo ""
        return
    fi

    echo -e "  ${BOLD}ID    Sport   Game                          Selection              Odds    Stake     Agent${NC}"
    echo "  ─────────────────────────────────────────────────────────────────────────────────────────────────"

    sqlite3 -separator '|' "$DB_PATH" "
        SELECT id, sport, game, selection, odds, stake, COALESCE(agent_used, '-')
        FROM bets WHERE result='PENDING' ORDER BY placed_at ASC;
    " | while IFS='|' read -r id sport game selection odds stake agent; do
        printf "  %-5s %-7s %-30s %-22s %-7s \$%-8s %s\n" \
            "#$id" "$sport" "${game:0:30}" "${selection:0:22}" "$odds" "$stake" "$agent"
    done

    echo ""
    echo -e "  ${BOLD}Total pending:${NC} $count bets"
    echo ""
}

# ── HISTORY ──────────────────────────────────────────────────
cmd_history() {
    check_db
    local limit="${1:-20}"
    echo -e "${BOLD}Recent Settled Bets (last ${limit})${NC}"
    echo ""

    echo -e "  ${BOLD}ID    Sport   Result  Selection              Odds    Stake     P&L        CLV${NC}"
    echo "  ────────────────────────────────────────────────────────────────────────────────────────"

    sqlite3 -separator '|' "$DB_PATH" "
        SELECT id, sport, result, selection, odds, stake, COALESCE(pnl, 0), COALESCE(clv, '-')
        FROM bets WHERE result IN ('WIN','LOSS','PUSH','VOID')
        ORDER BY settled_at DESC LIMIT ${limit};
    " | while IFS='|' read -r id sport result selection odds stake pnl clv; do
        if [[ "$result" == "WIN" ]]; then
            result_display="${GREEN}WIN ${NC}"
            pnl_display="${GREEN}+\$${pnl}${NC}"
        elif [[ "$result" == "LOSS" ]]; then
            result_display="${RED}LOSS${NC}"
            pnl_display="${RED}\$${pnl}${NC}"
        else
            result_display="${YELLOW}${result}${NC}"
            pnl_display="\$${pnl}"
        fi
        printf "  %-5s %-7s " "#$id" "$sport"
        echo -en "$result_display"
        printf "  %-22s %-7s \$%-8s " "${selection:0:22}" "$odds" "$stake"
        echo -en "$pnl_display"
        printf "    %s\n" "$clv"
    done

    echo ""
}

# ── VIEW a single bet ────────────────────────────────────────
cmd_view() {
    check_db
    local bet_id="$1"

    local bet_data
    bet_data=$(sqlite3 -separator '|' "$DB_PATH" "
        SELECT id, sport, game, market, selection, odds, stake, result,
               COALESCE(pnl,'—'), COALESCE(clv,'—'),
               placed_at, COALESCE(settled_at,'—'),
               COALESCE(agent_used,'—'), COALESCE(confidence,'—'), COALESCE(notes,'—')
        FROM bets WHERE id = ${bet_id};
    ")

    if [[ -z "$bet_data" ]]; then
        echo -e "${RED}Error:${NC} Bet #${bet_id} not found."
        exit 1
    fi

    IFS='|' read -r id sport game market selection odds stake result pnl clv placed settled agent confidence notes <<< "$bet_data"

    echo -e "${BOLD}Bet #${id}${NC}"
    echo ""
    echo -e "  Sport:      ${sport}"
    echo -e "  Game:       ${game}"
    echo -e "  Market:     ${market}"
    echo -e "  Selection:  ${selection}"
    echo -e "  Odds:       ${odds}"
    echo -e "  Stake:      \$${stake}"
    echo -e "  Result:     ${result}"
    echo -e "  P&L:        ${pnl}"
    echo -e "  CLV:        ${clv}"
    echo -e "  Placed:     ${placed}"
    echo -e "  Settled:    ${settled}"
    echo -e "  Agent:      ${agent}"
    echo -e "  Confidence: ${confidence}"
    echo -e "  Notes:      ${notes}"
    echo ""
}

# ── VOID a bet ───────────────────────────────────────────────
cmd_void() {
    check_db
    local bet_id="$1"

    local result
    result=$(sqlite3 "$DB_PATH" "SELECT result FROM bets WHERE id=${bet_id};")

    if [[ -z "$result" ]]; then
        echo -e "${RED}Error:${NC} Bet #${bet_id} not found."
        exit 1
    fi

    if [[ "$result" != "PENDING" ]]; then
        echo -e "${RED}Error:${NC} Bet #${bet_id} is already settled as ${result}. Cannot void."
        exit 1
    fi

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    sqlite3 "$DB_PATH" "
        UPDATE bets SET result='VOID', pnl=0.0, settled_at='${now}'
        WHERE id=${bet_id};
    "

    echo -e "${YELLOW}Bet #${bet_id} voided.${NC} No P&L impact."
}

# ── Main dispatcher ──────────────────────────────────────────
case "${1:-}" in
    place|new|add)
        cmd_place
        ;;
    settle|close|result)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Usage:${NC} $0 settle <bet_id>"
            exit 1
        fi
        cmd_settle "$2"
        ;;
    open|pending)
        cmd_open
        ;;
    history|log|recent)
        cmd_history "${2:-20}"
        ;;
    view|show|get)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Usage:${NC} $0 view <bet_id>"
            exit 1
        fi
        cmd_view "$2"
        ;;
    void|cancel)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Usage:${NC} $0 void <bet_id>"
            exit 1
        fi
        cmd_void "$2"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command:${NC} $1"
        usage
        exit 1
        ;;
esac
