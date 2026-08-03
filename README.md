# PandaNet — an online layer for TipTap games on a $4–6/mo VPS

[![CI](https://github.com/PandaCatz/PandaNet/actions/workflows/ci.yml/badge.svg)](https://github.com/PandaCatz/PandaNet/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%E2%89%A522.5-brightgreen.svg)](https://nodejs.org)
[![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)](#)

A dependency-free Node backend (built-in `node:sqlite`, nothing to `npm
install`) that gives TipTap games a real online side — built multi-tenant so
one box can serve the **entire service**, not one game:

| Feature | How |
|---|---|
| Global boards | daily + all-time per game, top-50 + around-me rank |
| Daily seed + live events | `GET /api/daily?game=` → `{date, seed, event}`; seed is `HMAC(SEED_KEY, game|date)`, events are date-ranged JSON posted via admin ("double coins this weekend", MOTD) |
| Ghost racing | the day's best run's **input log** (gzipped, ≤64 KB) stored per game and served to everyone — deterministic fixed-step games replay it as a live translucent rival for ~5 KB |
| **Realtime multiplayer** | hand-rolled RFC 6455 WebSocket relay + room manager: quickmatch and 4-letter private codes, synchronized countdown starts on a shared seed, live opaque state fan-out (≤512 B at ~10–15 Hz), race results, rematches, disconnect handling. The server never simulates gameplay — it relays — so it stays tiny |
| Identity | accountless direct mode (server-issued `{playerId, secret}`, HMAC-signed requests) **and** platform-proxy mode (`X-Proxy-Key` + platform-vouched `X-Player-Id` — no client secrets anywhere) |
| Anti-cheat | one-time run tokens, wall-clock cross-checks, per-game plausibility caps; implausible runs are stored but flagged off-board so false positives never eat a run |

> **Reality check (do not skip):** today's TipTap validator bans `fetch`, XHR,
> and WebSocket outright — `tools/audit-tiptap.js` §1 enforces the same rule
> locally. Nothing here may be concatenated into a shipped game until the
> platform provides a mediated bridge. [PROPOSAL.md](PROPOSAL.md) is the pitch
> for exactly that, with the sandbox left fully intact; proxy mode is that
> integration, working today.

## Quick start

```bash
node server.js        # http://localhost:8324 — demo console at /
node test.js          # 65-assertion end-to-end suite (HTTP + live 2-socket race)
```

The demo console exercises everything, including a scripted rival bot that
joins your multiplayer room and plays a race against you.

## Deploying / integrating

**[AGENT_HANDOFF.md](AGENT_HANDOFF.md)** is the operational document: package
inventory, environment contract, one-shot Ubuntu provisioning
(`deploy/setup.sh` — Node 22, Caddy auto-TLS, hardened systemd, firewall,
nightly backups), per-game onboarding, the platform-proxy header contract with
curl examples, hardening order, and an acceptance checklist. It is written so
an integration agent can deploy and verify end-to-end without asking anything.

## Capacity on a 1 vCPU / 1 GB box

Every HTTP request is a sub-millisecond indexed SQLite read/write in WAL mode;
a scoring player generates ~4 requests per 90-second run. A race relays ~30
tiny messages/second per room; sockets cost a few KB each. Hundreds of HTTP
requests/second and thousands of concurrent sockets fit — the early volume of
the whole service. Storage: ~100 B per score row, one ghost per game per day —
years of traffic in tens of MB. Single-node by design; the `game` key is the
shard axis if it ever outgrows one box.

## Anti-cheat: what it stops, honestly

Stops cold: forged/replayed submissions (one-time run tokens + HMAC or
platform vouching), score tampering, "90-second runs" finished in 3 seconds
(wall-clock cross-check), absurd score/progress ratios (flagged off-board,
reviewable). Does **not** stop a modified client lying about its own play —
no client-side game architecture can. The path there is server-side
re-simulation of flagged runs from their input logs; the ghost pipeline
already stores exactly those logs.

## Wiring into a game (when the bridge exists)

`client-sdk.js` is the reference client for both modes. Its failure contract:
**every method resolves, never rejects** — a failure or an unavailable server
returns `null`, so nothing can throw into a game loop and offline play is
untouched. `PandaNet.onError(cb)` surfaces what failed, and
`PandaNet.pendingRun` tells you a score has not been banked yet so the game can
retry `finishRun()` instead of losing it. For PandaCat
specifically: identity persists in the saveState blob (~60 B of the 8 KB cap),
`startRun()` at `GAME.start('contract')`, `finishRun()` inside the existing
submit-once guard, input recording is `[tick, buttonMask]` pairs on change
(the determinism the reach-bot already relies on), and rivals render as
translucent hero instances fed relayed state instead of live input.

## Files

- `server.js` — HTTP API + static demo hosting (entrypoint)
- `mp.js` — WebSocket relay + room manager (required by server.js)
- `client-sdk.js` — browser SDK (WebCrypto HMAC, WS client; resolves-or-null, never throws)
- `demo.html` — interactive console incl. multiplayer rival bot
- `test.js` — end-to-end suite; expect `65 passed, 0 failed`
- `deploy/` — `setup.sh`, systemd unit, Caddyfile, backup + restore scripts
- `PROPOSAL.md` — platform pitch: mediated `TipTap.net` bridge, sandbox intact
- `AGENT_HANDOFF.md` — deploy/integration runbook for an autonomous agent
- `SECURITY.md` — threat model, disclosure policy, accepted limits

## Security

Clients are untrusted; every scoring write is either HMAC-signed over a
canonical string with a fresh timestamp, or vouched for by the platform proxy.
Run tokens are single-use, wall-clock-checked, day-bound, and capped by
per-game plausibility limits. The server never executes or simulates game
code — multiplayer state blobs are opaque and relayed, never interpreted.

The code has been through four adversarial review passes; the last was a
48-agent audit whose 26 surviving findings are all fixed and pinned by
regression tests. Read [SECURITY.md](SECURITY.md) for the full threat model,
the documented accepted limits, and how to report a vulnerability privately.

`node test.js` must print `65 passed, 0 failed` — CI enforces exactly that
string on every push, so a truncated or crashed run cannot pass as green.

## License

GPL-3.0. If TipTap wants this under different terms for first-party use, ask —
the intent is for the platform to be able to run it.
