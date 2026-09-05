# aur-scanner single-auth prototype

This directory contains the frozen upstream patch used to validate a single-authentication privileged-install design for `aur-scanner` 2.0.0.

- Upstream repository: `KiefStudioMA/ks-aur-scanner`
- Upstream base commit: `07893f5c1a71252a8c2b584016eb6e24627a249e`
- Frozen patch: `0001-single-auth-privileged-broker.patch`
- Frozen patch blob: `a69740dfb301ceac34932f8d2612c11d880e2f46`

Permanent validation applies the saved patch to the exact upstream base, checks formatting, runs the CLI and full workspace test suites, and runs clippy with warnings denied. A separate Arch Linux integration test builds the patched CLI, runs an AUR installation as a non-root user with normal passworded sudo, verifies the package was installed, and requires exactly one sudo password prompt.

The patch keeps package builds unprivileged. Privileged repo and local-package installation is isolated behind the short-lived broker created before PKGBUILD execution; reusable sudo credentials are not exported into the build environment.
