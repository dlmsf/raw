#!/bin/bash

# string.sh - Converts JavaScript string declarations to NASM assembly data structures
# Generates runtime type tags compatible with the new log.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SCRIPT_DIR/simple"

OUTPUT_FILE="../../../../build_output.asm"
INPUT_FILE="../../var_input"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
fi

# Read and clean the input
INPUT_CONTENT=$(cat "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Remove trailing semicolon if present
INPUT_CONTENT="${INPUT_CONTENT%;}"

# Extract variable name and value
if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
    # Remove surrounding whitespace
    VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
else
    echo "Error: Invalid variable declaration format"
    echo "Expected format: var variableName = value"
    exit 1
fi

# Function to escape strings for NASM
escape_for_nasm() {
    local str="$1"
    
    if [ -z "$str" ]; then
        echo "0"
        return
    fi
    
    local result=""
    local i=0
    local len=${#str}
    
    while [ $i -lt $len ]; do
        local char="${str:$i:1}"
        local char_code=$(printf "%d" "'$char")
        
        # Handle escape sequences
        if [ "$char" = "\\" ] && [ $((i+1)) -lt $len ]; then
            local next_char="${str:$((i+1)):1}"
            case "$next_char" in
                n)  result="${result}10, " ;;
                t)  result="${result}9, " ;;
                r)  result="${result}13, " ;;
                \\\\) result="${result}92, " ;;
                \") result="${result}34, " ;;
                \') result="${result}39, " ;;
                *)  result="${result}92, ${next_char}, " ;;
            esac
            i=$((i+2))
        else
            # ASCII characters (0-127) - single byte
            if [ $char_code -lt 128 ]; then
                result="${result}${char_code}, "
            fi
            i=$((i+1))
        fi
    done
    
    # Remove trailing comma and space, add null terminator
    result="${result%, }"
    if [ -n "$result" ]; then
        echo "${result}, 0"
    else
        echo "0"
    fi
}

# Function to extract string content (handles quotes and concatenation)
extract_string_content() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # If it's a simple quoted string
    if [[ "$value" =~ ^\"([^\"]*)\"$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    if [[ "$value" =~ ^\'([^\']*)\'$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # If it contains concatenation with +, extract all string parts
    if [[ "$value" =~ \+ ]]; then
        local result=""
        
        # Split by + and process each part
        IFS='+' read -ra PARTS <<< "$value"
        for part in "${PARTS[@]}"; do
            part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # If part is quoted
            if [[ "$part" =~ ^\"([^\"]*)\"$ ]]; then
                result+="${BASH_REMATCH[1]}"
            elif [[ "$part" =~ ^\'([^\']*)\'$ ]]; then
                result+="${BASH_REMATCH[1]}"
            else
                # If it's not quoted, treat as string representation of the value
                result+="$part"
            fi
        done
        
        echo "$result"
        return
    fi
    
    # If no quotes found but we determined it's a string, use the value as-is
    echo "$value"
}

# Extract string content
STRING_CONTENT=$(extract_string_content "$VAR_VALUE")
ESCAPED_STRING=$(escape_for_nasm "$STRING_CONTENT")

# Generate assembly data with RUNTIME TYPE TAG
ASSEMBLY_DATA="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ; Variable: $VAR_NAME = \"$STRING_CONTENT\""$'\n'
ASSEMBLY_DATA+="    ; Type: STRING"$'\n'
ASSEMBLY_DATA+="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME} db $ESCAPED_STRING    ; String data"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_type dq TYPE_STRING    ; RUNTIME TYPE TAG"$'\n'

# Create temporary file
TEMP_FILE=$(mktemp)

# Insert data into .data section
IN_DATA_SECTION=0
DATA_INSERTED=0

while IFS= read -r line; do
    # Check if we're entering the data section
    if [[ "$line" == "section .data" ]]; then
        IN_DATA_SECTION=1
        echo "$line" >> "$TEMP_FILE"
        continue
    fi
    
    # Check if we're leaving the data section
    if [[ "$IN_DATA_SECTION" -eq 1 ]] && [[ "$line" == section* ]]; then
        # We're leaving data section, insert our data before leaving
        if [ "$DATA_INSERTED" -eq 0 ]; then
            echo "$ASSEMBLY_DATA" >> "$TEMP_FILE"
            DATA_INSERTED=1
        fi
        
        IN_DATA_SECTION=0
    fi
    
    # Write the current line
    echo "$line" >> "$TEMP_FILE"
    
done < "$OUTPUT_FILE"

# If we're still in data section at EOF, append data
if [[ "$IN_DATA_SECTION" -eq 1 ]] && [ "$DATA_INSERTED" -eq 0 ]; then
    echo "$ASSEMBLY_DATA" >> "$TEMP_FILE"
fi

# Replace the original file
mv "$TEMP_FILE" "$OUTPUT_FILE"

echo "✓ Successfully added string variable: $VAR_NAME = \"$STRING_CONTENT\""
echo "  - Runtime type tag: TYPE_STRING"
echo "  - String length: ${#STRING_CONTENT} characters"
echo "  - Variable accessible via: mov rax, $VAR_NAME"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0