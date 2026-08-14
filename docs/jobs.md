# Jobs

Elicited 14 Aug 2026 in an iron-out interview, following a product-improve
survey that found the user-needs and product-strategy layers unstarted and
named them the bottleneck. Recorded verbatim from GitHub issue 43. This
document records the register; it does not decide it.

## Two users

- **Listener** — the author primarily; someone who installed from the
  Homebrew tap secondarily. The second user's needs can justify work; they do
  not outrank the first's.
- **Maintainer** — the author, changing the thing.

## Root job — Listener

> When I am settling into a long stretch at the desk, I want radio playing
> continuously without it becoming a thing I have to manage, so my attention
> stays on the work.

## Scope boundary

Discovery is the service's job, not the application's. The app is a vessel:
it exposes what NTS already offers without requiring a browser. Anything that
curates *over* the service is out of scope by construction rather than by
preference.

## Secondary jobs — Listener

- **Capture** — when something good is playing, keep hold of it before it is
  gone.
- **Status at a glance** — know whether it is actually playing without
  looking at the window.
- **Reach the service** — get to what NTS already offers without opening a
  browser.

## Job — Maintainer

> When I am changing something I cannot see from the code alone, I want to
> drive the running app and read its state back, so I can tell whether the
> change actually worked.

## Shipped clusters, mapped

| Cluster | Serves |
|---|---|
| Volume and mute persistence, drag debounce | root |
| Menu-bar bars tracking playback status | status at a glance |
| Media keys, Control Centre tile | root |
| Auto-update | root |
| Star and follow from the card, account sync, saved list | capture |
| Tracklists, live and episode | capture |
| Source links out to nts.live, genre chips | reach the service |
| Radial dial, Explore, schedule timeline, local search | reach the service |
| The scripting dictionary and every state field | maintainer |

## Release bar

- **0.1.0** is gated on the repository going public — mechanical, the update
  feed cannot resolve otherwise — plus a stranger being able to install, sign
  in or understand why they cannot, and hear audio.
- **Every release after that** is gated on the root job alone: nothing
  known-broken in the unattended path.

## Cautions

- The status job's surface is partly decorative. The level lamps invent their
  levels — there is no audio to meter — so they are honest about *when* they
  move, not how much. A future feature justified by "status" should be
  checked against that.
- The maintainer job can justify anything if left unguarded. The guard: a
  maintainer feature earns its place when it makes something checkable that
  was not checkable before.
