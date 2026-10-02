# Co-star Web — Design

**Date:** 2026-10-02
**Status:** Approved (design phase)

## Summary

Pick a movie or a TV episode. See which of its cast have worked together on
*other* things, drawn as a D3 force graph. Add more titles to see how they
connect to the same people.

## Core idea: look up people, not titles

Ignore TV shows' own cast lists. A 400-episode series has thousands of guest
stars; fetching them is the expensive, unbounded part. Instead:

1. The **pool** is the cast of the starting title (one movie or one episode:
   roughly 30–150 people, so no top-N cap is needed).
2. For each person in the pool, fetch their credits once
   (`/person/{id}/combined_credits`; cached 30 days).
3. A title is **shared** when two or more pool members have it in their credits.

Cost is *N person lookups*, independent of how long any series is. Verified
against TMDb: every TV credit carries `episode_count`, so a link can say
"80 episodes together", not just "both appeared".

## Adding titles

Two kinds of add, labelled clearly in the UI:

| Add | Effect | Cost |
|---|---|---|
| **Whole series (lens)** | Highlights which pool members have ever been on it. Does not add anyone to the pool. | free, credits already fetched |
| **Movie or specific episode (pool expander)** | Its cast joins the pool. | one lookup per new person |

Phase 1 ships the starting title plus series lenses. Pool expansion is phase 2.

## Graph model

- **Shared titles are hubs; people are nodes.** Person-to-person edges explode
  (100 people on one show is about 5,000 edges); one hub with 100 spokes does not.
- Hub size = number of pool members in the title. Spoke width = that person's
  `episode_count` (TV) or 1 (film).
- Only titles shared by **two or more** pool members are drawn, ranked by member
  count, with a slider for how many hubs to show.
- **People with no shared title are hidden** by default (most background cast),
  with a toggle to show them.
- Exclude the starting title itself.
- Click a hub: list its members and their characters. Click a person: highlight
  their hubs.

## Credit filters

Shared with the Six Degrees game so the logic lives in one place
(`CreditFilter`):

- **Self credits** (character matches `Self`, `Himself`, `Herself`, archive
  footage): **on by default.** Talk and award shows otherwise become the biggest
  hub for every cast. Real example: one actor's TV list included *Hot Ones* and
  *LIVE with Kelly and Mark*, both credited as "Self".
- No voice acting: character contains `(voice)`, or genre is Animation. A
  heuristic; it will miss a few.
- No Marvel: production company or the MCU keyword. Needs a per-title lookup,
  cached.
- Optional: movies only, year range.

## Components

- `CostarWeb` service: pool + credits -> `{ people, hubs, links }` JSON.
- `CreditFilter`: pure rule logic, no I/O.
- `CostarsController` + a JSON endpoint; reuses the `/cast` pickers.
- Stimulus controller rendering the force layout with D3 (importmap pin).
- Reuses `TmdbClient#people_details`-style concurrency for `person_credits`.

## Limits

- TMDb person credits are show-level: we can say two people were *both* on a
  series and how many episodes each had, **not** that they shared an episode.
- A series lens only finds people already in the pool.
- Credits are as complete as TMDb is; background roles are thin.

## Testing

- `CostarWeb` with stubbed credits: shared-title detection, single-member titles
  dropped, starting title excluded, episode-count weighting, lens membership.
- `CreditFilter` unit specs for each rule and its false positives.
- Request spec for the JSON endpoint; a smoke test that the page mounts.

## Out of scope (v1)

- Same-episode detection.
- Crew (directors, writers): cast only.
- Saving or sharing a web.
