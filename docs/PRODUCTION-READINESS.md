# Production cleanup status

Changes prepared on `codex/production-readiness` from `a1bf092`.

## Completed in code

- Removed unused test report generators, debug Pro overrides, tracked brainstorm
  output, duplicate privacy manifest, and the StoreKit catalog's bundle membership.
- Production access uses verified, unexpired StoreKit products; cached profile
  flags no longer grant Pro. Restore failures are visible.
- AI requests use authenticated, App Check protected callable functions, Apple
  purchase verification, server-owned quotas, transactional claims, bounded
  retries, and durable failure records.
- Account deletion uses recursive server cleanup, recent authentication, distinct
  cancellation handling, Apple authorization revocation, and a deletion marker
  that blocks late report writes.
- All ad formats wait for consent. Profile exposes required ad privacy choices.
- AI sharing requires explicit opt-in in Profile. Prompts no longer invent
  drink-specific clearance claims or forbid reducing alcohol. Driving estimates
  no longer promise a safe driving time.
- Privacy declarations use Apple's valid health identifier and include purchase,
  account, crash, and country data. Runtime dependency audit reports zero findings.
- TestFlight upload depends on the same revision's backend and iOS CI checks.

## Verification

Local checks: backend lint, Node policy tests, Firestore emulator integration
tests, production source checks, and production dependency audit.
The emulator covers owner isolation, forged reports/Pro/quotas, duplicate requests,
bounded retry, deletion during generation, recent authentication, and purchase
ownership. A baseline run against the old rules proves the new security checks
reject the previously allowed writes.

macOS build/test results will be recorded after CI completes.
Signed archive validation, screenshots, real-device flows, and live services are
not verified from this Windows workspace.

## Handoff

[Release steps](RELEASE.md) contains the required App Attest, Apple IAP key,
Firebase deployment, and App Store upload steps. No production service changes or
App Store upload were performed. The user will handle distribution.

The backend is part of this change: **an app-only upload is not sufficient**.
Deploy both functions and rules, remove the three retired triggers, configure the
new secrets/parameters, and validate the archive before distributing the app.

