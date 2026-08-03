# Security policy

## Reporting a vulnerability

Please report privately — **do not open a public issue** for a security bug.

Use GitHub's [private vulnerability reporting](https://github.com/PandaCatz/PandaNet/security/advisories/new)
on this repository. That opens a private advisory only the maintainer can see.

Please include the affected file and line, a concrete failure scenario
(inputs and state → wrong outcome), and a proof-of-concept script if you have
one. A runnable repro is worth far more than a description.

Expect an initial response within about a week. This is a reference
implementation maintained by one person, not a funded product — that is the
honest service level.

## Scope

In scope: anything in `server.js`, `mp.js`, `client-sdk.js`, and the `deploy/`
scripts — remote crashes, authentication and authorization bypasses, score
forgery or cross-player writes, cross-game data leaks, resource exhaustion,
and deploy configurations that expose the service.

Out of scope, because they are documented, accepted design limits rather than
defects (see the "Known limits" section of `AGENT_HANDOFF.md`):

- A modified game client lying about its own play. No client-side game can
  prevent this. The mitigation path is server-side re-simulation of flagged
  runs from their stored input logs.
- Single-node operation with one SQLite writer.
- The static `X-Proxy-Key` shared secret. This is explicitly documented as
  pilot-only; step 1 of the production hardening list replaces it with a
  per-request HMAC signature.
- Relay race results being informational rather than authoritative. Ranked
  scoring only ever comes from the signed or proxy-vouched HTTP finish flow.

## Threat model in one paragraph

Clients are untrusted. Every scoring write requires either an HMAC signature
over a canonical string containing a fresh timestamp, or a request from the
platform proxy authenticated with a shared key. Runs require a server-issued
one-time token, are cross-checked against the wall clock, and are bounded by
per-game plausibility caps; implausible runs are stored but flagged off the
leaderboard so a false positive never destroys a legitimate run. WebSocket
access requires a single-use ticket that expires in 60 seconds. The server
never executes or simulates game code — multiplayer state blobs are opaque and
relayed, never interpreted.

## Verifying a change

`node test.js` must print `65 passed, 0 failed`. The suite covers every
rejection path, not just happy paths, including malformed WebSocket frames,
ping floods, prototype-pollution message types, expired run tokens, and
tampered signatures. CI runs it on every push and pull request.

## Audit history

This code has been through four adversarial review passes. The fourth was a
48-agent workflow that produced 39 candidate findings, of which 26 survived
independent refutation. Fixes from that pass include a remote out-of-memory
condition in the WebSocket ping path, a client-side score-loss bug, a
database-corrupting restore procedure, and a run token that could be cashed
after its leaderboard day had closed. Findings and their regression tests are
described in the commit history.
