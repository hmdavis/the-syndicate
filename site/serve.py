#!/usr/bin/env python3
"""
Syndicate Dashboard — local web server.
Reads from ~/.syndicate/bankroll.db and serves a dashboard at http://localhost:8501
Usage: python site/serve.py [--port 8501]
"""

import json
import sqlite3
import argparse
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

DB_PATH = Path.home() / ".syndicate" / "bankroll.db"
SITE_DIR = Path(__file__).parent


def query_db(sql, params=()):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_dashboard_data():
    bankroll = query_db("SELECT * FROM bankroll_state LIMIT 1")
    bets = query_db("SELECT * FROM bets ORDER BY placed_at DESC")
    snapshots = query_db("SELECT * FROM daily_snapshots ORDER BY date DESC LIMIT 90")
    agent_perf = query_db("SELECT * FROM agent_performance ORDER BY roi_pct DESC")
    sports_config = query_db("SELECT * FROM sports_config")

    state = bankroll[0] if bankroll else {}
    starting = state.get("starting_balance", 500)
    current = state.get("current_balance", 500)
    pnl = current - starting
    drawdown = max(0, (starting - current) / starting * 100) if starting > 0 else 0

    settled = [b for b in bets if b["result"] in ("WIN", "LOSS", "PUSH")]
    wins = sum(1 for b in settled if b["result"] == "WIN")
    losses = sum(1 for b in settled if b["result"] == "LOSS")
    pushes = sum(1 for b in settled if b["result"] == "PUSH")
    pending = sum(1 for b in bets if b["result"] == "PENDING")
    voided = sum(1 for b in bets if b["result"] == "VOID")
    total_staked = sum(b["stake"] for b in settled)
    total_pnl = sum(b["pnl"] or 0 for b in settled)
    roi = (total_pnl / total_staked * 100) if total_staked > 0 else 0

    return {
        "bankroll": {
            "current_balance": current,
            "starting_balance": starting,
            "pnl": pnl,
            "drawdown_pct": round(drawdown, 1),
            "risk_tolerance": state.get("risk_tolerance", "moderate"),
        },
        "summary": {
            "total_bets": len(bets),
            "settled": len(settled),
            "wins": wins,
            "losses": losses,
            "pushes": pushes,
            "pending": pending,
            "voided": voided,
            "win_rate": round(wins / len(settled) * 100, 1) if settled else 0,
            "total_staked": round(total_staked, 2),
            "total_pnl": round(total_pnl, 2),
            "roi_pct": round(roi, 1),
        },
        "bets": bets,
        "snapshots": list(reversed(snapshots)),
        "agent_performance": agent_perf,
        "sports_config": sports_config,
    }


class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE_DIR), **kwargs)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/data":
            data = get_dashboard_data()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(data, default=str).encode())
        else:
            if path == "/":
                self.path = "/index.html"
            super().do_GET()

    def log_message(self, format, *args):
        pass  # suppress request logs


def main():
    parser = argparse.ArgumentParser(description="Syndicate Dashboard")
    parser.add_argument("--port", type=int, default=8501)
    args = parser.parse_args()

    if not DB_PATH.exists():
        print(f"Error: {DB_PATH} not found. Run ./scripts/init-bankroll.sh first.")
        return

    server = HTTPServer(("localhost", args.port), DashboardHandler)
    print(f"Syndicate Dashboard: http://localhost:{args.port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutdown.")
        server.server_close()


if __name__ == "__main__":
    main()
