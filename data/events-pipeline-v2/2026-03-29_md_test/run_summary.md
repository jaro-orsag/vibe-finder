# Run Summary: 2026-03-29_md_test

**Run date:** 2026-03-29  
**Generated at:** 2026-03-29T16:54:59.011275Z

## Source Metrics

| Source | Events | Pages visited | Failures | Duration (ms) |
|--------|-------:|-------------:|---------:|--------------:|
| CITYLIFE Bratislava Events | 1 | 80 | 0 | 190727 |
| Kam do mesta Bratislava | 252 | 80 | 0 | 149577 |
| Kam do mesta Bratislava | 22 | 1 | 0 | 1710 |
| Visit Bratislava Events | 1 | 80 | 3 | 254545 |
| Zoznam Events Aggregation | 104 | 28 | 0 | 41986 |
| **TOTAL** | **380** | | **3** | |

## Failures

### By Category

| Category | Count | Description |
|----------|------:|-------------|
| FETCH_ERROR | 3 | HTTP error or network-level failure when fetching a URL (e.g. connection refused, 4xx/5xx response) |

### By Source

| Source | Category | Count |
|--------|----------|------:|
| src_visitbratislava_events | FETCH_ERROR | 3 |

### Failure Details

| Source | Category | URL | Message |
|--------|----------|-----|---------|
| src_visitbratislava_events | FETCH_ERROR | https://www.visitbratislava.com/events-and-festivals | HTTP 404 |
| src_visitbratislava_events | FETCH_ERROR | https://www.visitbratislava.com/place-categories/attraction | HTTP 404 |
| src_visitbratislava_events | FETCH_ERROR | https://www.visitbratislava.com/events/recommended | HTTP 404 |

