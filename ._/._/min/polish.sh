#!/bin/bash

# Polish.sh - Polish JavaScript file (console.log, functions, const, let)

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
# POLISH FLOW - Execute scripts as a pipeline
# Order matters: consolelog first, then functions,
# then const, then let (so const transformation
# can process consts created by consolelog)
# ============================================
OUTPUT_FILE="output.js"
TEMP1="${JS_FILE}.tmp1"
TEMP2="${JS_FILE}.tmp2"
TEMP3="${JS_FILE}.tmp3"
TEMP4="${JS_FILE}.tmp4"

if [ "$FORCE_LOG_MODE" = "true" ]; then
    bash "$SCRIPT_DIR/polish/consolelog.sh" "$JS_FILE" "$TEMP1"
    bash "$SCRIPT_DIR/polish/functions.sh" "$TEMP1" "$TEMP2"
    bash "$SCRIPT_DIR/polish/const.sh" "$TEMP2" "$TEMP3"
    bash "$SCRIPT_DIR/polish/let.sh" "$TEMP3" "$TEMP4"
else
    bash "$SCRIPT_DIR/polish/consolelog.sh" "$JS_FILE" "$TEMP1" >/dev/null 2>&1
    bash "$SCRIPT_DIR/polish/functions.sh" "$TEMP1" "$TEMP2" >/dev/null 2>&1
    bash "$SCRIPT_DIR/polish/const.sh" "$TEMP2" "$TEMP3" >/dev/null 2>&1
    bash "$SCRIPT_DIR/polish/let.sh" "$TEMP3" "$TEMP4" >/dev/null 2>&1
fi

# Move final result to output file
mv "$TEMP4" "$OUTPUT_FILE"
# Clean up temporary files
rm -f "$TEMP1" "$TEMP2" "$TEMP3"

exit $?