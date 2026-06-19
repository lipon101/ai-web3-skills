#!/bin/bash
# Wrapper to run Argus inside the pinned Docker environment.
#
# Usage:   scripts/run-in-docker.sh <project-root> [<additional args>]
#
# Mounts <project-root> as /workspace inside the container; Argus operates on it
# as if it were the working directory.

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <project-root> [<args>...]" >&2
  echo "  Example: $0 /path/to/my-rust-protocol" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$1" && pwd)"
shift

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "Error: $PROJECT_ROOT is not a directory" >&2
  exit 1
fi

# Build image if missing
if ! docker image inspect argus:0.1.10 >/dev/null 2>&1; then
  echo "Building argus:0.1.10 image (one-time, ~10 min)..."
  ARGUS_REPO="$(cd "$(dirname "$0")/.." && pwd)"
  docker build -t argus:0.1.10 "$ARGUS_REPO"
fi

# Run with the project mounted; pass additional args to the container shell
docker run -it --rm \
  -v "$PROJECT_ROOT":/workspace \
  -v "$HOME/.cache/argus":/root/.cache/argus \
  argus:0.1.10 "$@"
