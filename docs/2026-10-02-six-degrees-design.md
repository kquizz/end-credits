# Six Degrees — Design

**Date:** 2026-10-02
**Status:** Approved (design phase)

## Summary

A guessing game, not a solver. You get a **start** and a **target** actor. Type a
name; if that person shares a credit with the current end of your chain (under the
active rules), they join the chain. Reach the target in as few hops as you can.

## Why it's cheap

TMDb has no path-between-people endpoint, and a crawling solver would make
thousands of calls. A guess is just two cached credit lookups and an intersection:

1. Autocomplete the name (`/search/person`, popularity-ranked).
2. Fetch credits for the chain's last person and the guess
   (`/person/{id}/combined_credits`).
3. Apply the rule filters, intersect by title id. Any survivor = yes.

The matching title is shown ("both in *Heat*") and drawn on the chain.

## Targets

A curated list of about 40 famous people in a YAML file (names resolved to TMDb
person IDs at seed time), in three difficulty tiers. The seed check drops anyone
with fewer than ~30 credits that survive the default rules, so a target can't be
unreachable. Start and target both come from the list: random play now, a seeded
daily pair later.

## Rules (toggles)

Same `CreditFilter` as the Co-star Web:

- No "Self" credits: **on by default** (talk and award shows connect everyone).
- No voice acting.
- No Marvel.
- Optional: movies only, year range.

## Gameplay details

- A wrong guess shakes the input; no penalty in v1.
- No repeating people already in the chain.
- Win when the target joins the chain; score = hops.
- The finished chain is drawn with D3 (people as nodes, shared titles on the links).

## Components

- `GameController` (new, guess, reveal) + Turbo Frames for the chain.
- `ConnectionCheck`: two people + rules -> shared titles or nothing.
- `TargetList` loading `config/degrees_targets.yml`.
- Reuses `TmdbClient#search_person` and `#person_credits`, and `CreditFilter`.

## Out of scope (v1)

- A shortest-path solver or hint beyond one hop.
- Accounts, leaderboards, streaks.
- A daily puzzle (phase 2).

## Play with a friend (live rooms)

`POST /degrees/rooms` makes a room (6-char code) and a shareable `/degrees/rooms/:code`. Two players,
no accounts: each gets a seat token in a signed cookie (`degrees_seats`, a `{code => token}` hash).
Anyone else watches read-only.

- **Rules of play.** A server-drawn pair; players alternate bids ("I can do it in N hops", N 1..6,
  each strictly lower). The other player bids lower or says "Go for it"; the lowest bidder then builds
  the chain within their bid while the other watches live. Success wins the round; running out of hops
  or giving up loses it. Wrong guesses cost nothing. Round 1 opens with the creator, then it alternates.
- **State machine.** `RoomGame` is pure (no I/O): every move returns a new state or raises
  `IllegalMove`. `Room#transition!` applies it under `with_lock` and then broadcasts, so simultaneous
  clicks can't corrupt state; "Next round" is idempotent (the client names the round it saw).
- **Transport.** Moves are HTTP POSTs that return the new state; `RoomChannel` broadcasts the same
  sanitized state (no tokens) to everyone, and sends it on every (re)subscribe. State has a `version`
  so clients drop stale pushes. On reconnect the client also refetches `GET /degrees/rooms/:code.json`.
- **Pairs.** `PairGenerator` walks 3-5 hops from a popular actor through well-known titles (>= 1000
  TMDb votes), re-verifying each hop with `ConnectionCheck` under the room's rules, so the pair is
  reachable in at most k hops. A direct shared credit or an obscure target is rejected; if retries run
  out it falls back to a curated `TargetList` pair (not guaranteed reachable under unusual rules).
- **Cleanup.** `Room.purge_idle!` (rooms untouched for 24h), run daily by `config/recurring.yml`.
