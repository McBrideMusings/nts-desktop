# Seed the show index from the sitemap, not `/api/v2/shows`

Date: 2026-08-15

## Context

`/api/v2/shows` clamps `limit` to 12 and rejects any `offset` above 1000 with
HTTP 422 — at most 1012 of the 1834 shows.

## Decision

`/api/v2/shows` is not used for seeding the index. `ShowIndex` seeds from
`sitemap.xml.gz` → `sitemap{1,2}.xml.gz` instead, which has no ceiling and is
three requests.

## Consequences

The sitemap is regenerated about daily, so the current day's shows are
missing from it; `/api/v2/collections/recently-added` (newest broadcast
first, with `audio_sources`) covers the tail and is polled alongside it.
