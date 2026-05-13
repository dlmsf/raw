#!/bin/bash

# Self-extracting JavaScript file generator
# This script will recreate the original JavaScript file

set -e

# Get the original filename from the script name
SCRIPT_NAME="$(basename "$0")"
OUTPUT_FILE="${SCRIPT_NAME%.*}.js"

# Auto-overwrite if file exists (no prompt)
if [ -f "$OUTPUT_FILE" ]; then
    echo "Overwriting existing file: $OUTPUT_FILE"
fi

# Find where the embedded data starts
# Look for the base64 data after the marker
SCRIPT_END_MARKER="#===BEGIN_BASE64_DATA==="

# Get the line number of the marker
MARKER_LINE=$(grep -n "^${SCRIPT_END_MARKER}$" "$0" | cut -d: -f1)

if [ -z "$MARKER_LINE" ]; then
    echo "Error: Could not find embedded data marker" >&2
    exit 1
fi

# Extract the base64 data (starts after the marker)
DATA_START_LINE=$((MARKER_LINE + 1))

# Get all lines from the data start to end of file
# and decode from base64
# Compatible with both GNU base64 (--decode) and BusyBox base64 (-d)
tail -n +"${DATA_START_LINE}" "$0" | base64 -d > "$OUTPUT_FILE" 2>/dev/null || \
tail -n +"${DATA_START_LINE}" "$0" | base64 --decode > "$OUTPUT_FILE"

# Verify extraction
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    echo "Successfully created: $OUTPUT_FILE"
    echo "Size: $(wc -c < "$OUTPUT_FILE") bytes"
    
    # Make executable if it starts with shebang
    if head -n1 "$OUTPUT_FILE" | grep -q "^#!"; then
        chmod +x "$OUTPUT_FILE"
        echo "Made executable (has shebang)"
    fi
else
    echo "Error: Failed to extract JavaScript file" >&2
    exit 1
fi

exit 0

#===BEGIN_BASE64_DATA===
bGV0IGEgPSB1bmRlZmluZWQKbGV0IGIgPSAnZ2FtbWEnCmxldCBjID0gJ2RlbHRhJwpjb25zdCBk
ID0gMTAwLzMgKyA0NSoyIC0gNy8xMQpsZXQgZSA9IGZhbHNlCmxldCBvdXRybyA9IDUwMC83ICog
My8xMyArIDIyIC0gMTkvNgpjb25zdCBvcGEgPSBudWxsCmxldCB4ID0gMzU1LzExMyAtIDIyLzcg
KyAxMDAvMwpsZXQgeSA9IDEvMyArIDEvNyArIDEvOSArIDEvMTEKY29uc3QgeiA9IDEwMDAvODEg
KiAxNy8yMyAtIDUvMTkKbGV0IHcgPSA3NzcvMTMgKyA0OS8yNyAtIDEyMy8xNwpjb25zdCB2ID0g
MjU2LzQ5ICogMzMvMTkgKyAxMDEvNwpsZXQgdSA9IDEvNyArIDEvMTMgKyAxLzE3ICsgMS8xOSAr
IDEvMjMKY29uc3QgdCA9IDk5OS8zNyAtIDU1NS8xOSArIDIyMi81MwpsZXQgcyA9IDQ0NC8xMSAq
IDc3LzMxIC0gMTExLzcxCmNvbnN0IHIgPSAxMDAwLzMgLSAyMDAvOSArIDUwLzI3CmxldCBxID0g
MTMvNyArIDIyLzkgLSAxNy8xMSArIDI5LzEzCmNvbnNvbGUubG9nKG91dHJvKQpjb25zb2xlLmxv
ZyhhKQpjb25zb2xlLmxvZyhiKQpjb25zb2xlLmxvZyhjKQpjb25zb2xlLmxvZyhvcGEpCmNvbnNv
bGUubG9nKGQpCmNvbnNvbGUubG9nKGUpCmNvbnNvbGUubG9nKHgpCmNvbnNvbGUubG9nKHkpCmNv
bnNvbGUubG9nKHopCmNvbnNvbGUubG9nKHcpCmNvbnNvbGUubG9nKHYpCmNvbnNvbGUubG9nKHUp
CmNvbnNvbGUubG9nKHQpCmNvbnNvbGUubG9nKHMpCmNvbnNvbGUubG9nKHIpCmNvbnNvbGUubG9n
KHEpCmNvbnNvbGUubG9nKG51bGwp
