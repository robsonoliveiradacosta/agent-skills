---
name: add-load-testing
description: "Add k6 load testing to a Quarkus REST API — generates k6 scripts derived from the project's OpenAPI spec covering the most-used endpoints, a ramp-up / steady / spike scenario, thresholds (p95 latency, error rate, request rate) that fail the run if violated, a docker-compose service to run k6 locally against the stack, and a nightly GitHub Actions job that runs the test against a deployed environment and compares results with a baseline. Use when the user asks for load testing, performance testing, k6, stress test, \"how many requests can we handle\", or wants a perf budget per endpoint."
---

# add-load-testing

Add **k6** (Grafana's load testing tool) with scripts that exercise real endpoints, enforce a performance budget, and compare results across runs. The goal is a baseline + regression detection, not a 100x stress test.

## When to invoke

- "Add load tests"
- "What's our p95 latency?"
- "Set up a performance budget"

## Inputs to collect

| Input | Default |
|---|---|
| Target environment | `localhost:8080` (local) or a staging URL |
| Authentication | use the JWT from `/auth/login` flow (recommended) or a pre-generated token |
| Top endpoints to test | derive from OpenAPI; let user override |
| Ramp profile | `ramp_up: 1m → 50 vus, steady: 5m, ramp_down: 1m` |
| p95 latency budget | `< 500ms` |
| Error rate budget | `< 1%` |
| Run in CI? | nightly only — not on every PR |

> Always test against a **dedicated** environment. Loading shared dev infrastructure can break other people's work.

## Directory layout

```
load-tests/
├── README.md
├── auth.js                  # helper: POST /auth/login → JWT
├── scenarios/
│   ├── smoke.js             # 1 VU, 1 minute — sanity
│   ├── load.js              # baseline — ramp-up, steady, ramp-down
│   └── spike.js             # sudden burst — capacity check
├── baselines/
│   └── load.json            # last accepted run's metrics — gitignored or LFS
└── docker-compose.k6.yml    # optional, runs k6 against compose stack
```

## Files to generate

### `load-tests/auth.js`

```javascript
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

/** Returns a fresh JWT or throws. Cached per VU iteration. */
export function login() {
  const res = http.post(
    `${BASE}/v1/auth/login`,
    JSON.stringify({
      username: __ENV.USER || 'admin',
      password: __ENV.PASS || 'admin123',
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'login ok': r => r.status === 200 });
  return res.json('token');
}

export function authHeaders(token) {
  return { headers: { Authorization: `Bearer ${token}` } };
}
```

> **Critical**: don't log in every iteration — JWT issuance is expensive. Login once in `setup()` and reuse the token across the run.

### `load-tests/scenarios/load.js`

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { login, authHeaders } from '../auth.js';

const errors = new Rate('errors');
const albumListLatency = new Trend('album_list_latency');

export const options = {
  scenarios: {
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 50 },   // ramp up
        { duration: '5m', target: 50 },   // steady
        { duration: '1m', target: 0 },    // ramp down
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.01'],            // <1% errors
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors:            ['rate<0.01'],
    album_list_latency: ['p(95)<300'],           // tighter for hot endpoint
  },
  // Tags every metric with the test name — useful when several scenarios share a Grafana dashboard.
  tags: { test_id: 'load-baseline' },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export function setup() {
  return { token: login() };
}

export default function (data) {
  const headers = authHeaders(data.token);

  // 70% of traffic: list albums
  if (Math.random() < 0.7) {
    const res = http.get(`${BASE}/v1/albums?page=0&size=20`, headers);
    albumListLatency.add(res.timings.duration);
    errors.add(res.status >= 400);
    check(res, { 'albums 200': r => r.status === 200 });
  } else {
    const id = randomId(1, 100);
    const res = http.get(`${BASE}/v1/albums/${id}`, headers);
    errors.add(res.status >= 500);  // 404 is expected for random IDs, don't count
  }

  sleep(Math.random() * 2);
}

function randomId(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
```

> Two metrics philosophy: `http_req_*` are k6 built-ins (overall). Custom `Trend` per critical endpoint surfaces regressions that the global p95 might hide.

### `load-tests/scenarios/spike.js`

```javascript
import http from 'k6/http';
import { Rate } from 'k6/metrics';
import { login, authHeaders } from '../auth.js';

const errors = new Rate('errors');

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 500,
      stages: [
        { duration: '30s', target: 10 },    // baseline
        { duration: '10s', target: 500 },   // spike
        { duration: '1m',  target: 500 },   // hold
        { duration: '10s', target: 10 },    // recover
      ],
    },
  },
  thresholds: {
    // During a spike, allow more errors but never a meltdown
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export function setup() { return { token: login() }; }

export default function (data) {
  http.get(`${BASE}/v1/albums?page=0&size=20`, authHeaders(data.token));
}
```

### `load-tests/scenarios/smoke.js`

```javascript
import http from 'k6/http';
import { check } from 'k6';
import { login, authHeaders } from '../auth.js';

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<1000'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export function setup() { return { token: login() }; }

export default function (data) {
  const headers = authHeaders(data.token);
  check(http.get(`${BASE}/q/health`),                   { 'health 200': r => r.status === 200 });
  check(http.get(`${BASE}/v1/albums`, headers),     { 'albums 200': r => r.status === 200 });
  check(http.get(`${BASE}/v1/artists`, headers),    { 'artists 200': r => r.status === 200 });
}
```

> `smoke.js` is what you run on every deploy — fast, low load, catches "the new build doesn't even start" before `load.js` wastes 7 minutes.

### `docker-compose.k6.yml` (optional)

```yaml
services:
  k6:
    image: grafana/k6:0.55.0
    network_mode: host
    volumes:
      - ./load-tests:/scripts
    environment:
      BASE_URL: http://localhost:8080
      USER: admin
      PASS: admin123
    command: ["run", "/scripts/scenarios/load.js"]
    profiles: ["loadtest"]   # only runs with --profile loadtest
```

Run: `docker compose --profile loadtest run --rm k6 run /scripts/scenarios/load.js`.

### CI integration — `.github/workflows/load-test.yml`

```yaml
name: Load test (nightly)

on:
  schedule:
    - cron: '0 3 * * *'   # 03:00 UTC every day
  workflow_dispatch:       # manual trigger

jobs:
  load:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install -y k6

      - name: Run load test against staging
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}
          USER:     ${{ secrets.LOAD_TEST_USER }}
          PASS:     ${{ secrets.LOAD_TEST_PASS }}
        run: |
          k6 run --out json=results.json load-tests/scenarios/load.js

      - name: Compare with baseline
        run: |
          # Compare key metrics to the committed baseline
          node load-tests/compare.js results.json load-tests/baselines/load.json
          # compare.js: fails with non-zero if p95/p99/error_rate degraded > 10%

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: k6-results-${{ github.run_id }}
          path: |
            results.json
            summary.html
