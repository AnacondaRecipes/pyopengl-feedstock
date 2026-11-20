#!/usr/bin/env bash
set -euo pipefail

export PIP_NO_CACHE_DIR=1

${PYTHON} -m pip install . -vv --no-deps --no-build-isolation
