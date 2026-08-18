#!/bin/bash

# undefined.sh - Converts JavaScript undefined declarations to NASM assembly data structures
# Generates runtime type tags compatible with the new log.sh
# In JavaScript, undefined represents a variable that has been declared but not assigned a value
# Supports REASSIGNMENT mode: updates the variable to undefined.

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
    echo "Expected format: var variableName = undefined"
    exit 1
fi

# Remove surrounding whitespace
VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Validate that the value is actually undefined (case insensitive)
if [[ ! "$VAR_VALUE" =~ ^[Uu]ndefined$ ]]; then
    echo "Error: Expected 'undefined' but got '$VAR_VALUE'"
    exit 1
fi

if [[ "$REASSIGNMENT" == "true" ]]; then
    # Reassignment mode: generate code to update the existing variable to undefined
    CODE_SECTION="    ; Reassign undefined variable: $VAR_NAME = undefined"$'\n'
    CODE_SECTION+="    mov byte [${VAR_NAME}_defined_flag], 0"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}], 0"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}_type], TYPE_UNDEFINED"$'\n'

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

    echo "✓ Successfully reassigned undefined variable: $VAR_NAME = undefined"
    echo "  - Defined flag cleared"
    exit 0
fi

# -------- Original behaviour for initial declaration --------
# Generate assembly data with RUNTIME TYPE TAG
ASSEMBLY_DATA="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ; Variable: $VAR_NAME = undefined"$'\n'
ASSEMBLY_DATA+="    ; Type: UNDEFINED"$'\n'
ASSEMBLY_DATA+="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_defined_flag db 0    ; 0 = undefined, 1 = defined"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME} dq 0    ; Placeholder for future value"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_type dq TYPE_UNDEFINED    ; RUNTIME TYPE TAG"$'\n'

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

echo "✓ Successfully added undefined variable: $VAR_NAME = undefined"
echo "  - Runtime type tag: TYPE_UNDEFINED"
echo "  - Defined flag: 0 (can be changed to 1 when value is assigned)"
echo "  - Variable accessible via: mov rax, [$VAR_NAME]"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0
