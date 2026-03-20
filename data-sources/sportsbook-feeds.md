# Sportsbook Feeds & Direct Data Sources

Reference documentation for accessing odds data directly from sportsbooks and using prediction markets as sharp benchmarks.

---

## Overview

Most US sportsbooks do not offer official public APIs. Data access falls into three categories:

1. **Official APIs** — Pinnacle (account-gated), some daily fantasy sites
2. **Semi-public feeds** — JSON endpoints embedded in mobile/web apps, undocumented but stable
3. **Scraping** — HTML or XHR scraping with appropriate rate limiting

For line shopping, aggregators like The Odds API (see `odds-apis.md`) are usually the cleanest path. Direct feeds are useful when you need faster updates, specific markets not covered by aggregators, or want to monitor specific books.

---

## Sharp Market Benchmarks

Before covering individual books, establish your two benchmarks:

### Pinnacle (Sharpest Traditional Book)

Pinnacle accepts large bets from professionals and doesn't ban winners. Their closing lines are the gold standard for measuring Closing Line Value (CLV). Lines available via their official API (requires an account).

```
Base URL: https://api.pinnacle.com/v1/
Auth: HTTP Basic with account credentials
Docs: https://pinnacleapi.github.io/
```

See `odds-apis.md` for full Pinnacle API examples.

**Use Pinnacle lines to:**
- Calculate CLV on your bets
- Identify when other books are "off" relative to the sharp market
- Set your no-vig fair value baseline

```python
def no_vig_prob(home_american: int, away_american: int) -> tuple[float, float]:
    """Remove the vig from a two-way market to get fair probabilities."""
    def to_prob(american: int) -> float:
        if american < 0:
            return -american / (-american + 100)
        return 100 / (american + 100)

    home_raw = to_prob(home_american)
    away_raw = to_prob(away_american)
    total = home_raw + away_raw
    return home_raw / total, away_raw / total
```

### Polymarket (Sharpest Prediction Market)

Polymarket is a decentralized prediction market where contract prices reflect the crowd's probability estimate with real money at stake. It often leads traditional books on injury news and other information.

```
REST: https://clob.polymarket.com / https://gamma-api.polymarket.com
Auth: None required for reading
WebSocket: wss://ws-subscriptions-clob.polymarket.com/ws/
```

See `odds-apis.md` for full Polymarket CLOB API examples.

**Use Polymarket prices to:**
- Detect when traditional books lag on breaking news
- Get a second opinion on fair probability outside the sportsbook ecosystem
- Monitor large trades as a signal of informed money

```python
import requests

def get_polymarket_implied_prob(condition_id: str) -> dict[str, float]:
    """
    Returns {"yes": 0.62, "no": 0.38} for a binary Polymarket market.
    Prices are already implied probabilities (no vig removal needed on midpoints).
    """
    market = requests.get(
        f"https://gamma-api.polymarket.com/markets/{condition_id}",
        timeout=10,
    ).json()
    tokens = market.get("tokens", [])
    result = {}
    for token in tokens:
        token_id = token["token_id"]
        midpoint = requests.get(
            "https://clob.polymarket.com/midpoints",
            params={"token_ids": token_id},
            timeout=10,
        ).json()
        price = float(midpoint.get("mid", {}).get(token_id, 50)) / 100
        result[token["outcome"].lower()] = price
    return result


def polymarket_vs_pinnacle_edge(
    poly_yes_prob: float,
    pinnacle_home_american: int,
    pinnacle_away_american: int,
) -> float:
    """
    Compare Polymarket's YES price to Pinnacle's no-vig home probability.
    Positive value = Polymarket is more optimistic on YES than Pinnacle.
    """
    home_fair, _ = no_vig_prob(pinnacle_home_american, pinnacle_away_american)
    return poly_yes_prob - home_fair
```

---

## US Sportsbook Feeds

### DraftKings

DraftKings uses a JSON API internally. The endpoints are undocumented and subject to change, but have been stable.

