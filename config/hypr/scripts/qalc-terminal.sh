#!/usr/bin/env bash
# Native Qalc session inside Foot. Keep full terminal scrollback and Qalc history.
set -euo pipefail

exec qalc -s 'autocalc on'
