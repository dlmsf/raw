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
Ly8gRmlsZSB3aXRoIG5lc3RlZC1saWtlIG9wZXJhdGlvbnMKbGV0IGEgPSB1bmRlZmluZWQKbGV0
IGIgPSAnZXBzaWxvbicKbGV0IGMgPSAnemV0YScKY29uc3QgZCA9IDc1KzI1LzUtMTAqMys0MC84
IC8vIHNlcXVlbnRpYWwgb3BlcmF0aW9ucwpsZXQgZSA9IGZhbHNlCmxldCBvdXRybyA9IDkwLzMq
MisxNS0xMi80KzcgLy8gbXVsdGlwbGUgc3RlcHMKY29uc3Qgb3BhID0gbnVsbAovLyBEaXNwbGF5
IHNlY3Rpb24KY29uc29sZS5sb2cob3V0cm8pCmNvbnNvbGUubG9nKHVuZGVmaW5lZCkKY29uc29s
ZS5sb2coYSkKY29uc29sZS5sb2coYikKY29uc29sZS5sb2coYykKY29uc29sZS5sb2coMjU2KQpj
b25zb2xlLmxvZyhvcGEpCmNvbnNvbGUubG9nKDEyOCkKY29uc29sZS5sb2coZCkKY29uc29sZS5s
b2codHJ1ZSkKY29uc29sZS5sb2coZmFsc2UpCmNvbnNvbGUubG9nKCcqKioqKicpCmNvbnNvbGUu
bG9nKGUpCmNvbnNvbGUubG9nKGEpCmNvbnNvbGUubG9nKGMpCmNvbnNvbGUubG9nKG51bGwpCg==
