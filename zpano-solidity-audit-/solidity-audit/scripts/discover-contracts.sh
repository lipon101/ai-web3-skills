#!/usr/bin/env bash

set -euo pipefail

roots=("$@")
if [ ${#roots[@]} -eq 0 ]; then
  roots=(".")
fi

find_args=()
for root in "${roots[@]}"; do
  if [ -d "$root" ]; then
    find_args+=("$root")
  elif [ -f "$root" ]; then
    case "$root" in
      *.sol) printf '%s\n' "$root" ;;
    esac
  fi
done

if [ ${#find_args[@]} -eq 0 ]; then
  exit 0
fi

find "${find_args[@]}" \
  \( -path '*/lib/*' -o -path '*/test/*' -o -path '*/tests/*' -o -path '*/mocks/*' -o -path '*/interfaces/*' -o -path '*/script/*' -o -path '*/broadcast/*' \) -prune -o \
  -type f -name '*.sol' \
  ! -name '*.t.sol' \
  ! -name '*Test*.sol' \
  ! -name '*Mock*.sol' \
  -print | sort -u
