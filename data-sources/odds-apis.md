# Odds & Betting Data APIs

Reference documentation for odds and betting data sources used by The Syndicate agents.

---

## 1. The Odds API (the-odds-api.com)

### Overview
REST API aggregating odds from 40+ sportsbooks. Well-documented, reliable, and commonly used for line shopping and historical odds.

### Authentication
API key passed as a query parameter: `?apiKey=YOUR_KEY`

### Tiers & Rate Limits
| Tier | Requests/Month | Cost |
|------|---------------|------|
| Free | 500 | $0 |
| Starter | 30,000 | ~$39/mo |
| Pro | 100,000 | ~$99/mo |
| Business | 500,000 | ~$249/mo |

Requests remaining are returned in response headers: `x-requests-remaining`, `x-requests-used`.

### Key Endpoints

```
Base URL: https://api.the-odds-api.com/v4

# List available sports
GET /sports?apiKey={key}

# Get odds for a sport (head-to-head markets)
GET /sports/{sport_key}/odds?apiKey={key}&regions=us&markets=h2h&oddsFormat=american

# Get scores/results
GET /sports/{sport_key}/scores?apiKey={key}&daysFrom=1

# Historical odds (paid tiers only)
GET /historical/sports/{sport_key}/odds?apiKey={key}&date=2024-01-15T00:00:00Z
```

Common `sport_key` values: `basketball_nba`, `americanfootball_nfl`, `baseball_mlb`, `icehockey_nhl`

### Python Example

```python
import requests

API_KEY = "your_api_key_here"
BASE_URL = "https://api.the-odds-api.com/v4"

def get_nba_odds(markets: str = "h2h,spreads,totals") -> list[dict]:
    url = f"{BASE_URL}/sports/basketball_nba/odds"
    params = {
        "apiKey": API_KEY,
        "regions": "us",
        "markets": markets,
        "oddsFormat": "american",
        "bookmakers": "draftkings,fanduel,pinnacle,betmgm",
    }
    resp = requests.get(url, params=params, timeout=10)
    resp.raise_for_status()
    # Log remaining quota
    print(f"Requests remaining: {resp.headers.get('x-requests-remaining')}")
    return resp.json()

def find_best_line(games: list[dict], team: str) -> dict | None:
    """Find the best moneyline for a given team across all books."""
    best = None
    for game in games:
        for bookmaker in game.get("bookmakers", []):
            for market in bookmaker.get("markets", []):
                if market["key"] != "h2h":
                    continue
                for outcome in market["outcomes"]:
                    if outcome["name"] == team:
                        if best is None or outcome["price"] > best["price"]:
                            best = {
                                "book": bookmaker["key"],
                                "price": outcome["price"],
                                "game": f"{game['home_team']} vs {game['away_team']}",
                            }
    return best
```

---

## 2. Polymarket CLOB API

### Overview
Polymarket is a prediction market platform with a public Central Limit Order Book (CLOB). Sports event markets trade as binary contracts (YES/NO) where price = implied probability. No API key required for read operations.

This is a particularly valuable source because:
- Market prices reflect crowd wisdom and real money
- Often leads traditional sportsbooks on line movement
- Provides a probability-native view rather than American odds

### Authentication
None required for public read endpoints. Write operations (placing orders) require wallet-based auth.

### Base URLs
- REST: `https://clob.polymarket.com`
- Gamma (metadata/search): `https://gamma-api.polymarket.com`
- WebSocket: `wss://ws-subscriptions-clob.polymarket.com/ws/`

### Key REST Endpoints

```
# Get all markets (paginated)
GET https://gamma-api.polymarket.com/markets?limit=100&offset=0

# Search markets by keyword
GET https://gamma-api.polymarket.com/markets?keyword=NBA&limit=50

# Get a specific market by condition ID
GET https://gamma-api.polymarket.com/markets/{condition_id}

# Get CLOB orderbook for a token
GET https://clob.polymarket.com/book?token_id={token_id}

# Get last trade price for a token
GET https://clob.polymarket.com/last-trade-price?token_id={token_id}

# Get market mid-prices (best for quick implied prob)
GET https://clob.polymarket.com/midpoints?token_ids={token_id1},{token_id2}

# Get OHLC price history
GET https://clob.polymarket.com/prices-history?market={condition_id}&interval=1d&fidelity=60
```

