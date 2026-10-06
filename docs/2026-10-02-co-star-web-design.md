# Co-star Web — Design

**Date:** 2026-10-02
**Status:** Approved (design phase)

## Summary

There are two flows. The **primary flow** is series overlap: pick two or more
TV series and see everyone who appeared in at least two of them. The
**secondary flow** (below, "Single-episode pool") starts from one movie or
episode and draws a force graph.

## Primary flow: pick 2+ series, show the overlap

1. The user searches TV series and adds two or more as chips.
2. For each series, one call to `/tv/{id}/aggregate_credits`
   (`TmdbClient#tv_aggregate_credits`, cached 30 days). It returns every cast
   member with `total_episode_count` and per-role `episode_count`.
3. `CostarWeb` joins the casts by person id. **No per-person lookups.** Cost is
   one call per series, however long the series run.
4. A person is kept only if they appear in at least 2 selected series
   (`min_series`, default 2). **People who match fewer are dropped entirely.**
5. `total_episodes` is the sum of their episode counts across the series they
   matched in; episodes in unmatched series do not count.
6. `size = sqrt(total_episodes) / sqrt(max total_episodes)`, so the biggest
   match in the current result is 1.0 and a 156-episode lead does not dwarf a
   one-episode cameo. People are sorted by `total_episodes` descending.
7. The page draws circular profile photos (48-180px by `size`), with an
   initials circle when TMDb has no photo. Hover or click shows each series,
   the episode count and the character names.

Real example, verified against TMDb: *The Gilded Age* (81723) with *The Good
Wife* (1435) gives **43 shared people**. Christine Baranski leads (33 + 156
episodes), then Nathan Lane (13 + 15), Audra McDonald (17 + 1) and so on.

Endpoints: `GET /costars` (page), `GET /costars/search.json?q=` (TV title
search for the picker), `GET /costars/overlap.json?ids[]=81723&ids[]=1435`.

**Limit:** this is series-level overlap. It says two shows share a person and
for how many episodes, not that two people shared an episode.

## Secondary flow: single-episode pool

Pick a movie or a TV episode. See which of its cast have worked together on
*other* things, drawn as a D3 force graph. Add more titles to see how they
connect to the same people.

### Core idea: look up people, not titles

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

## Follow-ups shipped

- Shareable links: `/costars?ids[]=81723&ids[]=1435[&view=web][&min=2][&all=1]` preloads the chips
  server-side and runs the overlap on load; the address bar is kept in sync with `history.replaceState`.
- Filters (client-side, no refetch): a minimum-episodes slider (hide a person whose max episodes in any
  single matched show is below N; default 1) and, with 3+ series, "Only people in every selected show".
- Clicking a person opens a detail panel (characters per show, TMDb link); in the web view it also
  highlights that person's links and hubs and dims the rest.
- Picker results are sorted by TMDb popularity, dropping poster-less, barely popular stubs.
- Watch next: a lazy "Watch next" section under the results (`GET /costars/watch_next.json?ids[]=<people>&series[]=<selected>&skip_self=&skip_voice=&skip_marvel=`).
  `WatchNext` fetches each visible person's credits (first 60, cached), applies `CreditFilter`, and lists up to 25 other titles shared
  by 2+ of them, ranked by member count, combined episodes, popularity, recency. The min-episodes slider and all-shows filter decide
  which people are sent. `MarvelTitles` builds the Marvel set from `/discover` (companies 420 and 38679, MCU keyword 180547).
