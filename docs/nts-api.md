# NTS API limits worth knowing before extending the catalog

Moved verbatim from CLAUDE.md on 15 Aug 2026 — issue #42. This is a move, not an audit.

- `/api/v2/radio/schedule/{1,2}` is the programme grid: fourteen days per
  channel, ~16 slots a day, each with `start_timestamp`, `end_timestamp` and a
  `links[rel=details]` href naming the show and episode. Every slot carries a
  show alias; about 30% of them (the furthest-out ones) have no episode alias
  yet. No genres, location or artwork — every slot that wants those fetches
  `/api/v2/shows/<show>/episodes/<episode>` for itself: the rail for the
  programme on air, and each schedule row as it scrolls into view
  (`SlotArtLoader.request`, which falls back to `/api/v2/shows/<show>` for a
  slot with no episode alias). What comes back is folded into `ShowIndex`, so
  the alias carries artwork everywhere else it appears and on the next launch.
- `/api/v2/live` is **not used, deliberately** — see
  `adr/0001-schedule-grid-not-live-endpoint.md`. The grid above is the
  only record of what is on; anything that needs artwork or genres for the
  current slot fetches the episode by the aliases the grid supplies.
- `"embeds": {"tracklist": []}` — a bare array where the populated case is an
  object — is how an episode with no identified tracks is serialised, and that
  is every episode still on air. Decoding it strictly fails the whole episode
  request, so `ShowJSON.Embeds` reads the tracklist leniently.
- `/api/v2/search` answers 200 with an empty `results` array — even called
  exactly as nts.live calls it (`?q=…&types[]=show`) with browser headers, and
  even for terms in its own `metadata.popular_terms`. Search is local; there is
  no server search to fall back to. `/api/v2/search/episodes?q=…` (and
  `?query=…`) is worse than absent: it answers 200 and silently ignores `q`,
  returning all ~87,683 episodes (`metadata.resultset.count`) regardless of the
  term. `/api/v2/search/shows` is a bare 400.
- `/api/v2/shows` is not used to seed the index — see
  `adr/0002-show-index-from-sitemap.md`.
- `/api/v2/shows/<alias>` is the only source of a show's real name, location
  and host blurb (`description`, already plain text — `description_html` is
  the same content with the wrapping tag still on). One response is ~36.9KB
  (it embeds recent episodes; nothing trims it), so backfilling all ~1,834
  shows is ~68MB — done once per machine (`ShowDetailBackfill`, keyed off
  `ShowRef.detailed`), never on a recurring cadence.
- `sitemap.xml.gz` → `sitemap{1,2}.xml.gz` is the complete public index and the
  source `ShowIndex` builds from: 1834 show aliases and 89,260 episode URLs in
  ~1.9MB gzipped, three requests, and `robots.txt` is `Allow: /`. Served with
  `Content-Encoding: gzip`, so URLSession decompresses them and the parser only
  sees XML. Regenerated about daily, so the current day's shows are missing from
  it; `/api/v2/collections/recently-added` (newest broadcast first, with
  `audio_sources`) covers the tail and is polled alongside it. Every `<lastmod>`
  inside is just the generation stamp — only the file's own `Last-Modified`/
  `ETag` mean anything.
- There is no favourites REST endpoint — `/api/v2/users/me`, `/api/v2/favourites`
  and `/api/v2/users/me/favourites` return the site's HTML shell, not JSON.
  Favourites live in two top-level Firestore collections: `favourites` holds
  `{show_alias, episode_alias, device_id, created_at, session}` — follows are the
  rows with an empty `episode_alias`, saved episodes the rest — and `user_devices`
  (doc id = installation id) holds `{device_id, firebase_user_uid, …}`.
  **`device_id` is a misnomer**: nts.live fills it with
  `getUserUid() || getInstallationId() || gaClientId`, so while signed in it is
  the Firebase uid, which is why favourites follow you across browsers. The
  installation id only carries stars made before signing in, and `user_devices`
  is how those are found later. Read `device_id IN [uid] + registered
  installation ids`; write `device_id = uid`. `NTSFavourites` does this over Firestore's REST API
  with the Firebase ID token; the gRPC client in `NTSFirestore` is Listen-only.
  **No `orderBy` in those queries** — filtering one field and ordering by
  another needs a composite index that does not exist in NTS's project, and
  asking answers `FAILED_PRECONDITION: The query requires an index`.
- **Supporters entitlement is a third top-level Firestore collection,
  `subscriptions`** — not a token claim and not a REST field. Query it filtered
  on `subscriber_email`; each doc carries `status` and `end_time`. Entitled =
  any doc with `status` in `{active, trialing, on-hold}`, or a cancelled doc
  still inside its `end_time` grace period. Read off nts.live's own bundle
  (`onSubscriptionsChange` / `isSubscriptionActive` / `canSeePremiumFeature`).
  The Firebase ID token carries **no** tier claim — its only custom claim is
  `host`, which marks radio presenters. Untested: whether the security rules
  let a bare client read that collection. Trace: `../tmp/claude/issue-20-tier-signal.md`.
- Episode audio is a SoundCloud/Mixcloud page URL in `audio_sources`, which
  AVPlayer cannot open. `/api/v2/resolve-stream?url=<encoded>` returns
  `{"hls": "…m3u8?Policy=…&Signature=…"}` — signed and expiring, so resolve per
  play. It answers 401 without `Authorization: Basic <token>`, where the token is
  the `"NTS_API_TOKEN":"…"` constant in the HTML of every nts.live page. The app
  scrapes it at first play (`NTSAPI.siteToken`) rather than compiling it in, and
  re-reads it once on a 401.
- Explore is `/api/v2/search/episodes` with repeatable `genres[]` and `moods[]`,
  plus `intensity=<lo>-<hi>` (their 0–10 slider ×10) and `genre_count=<n>`.
  nts.live's "Focused" toggle is that `genre_count`; "Music Only" is just
  `moods[]=no-talkin`. 10 moods, 20 primary genres, 438 subgenres. None of it
  needs a user account.
- Every endpoint above is served `cache-control: max-age=900` with an ETag.
- **There is no audio to meter.** See `adr/0004-no-audio-metering.md`.
