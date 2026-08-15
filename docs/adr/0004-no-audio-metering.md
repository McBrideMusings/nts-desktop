# Don't meter audio for the level display

Date: 2026-08-15

## Context

Both the live relay (`stream-relay-geo.ntslive.net/stream{,2}`) and the
mixtape endpoints (`stream-mixtape-geo.ntslive.net/mixtape*`) hand AVPlayer an
asset that reaches `readyToPlay` carrying **zero audio tracks**, so an
`AVMutableAudioMix` has nothing to attach an `MTAudioProcessingTap` to and no
sample ever reaches a callback. Measured, not assumed.

## Decision

There is no audio to meter. The only route that does work is a CoreAudio
process tap over the app's own output (`AudioHardwareCreateProcessTap`, macOS
14.2+, read through a private aggregate device) — that does deliver real
samples, but it is audio capture and therefore a permission prompt, which is
not worth paying for a decoration.

## Consequences

`LevelLamps` in `NowPlayingBar.swift` invents its levels on purpose and is
honest only about *when* it moves, not how much.
