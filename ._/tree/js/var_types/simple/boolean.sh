#!/bin/bash

# boolean.sh - Converts JavaScript boolean declarations to NASM assembly data structures
# Generates runtime type tags compatible with the new log.sh
# Supports REASSIGNMENT mode: only generates code to update the existing variable.

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

# Normalize boolean value (handle case-insensitive)
NORMALIZED_VALUE=$(echo "$VAR_VALUE" | tr '[:upper:]' '[:lower:]')

# Validate and convert boolean value
case "$NORMALIZED_VALUE" in
    "true" | "false")
        # Valid boolean value
        ;;
    *)
        echo "Error: Invalid boolean value '$VAR_VALUE'"
        echo "Boolean values must be 'true' or 'false'"
        exit 1
        ;;
esac

# Convert boolean to assembly representation
# Using: true = 1, false = 0
BOOLEAN_NUMERIC=0
BOOLEAN_DISPLAY="false"
if [ "$NORMALIZED_VALUE" = "true" ]; then
    BOOLEAN_NUMERIC=1
    BOOLEAN_DISPLAY="true"
fi

if [[ "$REASSIGNMENT" == "true" ]]; then
    # Reassignment mode: generate code to update existing variable
    CODE_SECTION="    ; Reassign boolean variable: $VAR_NAME = $BOOLEAN_DISPLAY"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}], $BOOLEAN_NUMERIC"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}_type], TYPE_BOOLEAN"$'\n'

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

    echo "✓ Successfully reassigned boolean variable: $VAR_NAME = $BOOLEAN_DISPLAY"
    echo "  - Value updated at runtime"
    exit 0
fi

# -------- Original behaviour for initial declaration --------
# Generate assembly data with RUNTIME TYPE TAG
ASSEMBLY_DATA="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ; Variable: $VAR_NAME = $BOOLEAN_DISPLAY"$'\n'
ASSEMBLY_DATA+="    ; Type: BOOLEAN"$'\n'
ASSEMBLY_DATA+="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME} dq $BOOLEAN_NUMERIC    ; boolean value (0=false, 1=true)"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_type dq TYPE_BOOLEAN    ; RUNTIME TYPE TAG"$'\n'

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

echo "✓ Successfully added boolean variable: $VAR_NAME = $BOOLEAN_DISPLAY"
echo "  - Runtime type tag: TYPE_BOOLEAN"
echo "  - Value stored as: $BOOLEAN_NUMERIC"
echo "  - Variable accessible via: mov rax, [$VAR_NAME]"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0
