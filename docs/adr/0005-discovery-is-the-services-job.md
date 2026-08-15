# Discovery is the service's job, not the application's

Date: 2026-08-15

## Context

Decided rather than extracted — settled in an iron-out interview (GitHub
issue 43, recorded in `docs/jobs.md`), not argued inline in code comments.
Cross-reference `docs/jobs.md`'s "Scope boundary" section; the two must not
drift.

## Decision

Discovery is the service's job, not the application's. The app is a vessel:
it exposes what NTS already offers without requiring a browser. Anything
that curates *over* the service is out of scope by construction rather than
by preference. This excludes a recommendation layer or a personal-taste
model, specifically — the app will never rank, filter, or suggest based on
inferred listener taste.

This qualifies as a decision worth recording on all three tests: it is hard
to reverse (a curation layer, once users depend on it, can't be quietly
removed); it is surprising to a reader who sees the Explore tab and concludes
the app already curates; and it is the result of a real alternative that was
available (a taste-model or recommendation feature was a genuine option, not
a strawman).

## Consequences

Explore, the radial dial, the schedule timeline, and local search all serve
the "reach the service" job by exposing NTS's own facets (mood, genre,
schedule) — none of them rank or filter by inferred taste. Any future feature
proposed as "helping the user find something" must be checked against this
boundary before being built.
