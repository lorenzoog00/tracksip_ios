# TrackSip iOS

## Releasing to TestFlight

**Every release to TestFlight bumps the version.** Each `dev` → `main` release PR must raise `MARKETING_VERSION` to a number that was never uploaded, in all 14 entries of `siptrack.xcodeproj/project.pbxproj`. Put the bump in `dev` before you open the release PR.

- A merge to `main` triggers `.github/workflows/testflight.yml`.
- Apple rejects an upload on a version it has already approved or received for review (errors 90062 and 90186). The rejection only comes at the last step, after the whole CI run and the archive.
- CI sets the build number (`CURRENT_PROJECT_VERSION`) to a UTC timestamp, so the marketing version is the only number to bump.
