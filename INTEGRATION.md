# Proposal: an online layer for TipTap Games

**From:** the developer of PandaCat (`cmscicmh707ddpb3ihbjp18kc`)
**What this is:** a design + working, tested reference implementation for giving
every game on TipTap online features — global boards, daily ghosts, live
events, and realtime multiplayer races — without weakening the platform's
sandbox in any way.

## The one-sentence version

Keep games exactly as locked-down as they are today (no fetch, no sockets, no
storage — validator unchanged); let the **platform** mediate a small, capped
online API the same way it already mediates `submitScore`, and every game on
the service can have leaderboards-plus: ghosts, events, and live races.

## Why bother

TipTap games are islands. The only shared state a game can touch is its score
column and the daily seed. That caps what the service's games can be:

- **Daily ghost racing** — replay yesterday's/today's best run as a live
  translucent rival. Deterministic games (fixed-step sims with seeded content)
  can do this with a few KB of input log. It makes a daily board *visible*
  instead of a number — the single cheapest retention feature in arcade games.
- **Live events** — "double coins this weekend" pushed server-side, no
  re-upload, no moderation round-trip.
- **Realtime races** — 2–4 players, same seed, synchronized start, live rival
  positions, 90 seconds. Async-first games become social.
- **Cross-device identity for game state** beyond the 8 KB saveState, if a
  game wants it.

None of this is possible today, and none of it needs games to touch the
network themselves.

## The design principle: the sandbox stays

Games keep zero network APIs. The validator keeps rejecting `fetch`, XHR, and
WebSocket. Instead, the platform shell — which already injects `window.TipTap`
— exposes a mediated bridge:

```
game (sandboxed iframe)          platform                    game's backend
  TipTap.net.request(path, ---> shell posts to ---------->  HTTPS endpoint
      payload <= 8 KB)           platform proxy               registered in
  TipTap.net.socket()   <--->   platform WS relay  <--->     Creator Studio
```

The platform proxy attaches what it already knows and the backend could never
verify on its own:

- `X-Player-Id` — stable pseudonymous id (per player, or per player+game)
- `X-Player-Name` — display name
- `X-Proxy-Key` — per-game shared secret proving the request came from TipTap

And the platform enforces what it cares about:

- payload caps (e.g. 8 KB up / 64 KB down), N requests/min/player
- one registered backend origin per game — no arbitrary exfiltration targets
- player IPs never reach third-party backends (privacy win over any
  game-does-its-own-networking model)
- full visibility and an instant per-game kill switch
- opt-in per game; games without a registered backend behave exactly as today

This is the same shape Discord uses for Activities and Roblox uses for Open
Cloud: sandboxed client, platform-vouched identity, developer backend.

## What already exists (attached)

A complete reference backend — `server/` — built to run the **whole service**,
not one game:

| | |
|---|---|
| Multi-tenant | every table and endpoint is keyed by `game`; per-game tuning (score caps, run-duration bounds) via an admin endpoint |
| Platform-proxy mode | the exact header contract above, working today (`PROXY_KEY`); direct mode with client-side HMAC identities also included for standalone use |
| Boards | daily + all-time, top-50 + around-me, one write per player/day/game |
| Ghosts | day-best input log per game, gzipped, ≤ 64 KB, served to everyone |
| Events | date-ranged JSON per game, served with the daily seed |
| Realtime multiplayer | WebSocket relay: quickmatch + private room codes, synchronized countdown starts, live opaque state fan-out (≤ 512 B, ~10–15 Hz), race results, rematch, disconnect handling |
| Anti-cheat | server-issued one-time run tokens, wall-clock cross-checks, per-game plausibility caps; implausible runs stored but flagged off-board |
| Footprint | zero dependencies (Node 22 built-ins only), SQLite/WAL, ~1,070 lines total; deploys on a $5 VPS in ~10 minutes with automatic TLS, hardened systemd, firewall, nightly backups |
| Verification | 65-assertion end-to-end suite covering every guard and a full two-socket live race |

Capacity honesty: a scoring player generates ~4 HTTP requests per 90-second
run; a race relays ~30 tiny messages/second per room. One 1 vCPU box handles
hundreds of HTTP requests/second and thousands of concurrent sockets — the
early-volume needs of the whole service, not just one game. The design is
single-node; if the service outgrows it, the `game` key is the natural shard
axis.

## Anti-cheat, honestly

With platform-vouched identity, impersonation and score-for-someone-else are
gone. What remains is the client itself lying (modified game, slowed clock).
Mitigations shipped: one-time run tokens, wall-clock-vs-claimed-duration
checks, per-game plausibility ceilings — failures are stored but flagged off
the boards, so a false positive never destroys a legitimate run and flags can
be reviewed. The endgame for deterministic games is server-side
re-simulation of flagged runs from their input logs — the same logs that power
ghosts prove the runs are replayable. That's a roadmap item, not in v1.

## Rollout sketch

1. **Pilot (no platform work):** one game runs against the backend directly in
   a dev build to validate the feature set and tune caps. PandaCat volunteers.
2. **Bridge MVP:** shell implements `TipTap.net.request` (HTTP only) behind a
   per-game flag + Creator Studio fields for backend URL and shared secret.
   Ghosts, boards, events light up.
3. **Realtime:** shell adds the WS relay bridge (`TipTap.net.socket`). Races
   light up.
4. **Optional:** TipTap hosts this reference server itself as a shared
   service, so small developers get boards/ghosts/events/races with zero ops.
   It was built multi-tenant precisely so this is a deploy, not a rewrite.

Hardening notes for production (documented in the handoff): replace the static
proxy header with a per-request HMAC signature + timestamp, put the relay
behind the platform's edge, and rate-limit per player at the proxy.

## The ask

- Feedback on the SDK surface (`TipTap.net.request` / `TipTap.net.socket`).
- A pilot flag for one game to run Phase 1.
- If useful: this implementation, docs, deploy scripts, and test suite are
  yours to take — `AGENT_HANDOFF.md` in the same folder is written so an
  integration agent can stand it up and verify it end-to-end without help.
