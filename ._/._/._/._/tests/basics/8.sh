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
Ly8gRXh0ZW5kZWQgY2FsY3VsYXRpb24gdGVzdApsZXQgYSA9IHVuZGVmaW5lZApsZXQgYiA9ICdl
dGEnCmxldCBjID0gJ3RoZXRhJwpjb25zdCBkID0gMTUwLzMrMjAqNS00NS85KzEyIC8vIGV4dGVu
ZGVkIG1hdGgKbGV0IGUgPSB0cnVlCmxldCBvdXRybyA9IDEyMCoyLzYrMzUtMTgvMys5IC8vIGNv
bXBsZXggZXhwcmVzc2lvbgpjb25zdCBvcGEgPSBudWxsCi8vIFByaW50IGV2ZXJ5dGhpbmcKY29u
c29sZS5sb2cob3V0cm8pCmNvbnNvbGUubG9nKHVuZGVmaW5lZCkKY29uc29sZS5sb2coYSkKY29u
c29sZS5sb2coYikKY29uc29sZS5sb2coYykKY29uc29sZS5sb2coNTEyKQpjb25zb2xlLmxvZyhv
cGEpCmNvbnNvbGUubG9nKDIxNikKY29uc29sZS5sb2coZCkKY29uc29sZS5sb2codHJ1ZSkKY29u
c29sZS5sb2coZmFsc2UpCmNvbnNvbGUubG9nKCcrKysrKycpCmNvbnNvbGUubG9nKGUpCmNvbnNv
bGUubG9nKGEpCmNvbnNvbGUubG9nKGMpCmNvbnNvbGUubG9nKG51bGwpCg==