```
# Odds for a sport/category
GET https://sportsbook.draftkings.com/sites/US-SB/api/v5/eventgroups/{group_id}/categories/{category_id}?format=json

# Group IDs (partial list):
#   42648 = NFL
#   42808 = NBA
#   84240 = MLB
#   42133 = NHL
```

```python
import requests

DK_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept": "application/json",
    "Referer": "https://sportsbook.draftkings.com/",
}

def get_dk_nba_odds() -> dict:
    # NBA main markets: group 42808, category 583 (game lines)
    url = "https://sportsbook.draftkings.com/sites/US-SB/api/v5/eventgroups/42808/categories/583"
    resp = requests.get(url, headers=DK_HEADERS, params={"format": "json"}, timeout=10)
    resp.raise_for_status()
    return resp.json()
```

**Availability:** Public-facing JSON, no auth required. Subject to change without notice.

---

### FanDuel

FanDuel serves odds via a JSON API used by their web and mobile apps.

```
GET https://sbapi.tn.sportsbook.fanduel.com/api/content-managed-page?page=CUSTOM&customPageId=nba&_ak=FhMFpcPWXMeyZxOx&timezone=America%2FChicago
```

The API key (`_ak` parameter) is embedded in the FanDuel app bundle and is stable across updates but should be verified periodically.

```python
import requests

FD_API_KEY = "FhMFpcPWXMeyZxOx"
FD_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    "Accept": "application/json",
}

def get_fanduel_nba() -> dict:
    url = "https://sbapi.tn.sportsbook.fanduel.com/api/content-managed-page"
    params = {
        "page": "CUSTOM",
        "customPageId": "nba",
        "_ak": FD_API_KEY,
        "timezone": "America/New_York",
    }
    resp = requests.get(url, headers=FD_HEADERS, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()
```

**Availability:** Semi-public, embedded API key. Subject to change.

---

### BetMGM

BetMGM (Roar Digital / Entain) uses a REST API that can be accessed without auth for read operations.

```
GET https://sports.nj.betmgm.com/en/sports/api/widget/widgetdata?layoutSize=Large&page=InPlay&sportId=4&regionId=9&competitionId=&fixtureId=&group=Top&topCount=18&isMobile=false&isAuthenticated=false
```

Parameters vary by state (nj, pa, mi, etc.) and sport. The URL structure: `sports.{state}.betmgm.com`.

```python
import requests

def get_betmgm_live_nba(state: str = "nj") -> dict:
    url = f"https://sports.{state}.betmgm.com/en/sports/api/widget/widgetdata"
    params = {
        "layoutSize": "Large",
        "page": "InPlay",
        "sportId": 4,   # Basketball
        "regionId": 9,  # NBA
        "isMobile": "false",
        "isAuthenticated": "false",
    }
    headers = {"User-Agent": "Mozilla/5.0", "Accept": "application/json"}
    resp = requests.get(url, headers=headers, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()
```

---

### Caesars Sportsbook

Caesars (Kambi platform) provides event feeds that are accessible without auth.

```
GET https://eu-offering.kambicdn.org/offering/v2018/caesarsus/betoffer/event/{event_id}.json?lang=en_US&market=US
GET https://eu-offering.kambicdn.org/offering/v2018/caesarsus/listView/basketball/nba.json?lang=en_US&market=US&onlyMain=true
```

```python
import requests

KAMBI_BASE = "https://eu-offering.kambicdn.org/offering/v2018/caesarsus"

def get_caesars_nba() -> dict:
    url = f"{KAMBI_BASE}/listView/basketball/nba.json"
    params = {"lang": "en_US", "market": "US", "onlyMain": "true"}
    resp = requests.get(url, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()
```

---

### PointsBet

PointsBet was acquired by Fanatics in 2023. Fanatics Sportsbook uses similar internal API patterns. If targeting PointsBet markets, check current availability by state.

---

## Rate Limiting & Proxy Best Practices

### General Rules

