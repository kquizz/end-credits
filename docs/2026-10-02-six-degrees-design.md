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
