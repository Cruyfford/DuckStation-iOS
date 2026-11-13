# Upstream

Based on DuckStation by Connor McLaughlin (stenzek), commit `aa955b8a`,
the last revision distributed under GPL-3.0. This fork is used under GPL-3.0.
Modifications: iOS port (see `src/duckstation-ios/` and `.github/workflows/`).

## iOS user interface

The SwiftUI interface in `src/duckstation-ios/ui/` (Swift sources, `ARMSX2Bridge.h`, assets) comes from
ARMSX2 (https://github.com/ARMSX2/ARMSX2, commit in `ui/ARMSX2_COMMIT`), licensed GPL-3.0
(`ui/COPYING.GPLv3`). It is connected to DuckStation through `ui/Bridge/DSBridge.mm`.


## App name

The iOS app is shown to users as **Psxp**. It is a build of the GPL-3.0 DuckStation code base listed above
(plus the ARMSX2 SwiftUI frontend); the rename changes branding only, not authorship or licensing.
