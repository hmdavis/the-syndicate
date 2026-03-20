# Sports Statistics APIs

Reference documentation for sports data Python packages and APIs used by The Syndicate agents.

---

## 1. nba_api

### Overview
Unofficial Python client for stats.nba.com. Provides access to play-by-play, box scores, shot charts, player tracking, and advanced metrics going back to 1996.

### Installation
```bash
pip install nba_api
```

### Rate Limits
stats.nba.com is rate-limited. Add a 0.6–1s delay between requests to avoid 429s. The package has a built-in `timeout` parameter but no automatic backoff.

### Key Endpoints & Classes

```python
from nba_api.stats.endpoints import (
    LeagueGameLog,
    TeamGameLog,
    PlayByPlayV2,
    BoxScoreAdvancedV2,
    PlayerGameLogs,
    LeagueDashPlayerStats,
    ShotChartDetail,
    ScoreboardV2,
)
from nba_api.live.nba.endpoints import scoreboard  # live scores
```

### Python Examples

```python
import time
import pandas as pd
from nba_api.stats.endpoints import LeagueDashPlayerStats, PlayByPlayV2, ScoreboardV2
from nba_api.stats.static import teams, players

# Get all player stats for current season
def get_player_stats(season: str = "2024-25", per_mode: str = "PerGame") -> pd.DataFrame:
    stats = LeagueDashPlayerStats(
        season=season,
        per_mode_simple=per_mode,
        measure_type_simple="Advanced",
        timeout=30,
    )
    time.sleep(0.6)
    return stats.get_data_frames()[0]

# Get play-by-play for a game
def get_pbp(game_id: str) -> pd.DataFrame:
    pbp = PlayByPlayV2(game_id=game_id, timeout=30)
    time.sleep(0.6)
    return pbp.get_data_frames()[0]

# Live scoreboard
def get_live_scores() -> dict:
    from nba_api.live.nba.endpoints import scoreboard
    return scoreboard.ScoreBoard().get_dict()

# Find team ID by abbreviation
def get_team_id(abbrev: str) -> int:
    nba_teams = teams.get_teams()
    team = next(t for t in nba_teams if t["abbreviation"] == abbrev)
    return team["id"]
```

### What Data Is Available
- Box scores (traditional, advanced, tracking, hustle)
- Play-by-play with SYNERGY event types
- Shot charts with exact court coordinates
- Player tracking (speed, distance, touches)
- Historical season stats back to 1996-97
- Draft history, transactions, contracts

---

## 2. nfl_data_py

### Overview
Python package for NFL play-by-play, roster, schedule, and Next Gen Stats data. Sourced from nflfastR and nflverse. Essential for building NFL models.

### Installation
```bash
pip install nfl_data_py
```

### Rate Limits
Downloads from GitHub-hosted parquet/CSV files. No API key needed. Reasonable use only; cache locally to avoid re-downloading.

### Python Examples

```python
import nfl_data_py as nfl
import pandas as pd

# Play-by-play — the core dataset (~50MB per season)
def get_pbp(seasons: list[int]) -> pd.DataFrame:
    df = nfl.import_pbp_data(
        years=seasons,
        columns=[
            "game_id", "posteam", "defteam", "week", "down", "ydstogo",
            "yardline_100", "play_type", "yards_gained", "epa", "wpa",
            "pass_attempt", "rush_attempt", "qb_dropback", "air_yards",
            "yards_after_catch", "passer_player_name", "receiver_player_name",
        ],
        downcast=True,
    )
    return df

# Schedule with Elo ratings and Vegas lines
def get_schedule(seasons: list[int]) -> pd.DataFrame:
    return nfl.import_schedules(years=seasons)
    # Columns include: spread_line, total_line, away_moneyline, home_moneyline
    # result, away_score, home_score, roof, surface, temp, wind

# Weekly rosters
def get_rosters(seasons: list[int]) -> pd.DataFrame:
    return nfl.import_weekly_rosters(years=seasons)

# Seasonal stats (aggregated)
def get_seasonal_stats(seasons: list[int], stat_type: str = "passing") -> pd.DataFrame:
    return nfl.import_seasonal_data(years=seasons, s_type=stat_type)

# Next Gen Stats (requires 2016+)
def get_ngs(seasons: list[int], stat_type: str = "passing") -> pd.DataFrame:
    return nfl.import_ngs_data(stat_type=stat_type, years=seasons)

# Win probability and EPA per play
def get_epa_leaders(season: int) -> pd.DataFrame:
    pbp = get_pbp([season])
    return (
        pbp[pbp["pass_attempt"] == 1]
        .groupby("passer_player_name")["epa"]
        .agg(["mean", "sum", "count"])
        .rename(columns={"mean": "epa_per_play", "sum": "total_epa", "count": "plays"})
        .query("plays >= 100")
        .sort_values("epa_per_play", ascending=False)
    )
```

