#!/usr/bin/env bash
# VeerSkills CLI wrapper

MODE="standard"
ARGS=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        quick|standard|deep|beast) MODE="$1"; shift ;;
        --continue) ARGS="--continue"; shift ;;
        *) ARGS="$ARGS $1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

echo "Launching VeerSkills ($MODE mode)..."
claude -p "$SCRIPT_DIR/SKILL.md" "Follow the VeerSkills pipeline perfectly. Run a $MODE audit on: $ARGS"
