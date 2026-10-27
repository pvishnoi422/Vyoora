# Source consolidation

The maintained branch lives in the writable fork `pvishnoi422/Vyoora`.
`origin` points there; `upstream` points to `vyooramedia/Vyoora`.

The original `main` history is retained. Commit `c5f4041` first records the
nonignored working source from `/Users/pvishnoi/vyoora`, including previously
uncommitted changes and the earlier cleanup. No `.env`, virtual environment,
ZIP archive, image upload, or generated build cache was imported.

The application layer (`lib/`, `assets/`, pubspec) and v10 backend were selected
from `/Users/pvishnoi/Desktop/vyoora_test`. That copy has onboarding, history,
profile, local storage, and the redesigned interface, but lacks a complete Android
project. Complete Android, iOS, desktop, and web scaffolding came from the Git
checkout. Camera/photo usage text and Android Internet access were added.

Unused EasyOCR dependencies and legacy backend launchers were removed from the
maintained tree. Their earlier versions remain in Git history. Distinct `.bak`
files and v10 ZIP variants remain in the original snapshot locations; they were
not treated as authoritative code or silently deleted.

The original local folders and remaining ZIPs were not modified by this
consolidation. Future work should use this maintained checkout and branch.
Production previously reported v10. A version label alone does not establish
its exact source commit. Future deployments must use the Git commit as an image
tag and pin the resulting digest, with traffic moves recorded separately.

Old saved scans lacking the completion contract remain on-device but are omitted
from verified history. They must be analyzed again; they are never retroactively
marked successful. The history screen explains this rule.