1. **Respect robots.txt** — Check before scraping any site
2. **Minimum delay** — Add at least 1–2 seconds between requests to the same host
3. **Randomize delays** — Use `random.uniform(1.0, 3.0)` to avoid fingerprinting
4. **Cache aggressively** — Odds don't need re-fetching every second; 30–60 second TTLs are usually fine
5. **Use realistic headers** — Include `User-Agent`, `Accept`, `Referer` matching a real browser

```python
import time
import random
import requests
from functools import wraps
from typing import Callable

def rate_limited(min_delay: float = 1.0, max_delay: float = 3.0):
    def decorator(fn: Callable) -> Callable:
        @wraps(fn)
        def wrapper(*args, **kwargs):
            result = fn(*args, **kwargs)
            time.sleep(random.uniform(min_delay, max_delay))
            return result
        return wrapper
    return decorator


class BookScraper:
    def __init__(self, proxies: list[str] | None = None):
        self.proxies = proxies or []
        self._proxy_idx = 0
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) "
                          "Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
        })

    def _get_proxy(self) -> dict | None:
        if not self.proxies:
            return None
        proxy = self.proxies[self._proxy_idx % len(self.proxies)]
        self._proxy_idx += 1
        return {"http": proxy, "https": proxy}

    @rate_limited(1.5, 4.0)
    def get(self, url: str, **kwargs) -> requests.Response:
        kwargs.setdefault("timeout", 15)
        kwargs.setdefault("proxies", self._get_proxy())
        return self.session.get(url, **kwargs)
```

### Proxy Providers

For high-frequency scraping, residential proxies reduce the risk of IP bans:
- **Smartproxy** — Residential, ~$12.50/GB
- **Oxylabs** — Enterprise residential
- **Bright Data** (Luminati) — Most extensive, most expensive

For moderate scraping, a basic datacenter proxy pool is usually sufficient.

### Caching Layer

```python
import json
import hashlib
import time
from pathlib import Path

CACHE_DIR = Path("~/.syndicate/odds-cache").expanduser()
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def cached_get(url: str, params: dict, ttl_seconds: int = 60) -> dict:
    key = hashlib.md5(f"{url}{json.dumps(params, sort_keys=True)}".encode()).hexdigest()
    cache_file = CACHE_DIR / f"{key}.json"

    if cache_file.exists():
        data = json.loads(cache_file.read_text())
        if time.time() - data["_cached_at"] < ttl_seconds:
            return data["payload"]

    resp = requests.get(url, params=params, timeout=15)
    resp.raise_for_status()
    payload = resp.json()

    cache_file.write_text(json.dumps({"payload": payload, "_cached_at": time.time()}))
    return payload
```

---

## Legal Considerations

### Scraping

- **Terms of Service** — Most sportsbooks prohibit automated access in their ToS. Scraping for personal research/modeling is a legal gray area in the US; commercial use of scraped data carries higher risk.
- **Computer Fraud and Abuse Act (CFAA)** — Accessing systems in violation of ToS could theoretically implicate the CFAA, though enforcement against individual researchers is rare. Avoid anything that bypasses authentication or access controls.
- **Copyright** — Odds data itself is generally not copyrightable (facts are not protected), but database compilations can be in some jurisdictions.

### Recommendations

- Prefer official APIs and aggregators (The Odds API, Sportradar) where possible
- Use scraped data only for personal research and modeling
- Do not redistribute scraped data commercially
- Do not circumvent bot detection, CAPTCHAs, or login walls
- If in doubt, contact the platform to ask about data licensing

### Prediction Markets

Polymarket is a CFTC-regulated exchange for US users (with restrictions). Using their public API for research purposes is explicitly permitted. The data is public by design.

---

## Recommended Data Architecture

```
Polymarket CLOB API ─────┐
                         ├──► Probability Aggregator ──► Model Input
Pinnacle API ────────────┤         (weighted blend)
                         │
The Odds API ────────────┘

DraftKings/FanDuel/etc ──────────► Line Shopping Layer ──► Bet Execution
```

1. Use **Pinnacle** and **Polymarket** as your two independent "truth" sources for fair probability
2. Use **The Odds API** or direct feeds to find the best available price across retail books
3. Only bet when retail price offers positive expected value vs. your blended probability estimate
