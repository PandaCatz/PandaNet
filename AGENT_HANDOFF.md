# AGENT_HANDOFF — deploy and integrate PandaNet

Audience: an autonomous integration agent (or engineer) taking this package to
a real server for the TipTap Games service. Everything needed is in this
folder; there are no external dependencies to fetch and no package manager
involved. Follow the steps in order; every step has a verification command
with its expected output.

## 0. Package inventory

| File | Purpose |
|---|---|
| `server.js` | HTTP API: identity, daily seed + events, runs, boards, ghosts, admin, WS tickets. Single process entrypoint. |
| `mp.js` | Realtime layer required by server.js: RFC 6455 WebSocket server + room manager (quickmatch, private codes, synchronized starts, state relay, results). |
| `client-sdk.js` | Browser SDK for direct mode; also documents the client half of every flow. Served at `/client-sdk.js`. |
| `demo.html` | Interactive console exercising every endpoint incl. a scripted rival bot for multiplayer. Served at `/`. |
| `test.js` | 65-assertion end-to-end suite. Spawns its own scratch server + DB; safe to run anywhere, touches nothing outside this folder. |
| `deploy/setup.sh` | One-shot Ubuntu 24.04 provisioner (Node 22, Caddy TLS, systemd, ufw, backups). |
| `deploy/pandanet.service` | Hardened systemd unit. |
| `deploy/Caddyfile` | TLS + reverse proxy (WebSocket passes through automatically). |
| `deploy/backup.sh` | Nightly SQLite online backup, 14-day rotation. |
| `deploy/restore.sh` | Safe restore (stops service, clears WAL sidecars, integrity-checks). |
| `PROPOSAL.md` | The design rationale and platform-integration pitch. Read it first for context. |
| `README.md` | Feature overview and capacity numbers. |

Runtime contract: **Node >= 22.5** (uses built-in `node:sqlite`; the
`ExperimentalWarning` it prints on stderr is expected and harmless). No npm
install, ever. State is one SQLite file in WAL mode.

## 1. Verify the package before deploying

On any machine with Node 22+:

```bash
node --version        # must print v22.5.0 or later
node test.js          # from inside the server/ folder
```

Expected: lines of `ok ...` ending in exactly `65 passed, 0 failed`, exit
code 0. Takes ~15 s (contains real countdowns and wall-clock checks). Do not
proceed on any failure.

## 2. Environment variable contract

| Var | Required | Meaning |
|---|---|---|
| `PORT` | no (8324) | HTTP + WebSocket listen port. |
| `HOST` | no (127.0.0.1) | Bind address. Defaults to loopback so the app port is never exposed directly; set `0.0.0.0` only for containers or a proxy on another host. |
| `DB` | yes in prod | Absolute path to the SQLite file. Parent dir must be writable by the service user. |
| `ADMIN_KEY` | yes | Bearer for `/api/admin/*` (sent as `X-Admin-Key`). Empty string disables admin endpoints entirely. |
| `SEED_KEY` | yes | HMAC key from which every game's daily seed is derived. **Changing it changes every daily seed**; set once, back it up, never rotate mid-day. |
| `PROXY_KEY` | for platform mode | Shared secret the platform proxy presents in `X-Proxy-Key`. Unset = direct mode only. |
| `TRUST_PROXY` | `1` behind Caddy | Trust the first `X-Forwarded-For` entry for rate limiting. |
| `MP_DEBUG` | debug only | `1` logs every inbound multiplayer message to stderr. |

## 3. Deploy (Ubuntu 24.04 VPS, ~10 minutes)

Preconditions: root shell; DNS A record for the chosen domain pointing at the
VPS; ports 80/443 reachable.

```bash
# copy the server/ folder to the box, then:
cd server/deploy
bash setup.sh api.yourdomain.tld
```

The script is idempotent (safe to re-run). It installs Node 22 (NodeSource)
and Caddy (official repo), creates the `pandanet` system user, generates
`ADMIN_KEY`/`SEED_KEY`/`PROXY_KEY` into `/opt/pandanet/env` (chmod 600),
starts the hardened service, configures the firewall (22/80/443 only), and
installs the nightly backup cron. The app itself binds `127.0.0.1` by default,
so the API is reachable only through Caddy regardless of firewall state.