```

## Comparing runs (`compare.js`)

Generate a small Node script that:
1. Reads two k6 JSON outputs.
2. Extracts `http_req_duration` p50/p95/p99, `http_req_failed` rate, throughput.
3. Fails if any degraded > **threshold** vs baseline (default 10%).
4. Prints a diff table to the run log.

Keep the implementation in `load-tests/compare.js`. Two dozen lines of `JSON.parse` + comparison — no extra deps.

## Anti-patterns to refuse

- **Load testing on the user's laptop and reporting numbers.** Single-machine k6 maxes out the laptop's CPU/network before the server. Always run from a dedicated runner or cloud-hosted k6.
- **Logging in on every iteration.** Pre-fetch the token in `setup()`.
- **Treating 4xx as failure.** Some 4xx are expected (e.g. random ID lookups returning 404). Use `errors.add(status >= 500)`.
- **Running load tests against production without coordination.** Rate-limited APIs, downstream blast, on-call confusion. Always staging.
- **No thresholds.** Without thresholds, k6 always "passes" — the run produces numbers but no signal.
- **One mega-scenario script.** Smoke / load / spike each test a different question. Keep them separate.

## Post-generation

- Run `smoke.js` locally first; ensure it passes against `localhost:8080`.
- Run `load.js` once and commit the resulting metrics to `load-tests/baselines/load.json` as the initial baseline.
- Add `STAGING_URL`, `LOAD_TEST_USER`, `LOAD_TEST_PASS` to GitHub Actions secrets.
- Tell the user: the **first** nightly run after a config change will look like a regression because the baseline hasn't moved — update the baseline deliberately when intended changes ship.

---

## Strategic considerations & governance

## Goal

Design performance tests that answer a concrete operational question instead of producing vanity numbers.

## Workflow

1. Define the scenario: endpoint mix, user role, data volume, request rate, duration, and environment.
2. Set measurable targets: p95, p99, error rate, throughput, CPU, memory, database connections, and external dependency impact.
3. Prepare representative test data and authentication tokens.
4. Run smoke load first, then baseline, load, stress, and soak tests as needed.
5. Capture results, bottlenecks, environment details, and tuning recommendations.

## Scenario Types

- Smoke: low traffic to verify scripts and environment.
- Baseline: expected normal traffic.
- Load: expected peak traffic.
- Stress: beyond expected peak to find failure mode.
- Soak: sustained traffic to find leaks and resource exhaustion.

## Quality Rules

- Do not compare results from different environments without noting the difference.
- Keep external APIs stubbed unless the test explicitly covers them.
- Record dataset size and warm-up behavior.

## Example

For album listing, test authenticated reads with filters and sorting over realistic album and artist counts, and track p95 latency, database connections, and error rate.
