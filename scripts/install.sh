#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
AGENTS_DIR="$REPO_DIR/agents"
TARGET_DIR="$HOME/.claude/agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [--uninstall]"
    echo ""
    echo "Install The Syndicate agents to ~/.claude/agents/"
    echo ""
    echo "Options:"
    echo "  --uninstall    Remove all Syndicate agents from ~/.claude/agents/"
    echo "  --help         Show this help message"
}

check_syndicate_state() {
    local syndicate_dir="$HOME/.syndicate"
    local db_path="$syndicate_dir/bankroll.db"

    if [[ ! -d "$syndicate_dir" ]] || [[ ! -f "$db_path" ]]; then
        echo ""
        echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${YELLOW}│  Bankroll state not initialized                              │${NC}"
        echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  The Syndicate agents use persistent state stored in ${BOLD}~/.syndicate/${NC}"
        echo -e "  to track your bankroll, record bets, and power the learning"
        echo -e "  feedback loop. This directory was not found."
        echo ""
        read -rp "  Run init-bankroll.sh now to set it up? [Y/n] " confirm
        if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
            echo ""
            bash "$(dirname "$SCRIPT_DIR")/scripts/init-bankroll.sh"
        else
            echo ""
            echo -e "  ${YELLOW}Skipped.${NC} Run ${BOLD}./scripts/init-bankroll.sh${NC} before using bankroll-aware agents."
        fi
        echo ""
    fi
}

install_agents() {
    mkdir -p "$TARGET_DIR"

    local count=0
    while IFS= read -r -d '' agent_file; do
        local filename
        filename="$(basename "$agent_file")"
        cp "$agent_file" "$TARGET_DIR/$filename"
        count=$((count + 1))
        echo -e "  ${GREEN}+${NC} $filename"
    done < <(find "$AGENTS_DIR" -name '*.md' -type f -print0)

    echo ""
    echo -e "${GREEN}Installed $count agents to $TARGET_DIR${NC}"
    echo "Open Claude Code in any project to use them."

    check_syndicate_state
}

uninstall_agents() {
    if [[ ! -d "$TARGET_DIR" ]]; then
        echo -e "${YELLOW}No agents directory found at $TARGET_DIR${NC}"
        exit 0
    fi

    local count=0
    while IFS= read -r -d '' agent_file; do
        local filename
        filename="$(basename "$agent_file")"
        local target="$TARGET_DIR/$filename"
        if [[ -f "$target" ]]; then
            rm "$target"
            count=$((count + 1))
            echo -e "  ${RED}-${NC} $filename"
        fi
    done < <(find "$AGENTS_DIR" -name '*.md' -type f -print0)

    echo ""
    echo -e "${YELLOW}Removed $count agents from $TARGET_DIR${NC}"
}

case "${1:-}" in
    --uninstall)
        echo "Uninstalling The Syndicate agents..."
        echo ""
        uninstall_agents
        ;;
    --help|-h)
        usage
        ;;
    "")
        echo "Installing The Syndicate agents..."
        echo ""
        install_agents
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        usage
        exit 1
        ;;
esac
