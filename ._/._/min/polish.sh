#!/bin/bash

# Polish.sh - Polish JavaScript file

# ============================================
# SAVE CALLER'S DIRECTORY AND RESOLVE JS FILE
# ============================================
CALLER_DIR="$(pwd)"

# Check for --log flag
FORCE_LOG_MODE="false"
if [ $# -gt 0 ] && [ "$1" = "--log" ]; then
    FORCE_LOG_MODE="true"
    shift
fi

# Process JS file argument
JS_FILE=""
if [ $# -gt 0 ]; then
    if [[ "$1" = /* ]]; then
        JS_FILE="$1"
    else
        JS_FILE="$CALLER_DIR/$1"
    fi
    shift
fi

# Validate
if [ -z "$JS_FILE" ] || [ ! -f "$JS_FILE" ]; then
    echo -e "\033[0;31mError: No valid JS file provided\033[0m" >&2
    echo -e "\033[1;33mUsage: bash polish.sh [--log] <path/to/file.js>\033[0m"
    exit 1
fi

# ============================================
# GET SCRIPT'S OWN DIRECTORY
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# POLISH FLOW - Execute scripts directly
# ============================================

if [ "$FORCE_LOG_MODE" = "true" ]; then
    bash "$SCRIPT_DIR/polish/functions.sh" "$JS_FILE"
    bash "$SCRIPT_DIR/polish/const.sh" "$JS_FILE"
    bash "$SCRIPT_DIR/polish/let.sh" "$JS_FILE"
else
    bash "$SCRIPT_DIR/polish/functions.sh" "$JS_FILE" >/dev/null 2>&1
    bash "$SCRIPT_DIR/polish/const.sh" "$JS_FILE" >/dev/null 2>&1
    bash "$SCRIPT_DIR/polish/let.sh" "$JS_FILE" >/dev/null 2>&1
fi

exit $?