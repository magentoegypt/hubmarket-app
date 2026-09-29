# assets/video

## app_intro.mp4 — launch intro (CL042-DEV41)

Plays on **every cold start**, in place of the static launch splash, with Skip
appearing after five seconds. Both are the client's explicit instruction
(CL042-QA01, 2026-09-27) — it originally played once, and that was reversed.
Not on resume: only a cold start rebuilds the splash.

Switchable with `--dart-define=INTRO_VIDEO_ENABLED=false`, which still needs a
build — it is a compile-time flag, not remote config. See
`lib/features/onboarding/presentation/intro_video_screen.dart`.

**This file is a re-encode, not the master.** The supplied master was
2160×3840 (4K) at 26 Mbps — 41.9 MB for 13.5 seconds. Bundled raw it would
have been roughly four times the size of the entire iOS app, and every user
downloads it whether or not they ever see it. It also carried a silent audio
track (−91 dB, digital silence), which was dropped.

Re-encoded with:

```
ffmpeg -i <master>.mp4 -an \
  -vf "scale=1080:1920:flags=lanczos" \
  -c:v libx264 -profile:v high -preset slow -crf 24 \
  -pix_fmt yuv420p -movflags +faststart \
  app_intro.mp4
```

1080×1920 is full resolution on any phone this app targets; 4K is not
distinguishable on a 6" screen and costs ~40× the bytes. Result: **0.99 MB**.

**If you replace this video, re-encode it the same way and keep it around
1 MB.** Dropping a master in here unchanged is the failure mode this note
exists to prevent — nothing in the build will warn you, the app will simply
get tens of megabytes heavier.

Note the two files on the ticket ("for iphone" / "for android") were
byte-identical — the same master uploaded twice, not two per-platform cuts.
One asset serves both platforms.
