# Recording Slots

Put phone screen recordings here when you want the Remotion promo to use real product footage.

Recommended clips:

- `phone-chat-generate.mp4` — chat prompt, trace progress, generated artifact card.
- `phone-github-pages.mp4` — publish GitHub Pages and show the success card.
- `phone-repo-hub.mp4` — Repo Hub search, Pages badge, Actions/artifact surface.

Then edit `src/recordedClips.ts` and set `enabled: true` for the clips you want to include.

These raw recordings are ignored by git by default because they can be large or contain private tokens. Commit only polished rendered outputs in `docs/assets/`.