Verify, in order:

```bash
systemctl status pandanet --no-pager     # expect: active (running)
curl -s http://127.0.0.1:8324/api/health # expect: {"ok":true,...}
curl -s https://api.yourdomain.tld/api/health
# expect: {"ok":true,"day":"YYYY-MM-DD","players":0,"games":0,"sockets":0,"rooms":0}
```

WebSocket check (from any machine with Node 22):

```bash
node -e "const ws=new WebSocket('wss://api.yourdomain.tld/ws?ticket=nope');ws.onerror=()=>console.log('OK: relay reachable, bad ticket refused');ws.onopen=()=>console.log('FAIL: accepted a bad ticket')"
```

Optionally open `https://api.yourdomain.tld/` and click through the demo
console — including "connect", "host private room", then "spawn rival bot",
which plays a full race against you.

## 4. Onboard a game

Each game is a namespace; nothing needs pre-registration except (optionally)
its tuning. `ADMIN_KEY` below is from `/opt/pandanet/env`.

```bash
# per-game tuning (all fields optional; defaults shown):
curl -s -X POST https://api.yourdomain.tld/api/admin/game \
  -H "X-Admin-Key: $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"game":"pandacat","cfg":{"scoreMax":999999,"minMs":4000,"maxMs":92000,"capBase":5000,"capPerRoom":6000}}'
```

Config semantics: `scoreMax` rejects, `minMs`/`maxMs` bound the claimed run
duration, and a score above `capBase + rooms*capPerRoom` is **accepted but
flagged off-board** (review-friendly: false positives never destroy a run).
`rooms` is the game's own progress metric (depth, waves, level — any integer
0-200).

Schedule a live event (served with the daily seed; games interpret `data`):

```bash
curl -s -X POST https://api.yourdomain.tld/api/admin/event \
  -H "X-Admin-Key: $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"game":"pandacat","startDay":"2026-08-07","endDay":"2026-08-09","data":{"mod":"double_coins","motd":"Weekend event!"}}'
```

## 5. Platform integration (proxy mode — the intended production shape)

The platform's server-side proxy calls the same endpoints as direct clients,
adding three headers and **omitting** `playerId`/`ts`/`sig` from bodies:

```
X-Proxy-Key:    <PROXY_KEY from the env file>
X-Player-Id:    <stable pseudonymous id, [\w:-]{1,64}, e.g. "tt:abc123">
X-Player-Name:  <display name, optional; ASCII, truncated to 16>
```

Trust rules the backend enforces: a valid `X-Proxy-Key` makes the headers
authoritative (player row auto-provisioned); an *invalid* key is rejected
outright, never downgraded to direct mode. Direct-mode requests (no proxy
header) still work unless you firewall them off.

Full scoring flow, proxied:

```bash
B=https://api.yourdomain.tld; K="X-Proxy-Key: $PROXY_KEY"
curl -s -X POST $B/api/run/start  -H "$K" -H 'X-Player-Id: tt:p1' -H 'X-Player-Name: Cat' \
  -H 'Content-Type: application/json' -d '{"game":"pandacat"}'
# -> {"runId":"...","day":"YYYY-MM-DD","seed":"<64 hex>"}
#    Play THAT seed: it is the board this run will be scored against, which
#    matters for a run that crosses UTC midnight.  ... player plays for real ...
curl -s -X POST $B/api/run/finish -H "$K" -H 'X-Player-Id: tt:p1' \
  -H 'Content-Type: application/json' \
  -d '{"runId":"<runId>","score":12345,"rooms":6,"durMs":88000,"log":"<base64, optional>"}'
# -> {"ok":true,"flagged":false,"best":true,"rank":1,"total":1}
```

