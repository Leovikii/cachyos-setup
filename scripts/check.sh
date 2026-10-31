#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
for script in setup.sh lib/*.sh modules/*.sh assets/steam/* scripts/*.sh; do bash -n "$script"; done
sh -n assets/steam/environment.sh
sh -n assets/steam/steam-managed
if command -v shellcheck >/dev/null; then
    shellcheck --severity=error setup.sh lib/*.sh modules/*.sh scripts/*.sh
    shellcheck --severity=error --shell=sh assets/steam/*
fi
python3 -B -m unittest discover -s tests -v
