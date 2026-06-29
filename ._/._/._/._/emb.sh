#!/bin/bash

# Function to process a single JavaScript file
process_file() {
    local input_file="$1"
    
    # Check if the file exists
    if [ ! -f "$input_file" ]; then
        echo "Error: File '$input_file' does not exist"
        return 1
    fi

    # Get the base filename (without path)
    local filename=$(basename "$input_file")
    
    # Create the output shell script name (same name as .js but with .sh extension)
    local output_script="${filename%.*}.sh"

    echo "Processing: $filename"

    # Create the self-extracting shell script
    if ! cat > "$output_script" << 'EOF'
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
EOF
    then
        echo "Error: Failed to create script template for $filename"
        return 1
    fi

    # Encode the file in base64 and append it
    # Using base64 without options (works everywhere, though may wrap lines)
    if ! base64 "$input_file" >> "$output_script"; then
        echo "Error: Failed to encode $filename to base64"
        rm -f "$output_script"  # Clean up partial file
        return 1
    fi

    # Make the generated script executable
    if ! chmod +x "$output_script"; then
        echo "Error: Failed to make $output_script executable"
        return 1
    fi

    echo "  Created self-extracting script: $output_script"
    echo "  Original file: $filename ($(wc -c < "$input_file") bytes)"
    echo ""
    return 0
}

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <javascript-file.js> [javascript-file.js2 ...]"
    echo "       $0 <directory>"
    exit 1
fi

# Process all arguments WITHOUT set -e at the top level
processed_count=0
for arg in "$@"; do
    echo "Processing argument: '$arg'"
    
    if [ -d "$arg" ]; then
        echo "Argument is a directory"
        echo "Processing all .js files in directory: $arg"
        echo "=============================================="
        
        # Get the absolute path
        if [ "$arg" = "." ]; then
            dir_path="$(pwd)"
        else
            dir_path="$(cd "$arg" && pwd)"
        fi
        
        echo "Directory path: $dir_path"
        
        # Use a simple for loop without process substitution
        shopt -s nullglob  # Make globs return empty if no matches
        for js_file in "$dir_path"/*.js; do
            echo "Found file: $js_file"
            if process_file "$js_file"; then
                ((processed_count++))
            else
                echo "Failed to process: $js_file"
            fi
        done
        shopt -u nullglob
        
    elif [ -f "$arg" ]; then
        echo "Argument is a file"
        if [[ "$arg" == *.js ]]; then
            if process_file "$arg"; then
                ((processed_count++))
            else
                echo "Failed to process: $arg"
            fi
        else
            echo "Warning: '$arg' is not a .js file, skipping"
        fi
    else
        echo "Warning: '$arg' is not a file or directory, skipping"
    fi
done

echo "=============================================="
echo "Processing complete!"
echo "Total files processed: $processed_count"