Reads (`/api/daily`, `/api/board`, `/api/ghost`) are unauthenticated GETs.
For multiplayer, the proxy POSTs `/api/mp/ticket` (same headers, body
`{"game":"..."}`), hands the one-time ticket to the client, and the client's
`wss://.../ws?ticket=...` connection can be tunneled or direct — tickets are
single-use and expire in 60 s. The full message protocol is documented at the
top of `mp.js`, and `client-sdk.js` `connect()` is a working reference client.

**Production hardening (do before real launch, in this order):**

1. Replace the static `X-Proxy-Key` with a per-request HMAC
   (`X-Proxy-Sig = HMAC(secret, timestamp|method|path|bodyHash)` + timestamp
   header, verified with the same `SIG_WINDOW_MS` freshness rule the direct
   mode already uses). The static key is fine over TLS for a pilot.
2. If direct mode is unwanted in production, firewall the API to accept only
   the platform proxy's IPs (Caddy `@denied not remote_ip ...` or ufw).
3. Per-player rate limits at the proxy. The backend already handles the
   collapse case itself: a request that authenticates with `PROXY_KEY` is
   rate-limited on the vouched `X-Player-Id` rather than the source IP, because
   behind a proxy every request shares one address and an IP bucket would
   throttle the entire service to a single player's 60 req/min budget. Set
   `TRUST_PROXY=1` so *direct-mode* requests still key on the forwarded IP.

## 6. Operations

- **Logs:** `journalctl -u pandanet -f`. Multiplayer message tracing: add
  `Environment=MP_DEBUG=1` to the unit, `systemctl daemon-reload && systemctl
  restart pandanet` (verbose — debug only).
- **Backups:** nightly gzip'd SQLite online backups in
  `/opt/pandanet/data/backups`, 14-day rotation. Offsite: uncomment the rclone
  line in `backup.sh`.
- **Restore:** use `deploy/restore.sh <backup.db.gz>` — do not hand-roll it.
  Copying a backup over `$DB` while the old `-wal`/`-shm` sidecars are still
  present makes SQLite replay the *previous* database's write-ahead log onto
  the restored file, which corrupts it instead of rolling back. The script
  stops the service, preserves the live database under a timestamped name,
  deletes the sidecars, restores, runs `PRAGMA integrity_check`, and restarts.
- **Upgrade:** copy new `server.js`/`mp.js` over `/opt/pandanet/`,
  `systemctl restart pandanet`. SQLite schema uses `CREATE TABLE IF NOT
  EXISTS` only — additive migrations need explicit `ALTER TABLE` statements
  shipped in the new code.
- **Data growth:** ~100 B per score row, one ≤64 KB ghost per game per day.
  Tens of MB per year at hobby-platform scale. `MemoryMax=256M` in the unit
  is generous headroom; the process idles near 60 MB.

## 7. Known limits (by design, documented for honesty)

- Single node, single SQLite writer. Fine for hundreds of req/s; shard by
  `game` if the service ever outgrows one box.
- Relay race results are informational; authoritative scoring is only the
  signed/proxied HTTP finish flow.
- A modified client can still lie about its own play (all client-side games
  share this). Flagged-run review + future input-log re-simulation is the
  mitigation path; the ghost pipeline already stores the logs.
- Rooms hold 2–4 players (`MAX_ROOM` in mp.js); no spectators; no chat (a
  deliberate moderation-surface choice — add only with platform-level tooling).
- One WebSocket per player id; a new connection displaces the old one
  (verified by the test suite).

## 8. Acceptance checklist

- [ ] `node test.js` → `65 passed, 0 failed` on the target box
- [ ] `https://<domain>/api/health` returns `ok:true` with valid TLS
- [ ] Demo console: hello → start → finish → board shows the run
- [ ] Demo console: connect → host → spawn rival bot → live states stream → result board appears
- [ ] Proxied `run/start` + `run/finish` with `X-Proxy-Key` lands on the board
- [ ] `systemctl restart pandanet` recovers cleanly; health still `ok:true`
- [ ] A backup file appears in `/opt/pandanet/data/backups` after `bash /opt/pandanet/backup.sh`