### What Data Is Available
- Play-by-play with EPA, WPA, air yards, and coverage data (2000+)
- Schedule with Vegas lines, results, weather, and surface
- Rosters with depth chart positions and snap counts
- Next Gen Stats (tracking data) since 2016
- Combine measurements
- Draft picks and contract data

---

## 3. pybaseball

### Overview
Python package pulling from FanGraphs, Baseball Reference, and Statcast. Best-in-class for baseball analytics.

### Installation
```bash
pip install pybaseball
```

### Rate Limits
FanGraphs and Baseball Reference allow scraping at reasonable rates. Statcast pulls from baseballsavant.mlb.com — cache results, as large date ranges can be slow. Enable caching:

```python
from pybaseball import cache
cache.enable()
```

### Python Examples

```python
from pybaseball import (
    statcast,
    statcast_pitcher,
    statcast_batter,
    pitching_stats,
    batting_stats,
    schedule_and_record,
    team_pitching,
    playerid_lookup,
)
import pandas as pd

# Statcast data — pitch-by-pitch with Trackman data
def get_statcast_range(start: str, end: str) -> pd.DataFrame:
    # start/end format: "YYYY-MM-DD"
    return statcast(start_dt=start, end_dt=end, verbose=False)
    # Key columns: pitch_type, release_speed, release_spin_rate,
    # pfx_x, pfx_z, plate_x, plate_z, launch_speed, launch_angle,
    # estimated_ba_using_speedangle, estimated_woba_using_speedangle

# FanGraphs season pitching stats
def get_pitching_stats(season: int) -> pd.DataFrame:
    return pitching_stats(season, season, qual=50)
    # Includes FIP, xFIP, SIERA, K%, BB%, SwStr%

# FanGraphs batting stats
def get_batting_stats(season: int) -> pd.DataFrame:
    return batting_stats(season, season, qual=200)
    # Includes wRC+, WAR, wOBA, BABIP, Hard%

# Get a player's MLBAM ID for Statcast queries
def lookup_player(last: str, first: str) -> pd.DataFrame:
    return playerid_lookup(last, first)

# Team schedule and results (used for rest/travel modeling)
def get_schedule(team: str, season: int) -> pd.DataFrame:
    return schedule_and_record(season, team)
    # Columns: Date, Home_Away, Opp, R, RA, W_L, Win, Loss, Save
```

### What Data Is Available
- Statcast pitch-by-pitch (2015+): spin rate, movement, exit velocity, launch angle
- FanGraphs batting and pitching (projections, splits, advanced)
- Baseball Reference historical stats (1871+)
- Team schedules, standings, park factors

---

## 4. hockey_scraper / nhl_api

### Overview
Two complementary packages for NHL data. `hockey_scraper` pulls play-by-play from NHL.com. `nhl_api` wraps the official NHL Stats API.

### Installation
```bash
pip install hockey_scraper
pip install nhl-api-py   # maintained fork of nhlpy
```

### Rate Limits
NHL Stats API (`api-web.nhle.com`) has no documented rate limits but respect ~1 req/sec. hockey_scraper scrapes NHL.com HTML — use caching and moderate request rates.

### Python Examples

```python
# nhl_api (official NHL Stats API wrapper)
from nhlpy import NHLClient

client = NHLClient()

# Schedule
def get_schedule(date: str) -> dict:
    return client.schedule.get_schedule(date=date)  # "YYYY-MM-DD"

# Team stats
def get_team_stats(season: str = "20242025") -> dict:
    return client.teams.team_stats_by_season(season=season)

# Player game log
def get_player_log(player_id: int, season: str = "20242025") -> dict:
    return client.players.player_game_log(player_id=player_id, season_id=season)


# hockey_scraper for play-by-play
import hockey_scraper

def get_season_pbp(start_season: int, end_season: int) -> "pd.DataFrame":
    return hockey_scraper.scrape_seasons(
        [start_season, end_season],
        True,           # True = regular season
        data_format="Pandas",
    )
    # Columns: event, period, seconds_elapsed, ev_team, home_zone,
    # p1_name, p2_name, p3_name, shot_type, event_zone, coords_x, coords_y
```

### Key NHL Stats API Endpoints (Direct HTTP)

```
Base URL: https://api-web.nhle.com/v1

GET /standings/now                    # Current standings
GET /schedule/{date}                  # Games on a date
GET /gamecenter/{game_id}/play-by-play
GET /player/{player_id}/game-log/{season}/{game-type}
GET /club-stats/{team_abbrev}/now
```

---

## 5. cfbd (College Football Data)

### Overview
Python client for the collegefootballdata.com API. Comprehensive coverage of college football going back to 2000. Free tier available.

