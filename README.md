<div align="center">

# 🐼 PandaNet

### The online layer for arcade games — leaderboards, ghosts, live events, and realtime races on a $5 VPS

[![CI](https://github.com/PandaCatz/PandaNet/actions/workflows/ci.yml/badge.svg)](https://github.com/PandaCatz/PandaNet/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-67%20passing-brightgreen.svg)](test.js)
[![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)](#zero-dependencies)
[![Node](https://img.shields.io/badge/node-%E2%89%A5%2022.5-339933.svg?logo=node.js&logoColor=white)](https://nodejs.org)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Hosting](https://img.shields.io/badge/hosting-%244–6%2Fmo-orange.svg)](#deploy-in-10-minutes)

**Zero dependencies. One file to deploy. Multi-tenant from day one.**

</div>

---

## What this is

PandaNet is a small, complete backend that gives browser games the online
features players expect — and it runs comfortably on the cheapest VPS you can
rent.

Most small arcade games are islands. A player finishes a run, sees a number,
and that's the end of it. There's no board to climb, no rival to chase, no
reason the game feels different on a Tuesday than it did on Monday. Building
the server that fixes this is usually more work than building the game.

This is that server, already built. Point a game at it and you get global
leaderboards, a daily seed everyone shares, server-pushed events, ghost
racing against the day's best run, and realtime multiplayer rooms.

It is **multi-tenant**: every table and endpoint is keyed by a game id, with
per-game tuning. One box serves an entire catalogue of games, not one.

```
   ┌──────────┐   HMAC-signed HTTPS    ┌──────────┐
   │   Game   │ ─────────────────────► │ PandaNet │  boards · seeds · events
   │  client  │ ◄───────────────────── │          │  ghosts · rooms
   └──────────┘   WebSocket (wss)      └────┬─────┘
                                            │
                                      SQLite (WAL)
```

## Features

| | Feature | What it does |
|---|---|---|
| 🏆 | **Global leaderboards** | Daily and all-time boards per game, top 50 plus the player's own rank. Ties share a rank, and every response is internally consistent. |
| 🎲 | **Server-authoritative daily seed** | `HMAC(SEED_KEY, game·date)` — every player gets the same board today, and nobody can fake tomorrow's. |
| 📣 | **Live events** | Push "double coins this weekend" or a message-of-the-day as date-ranged JSON. No client update, no redeploy. |
| 👻 | **Ghost racing** | The day's best run's **input log** (gzipped, ≤64 KB) is stored and served to everyone. A deterministic game replays it as a live rival for a few KB. |
| ⚔️ | **Realtime multiplayer** | Quickmatch or 4-letter private room codes, synchronized countdown starts on a shared seed, live opponent state at 10–15 Hz, results, rematches, disconnect handling. |
| 🪪 | **Two identity modes** | Accountless (server-issued keypair, HMAC-signed requests) **or** platform-vouched (a trusted proxy asserts identity — no client ever holds a secret). |
| 🛡️ | **Anti-cheat** | Single-use run tokens, wall-clock cross-checks, day-bound tokens, per-game plausibility caps. Suspicious runs are stored but held off the board, so a false positive never destroys a real run. |

## Zero dependencies

There is no `package.json`, no `npm install`, and no build step. PandaNet uses
only Node 22 built-ins — including `node:sqlite` for storage and a hand-written
RFC 6455 implementation for WebSockets.

That is a deliberate operational choice. Nothing to audit for supply-chain
risk, nothing to break on a version bump, nothing to rebuild at 2am. Copy three
files to a box and run them.

```bash
git clone https://github.com/PandaCatz/PandaNet.git
cd PandaNet
node server.js       # http://localhost:8324 — interactive demo console at /
node test.js         # 67-assertion end-to-end suite
```

The demo console at `/` drives every endpoint through the real client SDK,
including a scripted rival bot that joins your room and races you — so you can
see multiplayer working before writing a line of game code.

## API

Reads are plain unauthenticated `GET`s. Writes are signed, or vouched for by a
trusted proxy.

| Endpoint | Purpose |
|---|---|
| `POST /api/hello` | Create or refresh an identity |
| `GET /api/daily?game=` | Today's seed, date, and any active event |
| `POST /api/run/start` | Mint a single-use run token; returns the day and seed it is filed under |
| `POST /api/run/finish` | Submit a score (+ optional ghost input log) |
| `GET /api/board?game=&scope=` | Daily or all-time board, optionally with the caller's rank |
| `GET /api/ghost?game=` | The day's best run's input log |
| `POST /api/mp/ticket` | Single-use, 60-second WebSocket ticket |
| `GET /ws?ticket=` | Realtime relay: rooms, starts, state, results |
| `POST /api/admin/game` | Per-game tuning (score caps, run-length bounds) |
| `POST /api/admin/event` | Schedule a live event |
| `GET /api/health` | Liveness, player/game counts, live socket and room counts |

`client-sdk.js` is the reference browser client for all of it. Its failure
contract is strict: **every method resolves, never rejects.** A failure returns
`null`, so nothing can throw into a game loop, and offline play is untouched.
`PandaNet.pendingRun` tells you a score hasn't been banked yet so you can retry
rather than lose it.

```js
PandaNet.configure('https://api.example.com', 'my-game');
await PandaNet.hello(savedIdentity);
const { seed, event } = await PandaNet.daily();
await PandaNet.startRun();
// ... player plays ...
await PandaNet.finishRun({ score, rooms, durMs, log });
```

## Deploy in 10 minutes

One script on a fresh Ubuntu 24.04 box:

```bash
cd deploy && bash setup.sh api.yourdomain.tld
```

It installs Node 22 and Caddy, creates a locked-down service account,
generates secrets, starts a hardened systemd unit, configures the firewall,
and installs nightly backups with rotation. TLS is automatic via Let's Encrypt.
The app binds loopback only and is reachable solely through the proxy.

**[AGENT_HANDOFF.md](AGENT_HANDOFF.md)** is the full runbook — environment
contract, per-game onboarding, the proxy header spec, hardening order, and an
acceptance checklist. It's written so an engineer or an agent can stand this up
and verify it end to end without asking anyone.

## Performance

| | |
|---|---|
| Cost | **$4–6/month** (1 vCPU / 1 GB VPS) |
| Per player, per 90-second run | ~4 HTTP requests |
| Per multiplayer room | ~30 small messages/second, relayed not simulated |
| Storage | ~100 B per score row; one ghost per game per day |
| Idle memory | ~40 MB (unit caps at 256 MB) |

Every request is a sub-millisecond indexed SQLite read or write in WAL mode.
The one exception is the all-time board, which aggregates across days; it has
its own index and a 60-second memo cache, because this engine is synchronous
and a slow query there would stall the event loop for every other request.
A single box handles hundreds of requests per second and thousands of
concurrent sockets. It's single-node by design — the game id is the natural
shard key if it ever outgrows one machine.

## Security

Clients are untrusted. Every scoring write is either HMAC-signed over a
canonical string containing a fresh timestamp, or vouched for by a trusted
proxy. Run tokens are single-use, wall-clock-checked, and bound to the
leaderboard day they were minted for. WebSocket access requires a single-use
ticket that expires in 60 seconds. The server never executes or simulates game
code — multiplayer state blobs are opaque and relayed, never interpreted.

The code has been through four adversarial review passes; the most recent was
a 48-agent audit that produced 39 candidate findings, of which 26 survived
independent refutation and were fixed. Those included a remote out-of-memory
condition in the WebSocket ping path, a client-side score-loss bug, and a
restore procedure that would have corrupted the database. Every fix is pinned
by a regression test.

See **[SECURITY.md](SECURITY.md)** for the threat model, the honestly
documented limits, and how to report a vulnerability privately.

## Integration

**Direct mode** works today for any game that can make network requests: the
client holds a server-issued keypair and signs its own writes.

**Proxy mode** is for platforms that sandbox their games. The platform's server
calls the same endpoints with a shared key and asserts the player's identity in
headers, so no client ever holds a secret and player IPs never reach the game
backend. [INTEGRATION.md](INTEGRATION.md) covers that design in full, including
what a platform-side bridge looks like for sandboxed games.

## Project layout

```
server.js          HTTP API — identity, seeds, events, runs, boards, ghosts, admin
mp.js              WebSocket relay + room manager (RFC 6455, hand-written)
client-sdk.js      Browser SDK — resolves-or-null, never throws
demo.html          Interactive console with a scripted rival bot
test.js            67-assertion end-to-end suite (HTTP + live 2-socket race)
deploy/            Ubuntu provisioner, systemd unit, Caddyfile, backup + restore
AGENT_HANDOFF.md   Deploy and integration runbook
INTEGRATION.md     Platform integration design
SECURITY.md        Threat model and disclosure policy
```

## Contributing

Issues and pull requests are welcome. CI runs the full suite on every push and
pull request and asserts the exact expected assertion count, so a truncated or
crashed run can't pass as green.

## License

[GPL-3.0](LICENSE).

<div align="center">
<sub>Built for <a href="https://tiptapgames.com">TipTap</a>-class arcade games — useful to any browser game that wants an online side.</sub>
</div>
