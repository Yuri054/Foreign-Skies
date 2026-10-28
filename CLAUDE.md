# Notes for working on Foreign Skies

- Read VISION.md first: it says what the game is for (a sandbox where your effort compounds, not a history
  simulation). Every rule change serves one of its rules and is judged by a playtest, not only by AI-only runs.

- CHANGELOG.md: every new entry's heading carries the date and time of the release in UTC, as
  `## 0.10.3 (2026-10-27 09:30 UTC)`. Bump the version in `project.godot` with it; a push to main with a new version
  publishes a GitHub release with the Windows build (`.github/workflows/build.yml`).
