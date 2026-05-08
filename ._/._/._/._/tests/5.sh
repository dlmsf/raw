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
Ly8gVGhpcyBpcyBhIHNpbXBsZSB0ZXN0IGZpbGUKbGV0IGEgPSB1bmRlZmluZWQgLy8gdW5kZWZp
bmVkIHZhcmlhYmxlCmxldCBiID0gJ2ZpcnN0JyAvLyBzdHJpbmcgdmFsdWUKbGV0IGMgPSAnc2Vj
b25kJyAvLyBhbm90aGVyIHN0cmluZwpjb25zdCBkID0gNTAvMisxMCo0LTYgLy8gY29tcGxleCBj
YWxjdWxhdGlvbgovLyBUaGlzIGlzIGEgYm9vbGVhbiBmbGFnCmxldCBlID0gZmFsc2UKbGV0IG91
dHJvID0gNDAqMi84KzE1IC8vIG91dHJvIGNhbGN1bGF0aW9uCmNvbnN0IG9wYSA9IG51bGwgLy8g
bnVsbCB2YWx1ZQovLyBDb25zb2xlIG91dHB1dCBzZWN0aW9uCmNvbnNvbGUubG9nKG91dHJvKSAv
LyBvdXRwdXQgb3V0cm8KY29uc29sZS5sb2codW5kZWZpbmVkKSAvLyBvdXRwdXQgdW5kZWZpbmVk
CmNvbnNvbGUubG9nKGEpIC8vIG91dHB1dCBhCmNvbnNvbGUubG9nKGIpIC8vIG91dHB1dCBiCmNv
bnNvbGUubG9nKGMpIC8vIG91dHB1dCBjCmNvbnNvbGUubG9nKDk5KSAvLyBudW1iZXIgb3V0cHV0
CmNvbnNvbGUubG9nKG9wYSkgLy8gb3V0cHV0IG9wYQpjb25zb2xlLmxvZyg2NCkgLy8gYW5vdGhl
ciBudW1iZXIKY29uc29sZS5sb2coZCkgLy8gb3V0cHV0IGQKY29uc29sZS5sb2codHJ1ZSkgLy8g
Ym9vbGVhbiB0cnVlCmNvbnNvbGUubG9nKGZhbHNlKSAvLyBib29sZWFuIGZhbHNlCmNvbnNvbGUu
bG9nKCctLS0tLScpIC8vIHNlcGFyYXRvcgovLyBNb3JlIG91dHB1dHMKY29uc29sZS5sb2coZSkg
Ly8gb3V0cHV0IGUKY29uc29sZS5sb2coYSkgLy8gb3V0cHV0IGEgYWdhaW4KY29uc29sZS5sb2co
YykgLy8gb3V0cHV0IGMgYWdhaW4KY29uc29sZS5sb2cobnVsbCkgLy8gb3V0cHV0IG51bGwK
