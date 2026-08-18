#!/bin/bash

# string.sh - Converts JavaScript string declarations to NASM assembly data structures
# Generates runtime type tags compatible with the new log.sh
# Supports REASSIGNMENT mode: copies the new string into the existing string buffer
# (assuming the new string length does not exceed the original allocation).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SCRIPT_DIR/simple"

OUTPUT_FILE="../../../../build_output.asm"
INPUT_FILE="../../var_input"

# Default REASSIGNMENT to false if not set
REASSIGNMENT="${REASSIGNMENT:-false}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
fi

# Read and clean the input
INPUT_CONTENT=$(cat "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Remove trailing semicolon if present
INPUT_CONTENT="${INPUT_CONTENT%;}"

# Extract variable name and value
# In reassignment mode, the input lacks the "var" keyword.
if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
elif [[ "$REASSIGNMENT" == "true" && "$INPUT_CONTENT" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
else
    echo "Error: Invalid variable declaration format"
    echo "Expected format: var variableName = value"
    exit 1
fi

# Remove surrounding whitespace
VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

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

# In reassignment mode, generate code to copy the new string into the existing location.
if [[ "$REASSIGNMENT" == "true" ]]; then
    # We assume the existing string buffer is large enough. For simplicity, we copy byte by byte.
    # First, calculate length of new string (excluding null terminator)
    STR_LEN=${#STRING_CONTENT}

    CODE_SECTION="    ; Reassign string variable: $VAR_NAME = \"$STRING_CONTENT\""$'\n'
    CODE_SECTION+="    ; Copy new string into existing buffer (length ${STR_LEN})"$'\n'

    # Load address of destination into rdi
    CODE_SECTION+="    mov rdi, ${VAR_NAME}"$'\n'

    # We need to write each byte. We'll generate a series of mov instructions.
    # For simplicity, we unroll the loop (since string length is known at compile time).
    local i
    for (( i=0; i<STR_LEN; i++ )); do
        char_code=$(printf "%d" "'${STRING_CONTENT:$i:1}")
        CODE_SECTION+="    mov byte [rdi + $i], $char_code"$'\n'
    done
    # Null terminator
    CODE_SECTION+="    mov byte [rdi + $STR_LEN], 0"$'\n'
    # Update type tag (if not already STRING)
    CODE_SECTION+="    mov qword [${VAR_NAME}_type], TYPE_STRING"$'\n'

    # Insert code section into assembly file
    TEMP_FILE=$(mktemp)
    IN_START=0
    CODE_DONE=0

    while IFS= read -r line; do
        if [[ "$line" == "_start:" ]]; then
            IN_START=1
        fi

        if [ "$IN_START" -eq 1 ] && [ "$CODE_DONE" -eq 0 ] && \
           [[ "$line" =~ ^[[:space:]]*mov[[:space:]]+rax,[[:space:]]*60 ]] && \
           [ -n "$CODE_SECTION" ]; then
            echo "$CODE_SECTION" >> "$TEMP_FILE"
            CODE_DONE=1
        fi

        echo "$line" >> "$TEMP_FILE"
    done < "$OUTPUT_FILE"

    if [ "$CODE_DONE" -eq 0 ] && [ -n "$CODE_SECTION" ]; then
        echo "$CODE_SECTION" >> "$TEMP_FILE"
    fi

    mv "$TEMP_FILE" "$OUTPUT_FILE"

    echo "✓ Successfully reassigned string variable: $VAR_NAME = \"$STRING_CONTENT\""
    echo "  - New string copied into existing buffer (length ${STR_LEN})"
    exit 0
fi

# -------- Original behaviour for initial declaration --------
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
    if [[ "$line" == "section .data" ]]; then
        IN_DATA_SECTION=1
        echo "$line" >> "$TEMP_FILE"
        continue
    fi
   
    if [[ "$IN_DATA_SECTION" -eq 1 ]] && [[ "$line" == section* ]]; then
        if [ "$DATA_INSERTED" -eq 0 ]; then
            echo "$ASSEMBLY_DATA" >> "$TEMP_FILE"
            DATA_INSERTED=1
        fi
       
        IN_DATA_SECTION=0
    fi
   
    echo "$line" >> "$TEMP_FILE"
   
done < "$OUTPUT_FILE"

if [[ "$IN_DATA_SECTION" -eq 1 ]] && [ "$DATA_INSERTED" -eq 0 ]; then
    echo "$ASSEMBLY_DATA" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$OUTPUT_FILE"

echo "✓ Successfully added string variable: $VAR_NAME = \"$STRING_CONTENT\""
echo "  - Runtime type tag: TYPE_STRING"
echo "  - String length: ${#STRING_CONTENT} characters"
echo "  - Variable accessible via: mov rax, $VAR_NAME"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0