### Installation
```bash
pip install cfbd
```

### Authentication
API key required (free at collegefootballdata.com). Passed via config.

### Rate Limits
Free tier: ~1,000 requests/hour. Paid tiers available for higher volume.

### Python Examples

```python
import cfbd
from cfbd.rest import ApiException

configuration = cfbd.Configuration()
configuration.api_key["Authorization"] = "Bearer YOUR_API_KEY"

# Games and scores
def get_games(season: int, week: int | None = None) -> list:
    api = cfbd.GamesApi(cfbd.ApiClient(configuration))
    return api.get_games(year=season, week=week, division="fbs")

# Betting lines
def get_lines(season: int, week: int) -> list:
    api = cfbd.BettingApi(cfbd.ApiClient(configuration))
    return api.get_lines(year=season, week=week)
    # Returns: spread, over_under, moneyline per book

# Team season stats
def get_team_stats(season: int, team: str) -> list:
    api = cfbd.StatsApi(cfbd.ApiClient(configuration))
    return api.get_team_season_stats(year=season, team=team)

# Win probability (EP model built-in)
def get_win_prob(game_id: int) -> list:
    api = cfbd.MetricsApi(cfbd.ApiClient(configuration))
    return api.get_win_probability_data(game_id=game_id)

# Recruiting rankings (useful for future team quality)
def get_recruiting(season: int) -> list:
    api = cfbd.RecruitingApi(cfbd.ApiClient(configuration))
    return api.get_recruiting_teams(year=season)
```

---

## 6. Sportradar

### Overview
Professional-grade stats feed used by sportsbooks and media companies. Comprehensive coverage across all major sports with real-time push feeds. Expensive but industry standard.

### Authentication
API key as a query parameter: `?api_key=YOUR_KEY`

### Tiers & Cost
- Trial: 1,000 requests/month free
- Production: Starting ~$500/mo per sport, up to $5,000+/mo for full suite

### Rate Limits
Varies by subscription: typically 1 req/sec on trial, higher on production.

### Key Base URLs

```
NFL: https://api.sportradar.com/nfl/official/trial/v7/en/
NBA: https://api.sportradar.com/nba/trial/v8/en/
MLB: https://api.sportradar.com/mlb/trial/v7/en/
NHL: https://api.sportradar.com/nhl/trial/v7/en/
```

### Python Example

```python
import requests
import time

SR_KEY = "your_api_key"

def get_nba_daily_schedule(date: str) -> dict:
    # date format: YYYY/MM/DD
    url = f"https://api.sportradar.com/nba/trial/v8/en/games/{date}/schedule.json"
    resp = requests.get(url, params={"api_key": SR_KEY}, timeout=10)
    resp.raise_for_status()
    time.sleep(1.0)  # respect rate limit
    return resp.json()

def get_game_boxscore(game_id: str) -> dict:
    url = f"https://api.sportradar.com/nba/trial/v8/en/games/{game_id}/boxscore.json"
    resp = requests.get(url, params={"api_key": SR_KEY}, timeout=10)
    resp.raise_for_status()
    time.sleep(1.0)
    return resp.json()

def get_player_profile(player_id: str) -> dict:
    url = f"https://api.sportradar.com/nba/trial/v8/en/players/{player_id}/profile.json"
    resp = requests.get(url, params={"api_key": SR_KEY}, timeout=10)
    resp.raise_for_status()
    time.sleep(1.0)
    return resp.json()
```

### What Data Is Available
- Real-time play-by-play with push feeds
- Injury reports updated ~every 5 minutes
- Rotations, depth charts, expected starters
- Historical game-by-game data going back 10+ years
- Proprietary metrics (Sportradar efficiency ratings)

---

## Summary Table

| Package | Sport | Cost | Best For |
|---------|-------|------|----------|
| nba_api | NBA | Free | Box scores, play-by-play, tracking data |
| nfl_data_py | NFL | Free | EPA/WPA modeling, Vegas lines history |
| pybaseball | MLB | Free | Statcast, FanGraphs advanced metrics |
| hockey_scraper / nhl_api | NHL | Free | Play-by-play, official NHL API |
| cfbd | CFB | Free (1K/hr) | Lines, win probability, recruiting |
| Sportradar | All | $500+/mo/sport | Real-time feeds, professional coverage |

### Caching Recommendation

Use pandas + parquet for local caching of heavy datasets:

```python
import pandas as pd
from pathlib import Path

CACHE_DIR = Path("~/.syndicate/cache").expanduser()
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def load_or_fetch(cache_key: str, fetch_fn, **kwargs) -> pd.DataFrame:
    path = CACHE_DIR / f"{cache_key}.parquet"
    if path.exists():
        return pd.read_parquet(path)
    df = fetch_fn(**kwargs)
    df.to_parquet(path, index=False)
    return df
```