### Contract Price to Implied Probability

Polymarket prices are in USDC cents (0-100), representing the probability of YES outcome.

```
Price of 0.65 = 65% implied probability of YES
```

To convert to American odds:
```
prob = price / 100
if prob >= 0.5:
    american_odds = -(prob / (1 - prob)) * 100
else:
    american_odds = ((1 - prob) / prob) * 100
```

### Python Example

```python
import requests
from dataclasses import dataclass

GAMMA_URL = "https://gamma-api.polymarket.com"
CLOB_URL = "https://clob.polymarket.com"


@dataclass
class PolymarketSportsMarket:
    condition_id: str
    question: str
    yes_token_id: str
    no_token_id: str
    yes_price: float      # 0.0 - 1.0
    no_price: float
    volume_24h: float
    liquidity: float


def search_sports_markets(keyword: str, active_only: bool = True) -> list[dict]:
    params = {"keyword": keyword, "limit": 50}
    if active_only:
        params["active"] = "true"
        params["closed"] = "false"
    resp = requests.get(f"{GAMMA_URL}/markets", params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()


def get_market_prices(token_ids: list[str]) -> dict[str, float]:
    """Returns {token_id: mid_price} where price is 0-100."""
    joined = ",".join(token_ids)
    resp = requests.get(f"{CLOB_URL}/midpoints", params={"token_ids": joined}, timeout=10)
    resp.raise_for_status()
    return resp.json().get("mid", {})


def price_to_american(prob: float) -> int:
    """Convert implied probability (0-1) to American odds."""
    if prob >= 0.5:
        return round(-(prob / (1 - prob)) * 100)
    else:
        return round(((1 - prob) / prob) * 100)


def fetch_nba_markets() -> list[PolymarketSportsMarket]:
    raw_markets = search_sports_markets("NBA")
    results = []
    for m in raw_markets:
        tokens = m.get("tokens", [])
        if len(tokens) != 2:
            continue
        yes_token = next((t for t in tokens if t.get("outcome") == "Yes"), None)
        no_token = next((t for t in tokens if t.get("outcome") == "No"), None)
        if not yes_token or not no_token:
            continue

        prices = get_market_prices([yes_token["token_id"], no_token["token_id"]])
        yes_price = float(prices.get(yes_token["token_id"], 50)) / 100
        no_price = float(prices.get(no_token["token_id"], 50)) / 100

        results.append(PolymarketSportsMarket(
            condition_id=m["condition_id"],
            question=m["question"],
            yes_token_id=yes_token["token_id"],
            no_token_id=no_token["token_id"],
            yes_price=yes_price,
            no_price=no_price,
            volume_24h=float(m.get("volume24hr", 0)),
            liquidity=float(m.get("liquidity", 0)),
        ))
    return results


def compare_polymarket_vs_sportsbook(poly_prob: float, book_american: int) -> float:
    """
    Returns edge in probability points: positive = Polymarket implies better value on YES.
    """
    if book_american < 0:
        book_prob = (-book_american) / (-book_american + 100)
    else:
        book_prob = 100 / (book_american + 100)
    return poly_prob - book_prob


# WebSocket example for live price updates
import json
import websockets
import asyncio

async def subscribe_to_market(condition_id: str):
    uri = "wss://ws-subscriptions-clob.polymarket.com/ws/market"
    async with websockets.connect(uri) as ws:
        await ws.send(json.dumps({
            "assets_ids": [condition_id],
            "type": "market",
        }))
        async for msg in ws:
            data = json.loads(msg)
            print(data)  # price updates, trade events
```

---

## 3. OddsJam

### Overview
Paid API with positive EV detection, arbitrage, and historical odds. Primarily marketed to bettors rather than developers, but provides an API for programmatic access.

### Authentication
Bearer token in `Authorization` header.

### Tiers & Rate Limits
- Subscription-based pricing, starts around $75/mo for API access
- Rate limits vary by plan; typically 60 req/min

### Key Endpoints

```
Base URL: https://api.oddsjam.com/api/v2

GET /game-odds?sport=basketball_nba&book=draftkings,fanduel&market=moneyline
GET /positive-ev?sport=basketball_nba&min_ev=2
GET /historical-odds?game_id={id}&book=pinnacle
```

