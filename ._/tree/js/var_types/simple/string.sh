#!/bin/bash

# string.sh - String declarations and reassignments
# Supports REASSIGNMENT mode with fixed 256-byte buffer.

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
            if [ $char_code -lt 128 ]; then
                result="${result}${char_code}, "
            fi
            i=$((i+1))
        fi
    done
    result="${result%, }"
    if [ -n "$result" ]; then
        echo "${result}, 0"
    else
        echo "0"
    fi
}

# Function to extract string content
extract_string_content() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$value" =~ ^\"([^\"]*)\"$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$value" =~ ^\'([^\']*)\'$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$value" =~ \+ ]]; then
        local result=""
        IFS='+' read -ra PARTS <<< "$value"
        for part in "${PARTS[@]}"; do
            part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$part" =~ ^\"([^\"]*)\"$ ]]; then
                result+="${BASH_REMATCH[1]}"
            elif [[ "$part" =~ ^\'([^\']*)\'$ ]]; then
                result+="${BASH_REMATCH[1]}"
            else
                result+="$part"
            fi
        done
        echo "$result"
        return
    fi
    echo "$value"
}

STRING_CONTENT=$(extract_string_content "$VAR_VALUE")
ESCAPED_STRING=$(escape_for_nasm "$STRING_CONTENT")

if [[ "$REASSIGNMENT" == "true" ]]; then
    STR_LEN=${#STRING_CONTENT}
    if [ $STR_LEN -gt 255 ]; then
        echo "Error: String too long for reassignment (max 255)"
        exit 1
    fi

    CODE_SECTION="    ; Reassign string variable: $VAR_NAME = \"$STRING_CONTENT\""$'\n'
    CODE_SECTION+="    ; Copy new string into existing buffer (length ${STR_LEN})"$'\n'
    CODE_SECTION+="    mov rdi, ${VAR_NAME}"$'\n'

    for (( idx=0; idx<STR_LEN; idx++ )); do
        char_code=$(printf "%d" "'${STRING_CONTENT:$idx:1}")
        CODE_SECTION+="    mov byte [rdi + $idx], $char_code"$'\n'
    done
    CODE_SECTION+="    mov byte [rdi + $STR_LEN], 0"$'\n'
    CODE_SECTION+="    mov qword [${VAR_NAME}_type], TYPE_STRING"$'\n'
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

    echo "✓ Successfully reassigned string variable: $VAR_NAME = \"$STRING_CONTENT\""
    exit 0
fi

# Initial declaration with fixed 256-byte buffer
ASSEMBLY_DATA="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ; Variable: $VAR_NAME = \"$STRING_CONTENT\""$'\n'
ASSEMBLY_DATA+="    ; Type: STRING"$'\n'
ASSEMBLY_DATA+="    ; ========================================="$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_defined_flag db 1"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME} db $ESCAPED_STRING"$'\n'
ASSEMBLY_DATA+="    times (256 - (\$ - ${VAR_NAME})) db 0"$'\n'
ASSEMBLY_DATA+="    ${VAR_NAME}_type dq TYPE_STRING"$'\n'

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

echo "✓ Successfully added string variable: $VAR_NAME = \"$STRING_CONTENT\""
exit 0
