#!/bin/bash

# boolean.sh - Boolean declarations and reassignments
# Supports REASSIGNMENT mode.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SCRIPT_DIR/simple"

OUTPUT_FILE="../../../../build_output.asm"
INPUT_FILE="../../var_input"

REASSIGNMENT="${REASSIGNMENT:-false}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
fi

INPUT_CONTENT=$(cat "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
INPUT_CONTENT="${INPUT_CONTENT%;}"

if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
elif [[ "$REASSIGNMENT" == "true" && "$INPUT_CONTENT" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
else
    echo "Error: Invalid variable declaration format"
    exit 1
fi

VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
NORMALIZED_VALUE=$(echo "$VAR_VALUE" | tr '[:upper:]' '[:lower:]')

case "$NORMALIZED_VALUE" in
    "true" | "false")
        ;;
    *)
        echo "Error: Invalid boolean value '$VAR_VALUE'"
        exit 1
        ;;
esac

BOOLEAN_NUMERIC=0
BOOLEAN_DISPLAY="false"
if [ "$NORMALIZED_VALUE" = "true" ]; then
    BOOLEAN_NUMERIC=1
    BOOLEAN_DISPLAY="true"
fi

if [[ "$REASSIGNMENT" == "true" ]]; then
    CODE_SECTION="    ; Reassign boolean variable: $VAR_NAME = $BOOLEAN_DISPLAY"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}], $BOOLEAN_NUMERIC"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}_type], TYPE_BOOLEAN"$'\n'
    CODE_SECTION+="    mov byte [${VAR_NAME}_defined_flag], 1"$'\n'

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
    exit 0
fi

# Initial declaration
ASSEMBLY_DATA="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ; Variable: $VAR_NAME = $BOOLEAN_DISPLAY"$'\n'
ASSEMBLY_DATA+="    ; Type: BOOLEAN"$'\n'
ASSEMBLY_DATA+="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_defined_flag db 1"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME} dq $BOOLEAN_NUMERIC"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_type dq TYPE_BOOLEAN"$'\n'

TEMP_FILE=$(mktemp)
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

echo "✓ Successfully added boolean variable: $VAR_NAME = $BOOLEAN_DISPLAY"
exit 0