### Python Example

```python
import requests

ODDSJAM_KEY = "your_api_key"

def get_positive_ev_bets(sport: str = "basketball_nba", min_ev: float = 3.0) -> list[dict]:
    headers = {"Authorization": f"Bearer {ODDSJAM_KEY}"}
    params = {"sport": sport, "min_ev": min_ev}
    resp = requests.get(
        "https://api.oddsjam.com/api/v2/positive-ev",
        headers=headers,
        params=params,
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json().get("data", [])
```

---

## 4. DonBest

### Overview
Professional-grade odds feed used by sharp bettors and syndicates. Provides opening lines, line movement, and consensus data. Requires a paid subscription and credentialing.

### Authentication
Username/password or API key via request headers. Contact DonBest for access.

### Base URL
`https://xml.donbest.com/v2/` (XML feed) or newer JSON endpoints.

### Key Endpoints

```
GET /odds/{sport_id}?token={token}          # Current odds
GET /schedule/{sport_id}?token={token}      # Game schedule
GET /team_scores/{sport_id}?token={token}   # Live scores
GET /line_movement/{game_id}?token={token}  # Line history
```

### Python Example

```python
import requests
import xml.etree.ElementTree as ET

DONBEST_TOKEN = "your_token"

def get_nfl_odds() -> list[dict]:
    url = f"https://xml.donbest.com/v2/odds/3?token={DONBEST_TOKEN}"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    root = ET.fromstring(resp.text)
    games = []
    for game in root.findall(".//game"):
        games.append({
            "id": game.get("id"),
            "home": game.find("home/name").text,
            "away": game.find("away/name").text,
            "spread": game.find(".//spread/home").text,
        })
    return games
```

---

## 5. Pinnacle API

### Overview
Pinnacle is the benchmark sharp sportsbook. Their lines are widely used as the "true market" since they accept large bets from professionals. They have a semi-public API available to account holders.

### Authentication
HTTP Basic Auth with your Pinnacle account credentials.

### Base URL
`https://api.pinnacle.com/v1/`

### Rate Limits
- 1 request/second per endpoint
- Some endpoints have lower limits; check `X-Rate-Limit-*` response headers

### Key Endpoints

```
GET /leagues?sportId={id}                    # List leagues
GET /fixtures?sportId={id}&leagueIds={ids}   # Upcoming games
GET /odds?sportId={id}&leagueIds={ids}&oddsFormat=American
GET /odds/special?sportId={id}               # Props/specials
GET /line?sportId=29&leagueId=1456&eventId={id}&periodNumber=0&betType=Spread
```

Sport IDs: `29` = NFL, `4` = NBA, `3` = MLB, `19` = NHL

### Python Example

```python
import requests
from requests.auth import HTTPBasicAuth

PINNACLE_USER = "your_username"
PINNACLE_PASS = "your_password"
BASE = "https://api.pinnacle.com/v1"
AUTH = HTTPBasicAuth(PINNACLE_USER, PINNACLE_PASS)

def get_nba_odds() -> dict:
    params = {
        "sportId": 4,
        "leagueIds": "487",   # NBA league ID
        "oddsFormat": "American",
    }
    resp = requests.get(f"{BASE}/odds", auth=AUTH, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()

def get_closing_line(event_id: int, bet_type: str = "Spread") -> dict:
    """Fetch the closing line for a specific event — useful for CLV analysis."""
    params = {
        "sportId": 4,
        "leagueId": 487,
        "eventId": event_id,
        "periodNumber": 0,
        "betType": bet_type,
        "team": "Home",
        "side": "Home",
        "handicap": -3.5,
        "oddsFormat": "American",
    }
    resp = requests.get(f"{BASE}/line", auth=AUTH, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()
```

---

## Summary Table

| Source | Auth | Cost | Best For |
|--------|------|------|----------|
| The Odds API | API key | Free–$249/mo | Multi-book aggregation, easy setup |
| Polymarket CLOB | None (read) | Free | Prediction market implied probs, leading indicator |
| OddsJam | Bearer token | ~$75+/mo | Positive EV detection, arbitrage |
| DonBest | Token | Paid (contact) | Professional line movement, consensus |
| Pinnacle | Basic auth | Account required | Sharp market benchmark, CLV analysis |
