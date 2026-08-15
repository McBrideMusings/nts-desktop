# Use the schedule grid, not `/api/v2/live`, as the record of what is on

Date: 2026-08-15

## Context

`/api/v2/live` returns `now` plus `next` … `next17` per channel with `details`
embedded for the first two. But it is served `cache-control: max-age=900`, so
for up to fifteen minutes after every changeover it hands back the programme
that just finished. Writing that over the grid is what made the rail show the
previous hour's show.

## Decision

`/api/v2/live` is **not used, deliberately**. `/api/v2/radio/schedule/{1,2}` —
the programme grid, fourteen days per channel, ~16 slots a day — is the only
record of what is on; anything that needs artwork or genres for the current
slot fetches the episode by the aliases the grid supplies
(`/api/v2/shows/<show>/episodes/<episode>`, or `/api/v2/shows/<show>` when a
slot has no episode alias yet).

## Consequences

Every consumer of "what's on now" reads the grid, not the live endpoint, even
though the grid alone carries no genres, location, or artwork — each such
lookup costs a per-show/episode fetch (`AppModel.loadSlotDetail`), folded into
`ShowIndex` so it's cached on subsequent reads and across launches.
