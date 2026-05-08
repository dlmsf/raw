#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <file.js>${NC}"
    exit 1
fi

# Get the directory where THIS script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve paths relative to script location
JS_FILE="$1"
# If JS_FILE is relative, make it absolute from current working directory
if [[ ! "$JS_FILE" = /* ]]; then
    JS_FILE="$(pwd)/$JS_FILE"
fi

# Raw.sh is always relative to this script's location
RAW_SCRIPT="$SCRIPT_DIR/../../../Raw.sh"
# Make Raw.sh absolute if it's relative
if [[ ! "$RAW_SCRIPT" = /* ]]; then
    RAW_SCRIPT="$(cd "$(dirname "$RAW_SCRIPT")" && pwd)/$(basename "$RAW_SCRIPT")"
fi

FILENAME=$(basename "$JS_FILE")

# Function to strip ANSI color codes
strip_colors() {
    sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

# Function to normalize output (strip colors, remove carriage returns, trim spaces)
normalize() {
    strip_colors | sed 's/\r$//' | sed 's/[[:space:]]*$//' | grep -v '^$'
}

# Run tests silently - using absolute paths
NODE_OUTPUT=$(node "$JS_FILE" 2>&1 | normalize)
RAW_OUTPUT=$(bash "$RAW_SCRIPT" "$JS_FILE" 2>&1 | normalize)

# Compare normalized outputs
if diff -bBw <(echo "$NODE_OUTPUT") <(echo "$RAW_OUTPUT") >/dev/null 2>&1; then
    echo -e "${GREEN}✓ ${BOLD}${FILENAME}${NC}${GREEN} - 100% match${NC}"
    exit 0
else
    # Header with filename and overall status
    echo -e "\n${RED}✗ ${BOLD}${FILENAME}${NC}${RED} - Differences detected${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Calculate similarity
    mapfile -t node_arr <<< "$NODE_OUTPUT"
    mapfile -t raw_arr <<< "$RAW_OUTPUT"
    
    NODE_LINES=${#node_arr[@]}
    RAW_LINES=${#raw_arr[@]}
    MAX_LINES=$((NODE_LINES > RAW_LINES ? NODE_LINES : RAW_LINES))
    
    MATCH=0
    for i in "${!node_arr[@]}"; do
        [[ $i -lt ${#raw_arr[@]} ]] && [[ "${node_arr[$i]}" == "${raw_arr[$i]}" ]] && ((MATCH++))
    done
    
    SIMILARITY=$((MATCH * 100 / MAX_LINES))
    
    # Stats in compact format
    echo -e "${YELLOW}Match: ${SIMILARITY}% (${MATCH}/${MAX_LINES} lines)${NC}"
    
    # Show differences in a cleaner format
    if [[ $NODE_LINES -ne $RAW_LINES ]]; then
        echo -e "${YELLOW}Line count: Node.js=${NODE_LINES}, Raw.sh=${RAW_LINES}${NC}"
    fi
    
    echo -e "\n${BLUE}Differences:${NC}"
    
    # Side-by-side diff with better formatting
    for i in "${!node_arr[@]}"; do
        if [[ $i -ge ${#raw_arr[@]} ]]; then
            echo -e "${RED}Line $((i+1)) only in Node.js:${NC}"
            echo -e "  ${node_arr[$i]}"
        elif [[ "${node_arr[$i]}" != "${raw_arr[$i]}" ]]; then
            echo -e "${YELLOW}Line $((i+1)):${NC}"
            echo -e "  ${CYAN}Node:${NC} ${node_arr[$i]}"
            echo -e "  ${CYAN}Raw :${NC} ${raw_arr[$i]}"
        fi
    done
    
    # Lines only in Raw output
    for i in $(seq ${#node_arr[@]} $((RAW_LINES - 1))); do
        echo -e "${RED}Line $((i+1)) only in Raw.sh:${NC}"
        echo -e "  ${raw_arr[$i]}"
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    exit 1
fi