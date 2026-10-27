# Validation of the security foundation

Local checks on October 27, 2026:

- 42 backend tests passed with Google's Firestore emulator, including concurrent
  requests through independent clients sharing one budget, outage rejection,
  disabled-policy rejection, daily/monthly caps, token buckets, malformed model
  output, unreadable labels, provider failure sanitization, and the real SDK
  exercised through a mocked HTTP transport.
- Six Flutter tests passed, including failure/unverified-result widget checks
  and the history rule that only completed analyses can be saved or displayed.
- Flutter's release web build completed. The image package emits WebAssembly
  compatibility notices; the standard JavaScript web target builds successfully.
- Flutter analysis reported no errors. Existing deprecation/style notices and
  unused-code warnings remain in the imported v10 application.
- The locked Python runtime dependency set passed pip-audit with no known
  vulnerabilities after patching Flask and Pillow. This is a point-in-time scan.
- Git diff whitespace checks passed; the new source tree was checked for embedded
  provider keys. None were found. No source `.env` or local credential file was
  imported. The earlier public upstream history was not rewritten.

The GitHub workflow additionally tests Python 3.11 and the non-root Docker image.
Local backend tests used an isolated Python 3.13 environment because the Mac's
system Python installation was damaged. No local Docker executable was present.
CI results must be checked on the final pushed commit. GitHub workflow access was
authorized through the browser before enabling these checks.

No production deployment, live paid AI request, signed native app build, key
rotation, Firestore provisioning, or Secret Manager migration was performed by
these local checks. Those are explicit rollout/acceptance steps, not implied by
unit tests or successful health responses. Photos and prompts used in tests are
synthetic; no user image was sent to the provider.
