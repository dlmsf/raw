#!/bin/bash

# ============================================================
# var.sh - Main handler that analyzes JavaScript var declarations
# and delegates to specific type handlers.
# ------------------------------------------------------------
# NEW: Directly handles "var x = y" (variable reference copy)
#      inside this script, without delegating to simple.sh.
#      Also supports REASSIGNMENT mode (bare assignment).
# ============================================================

set -o nounset    # Treat unset variables as an error
set -o pipefail   # Return value of a pipeline is the status of
                  # the last command to exit with a non-zero status

# Determine the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || {
    echo "Error: Failed to change directory to $SCRIPT_DIR"
    exit 1
}

# Default REASSIGNMENT to false if not set
REASSIGNMENT="${REASSIGNMENT:-false}"

VAR_TYPES_DIR="./var_types"

# ------------------------------------------------------------
# Read and sanitise the input file
# ------------------------------------------------------------
INPUT_FILE="var_input"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE file not found in $(pwd)"
    exit 1
fi

# Remove all newlines, leading and trailing whitespace
INPUT_CONTENT=$(tr -d '\n' < "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# ------------------------------------------------------------
# Extract variable name and value from a declaration like:
#   var name = value;
# For reassignment mode, the input may not contain "var" keyword.
# ------------------------------------------------------------
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

# Remove an optional trailing semicolon
VAR_VALUE="${VAR_VALUE%;}"

# Export so that the type handler scripts can use them
export VAR_NAME
export VAR_VALUE

# ============================================================
# Helper functions for type detection
# ============================================================

# ----------------------------------------------------------------------
# is_arithmetic_expression
# ----------------------------------------------------------------------
is_arithmetic_expression() {
    local value="$1"
    value=$(echo "$value" | sed 's/[[:space:]]//g')
    if [[ "$value" =~ \( ]]; then
        local check_value="$value"
        while [[ "$check_value" =~ \(([^()]+)\) ]]; do
            local inner="${BASH_REMATCH[1]}"
            if ! is_arithmetic_expression "$inner"; then
                return 1
            fi
            check_value="${check_value//(${inner})/1}"
        done
        if ! is_arithmetic_expression "$check_value"; then
            return 1
        fi
        return 0
    fi
    local number_pattern='-?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?|-?0[xX][0-9a-fA-F]+|-?0[oO][0-7]+|-?0[bB][01]+'
    if [[ "$value" =~ ^${number_pattern}([-+*/%]${number_pattern})*$ ]]; then
        return 0
    fi
    return 1
}

# ----------------------------------------------------------------------
# is_simple_number
# ----------------------------------------------------------------------
is_simple_number() {
    local str="$1"
    if [[ "$str" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?[0-9]+\.[0-9]*$ ]] || \
       [[ "$str" =~ ^-?\.[0-9]+$ ]] || \
       [[ "$str" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?[0-9]+(\.[0-9]*)?[eE][+-]?[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?0[xX][0-9a-fA-F]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?0[oO][0-7]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?0[bB][01]+$ ]]; then
        return 0
    fi
    if [[ "$str" =~ ^-?0[0-7]+$ ]] && [[ ! "$str" =~ ^-?0[xXoObB] ]]; then
        return 0
    fi
    return 1
}

# ----------------------------------------------------------------------
# is_simple_type
# ----------------------------------------------------------------------
is_simple_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if is_arithmetic_expression "$value"; then
        return 0
    fi
    if [ "$value" = "null" ] || [ "$value" = "undefined" ]; then
        return 0
    fi
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        return 0
    fi
    if is_simple_number "$value"; then
        return 0
    fi
    if [[ "$value" =~ ^\"([^\"]*)\"$ ]] || \
       [[ "$value" =~ ^\'([^\']*)\'$ ]] || \
       [[ "$value" =~ ^\`([^\`]*)\`$ ]]; then
        return 0
    fi
    if [[ "$value" =~ [\"\'] ]]; then
        return 0
    fi
    if [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 0
    fi
    if [[ "$value" =~ [-+*/%] ]]; then
        return 0
    fi
    if [[ "$value" =~ \( ]]; then
        return 0
    fi
    return 1
}

# ----------------------------------------------------------------------
# is_array_type
# ----------------------------------------------------------------------
is_array_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ ! "$value" =~ ^\[.*\]$ ]]; then
        return 1
    fi
    local content="${value:1:${#value}-2}"
    if is_arithmetic_expression "$content" || is_simple_number "$content"; then
        return 1
    fi
    local array_content="$content"
    array_content=$(echo "$array_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$array_content" ]; then
        return 0
    fi
    local elements=()
    local current=""
    local bracket_depth=0
    local brace_depth=0
    local paren_depth=0
    local in_string=false
    local string_char=""
    local i char prev_char
    for (( i=0; i<${#array_content}; i++ )); do
        char="${array_content:$i:1}"
        prev_char=""
        [ $i -gt 0 ] && prev_char="${array_content:$((i-1)):1}"
        if [ "$in_string" = false ]; then
            case "$char" in
                "[") ((bracket_depth++)) ;;
                "]") ((bracket_depth--)) ;;
                "{") ((brace_depth++)) ;;
                "}") ((brace_depth--)) ;;
                "(") ((paren_depth++)) ;;
                ")") ((paren_depth--)) ;;
                '"' | "'" | "\`")
                    in_string=true
                    string_char="$char"
                    ;;
            esac
            if [ "$char" = "," ] && [ $bracket_depth -eq 0 ] && \
               [ $brace_depth -eq 0 ] && [ $paren_depth -eq 0 ]; then
                elements+=("$current")
                current=""
            else
                current="${current}${char}"
            fi
        else
            current="${current}${char}"
            if [ "$char" = "$string_char" ] && [ "$prev_char" != "\\" ]; then
                in_string=false
            fi
        fi
    done
    if [ -n "$current" ]; then
        elements+=("$current")
    fi
    local element
    for element in "${elements[@]}"; do
        element=$(echo "$element" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if ! is_simple_type "$element"; then
            return 1
        fi
    done
    return 0
}

# ----------------------------------------------------------------------
# is_object_type
# ----------------------------------------------------------------------
is_object_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ ! "$value" =~ ^\{.*\}$ ]]; then
        return 1
    fi
    local object_content="${value:1:${#value}-2}"
    object_content=$(echo "$object_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$object_content" ]; then
        return 0
    fi
    local properties=()
    local current=""
    local bracket_depth=0
    local brace_depth=0
    local paren_depth=0
    local in_string=false
    local string_char=""
    local i char prev_char
    for (( i=0; i<${#object_content}; i++ )); do
        char="${object_content:$i:1}"
        prev_char=""
        [ $i -gt 0 ] && prev_char="${object_content:$((i-1)):1}"
        if [ "$in_string" = false ]; then
            case "$char" in
                "[") ((bracket_depth++)) ;;
                "]") ((bracket_depth--)) ;;
                "{") ((brace_depth++)) ;;
                "}") ((brace_depth--)) ;;
                "(") ((paren_depth++)) ;;
                ")") ((paren_depth--)) ;;
                '"' | "'" | "\`")
                    in_string=true
                    string_char="$char"
                    ;;
            esac
            if [ "$char" = "," ] && [ $bracket_depth -eq 0 ] && \
               [ $brace_depth -eq 0 ] && [ $paren_depth -eq 0 ]; then
                properties+=("$current")
                current=""
            else
                current="${current}${char}"
            fi
        else
            current="${current}${char}"
            if [ "$char" = "$string_char" ] && [ "$prev_char" != "\\" ]; then
                in_string=false
            fi
        fi
    done
    if [ -n "$current" ]; then
        properties+=("$current")
    fi
    local prop prop_value
    for prop in "${properties[@]}"; do
        prop=$(echo "$prop" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$prop" =~ ^[^:]*:[[:space:]]*(.*)$ ]]; then
            prop_value="${BASH_REMATCH[1]}"
            prop_value=$(echo "$prop_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if ! is_simple_type "$prop_value"; then
                return 1
            fi
        fi
    done
    return 0
}

# ----------------------------------------------------------------------
# is_complex_type
# ----------------------------------------------------------------------
is_complex_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ ! "$value" =~ ^[\[\{].*[\]\}]$ ]]; then
        return 1
    fi
    local bracket_depth=0
    local brace_depth=0
    local in_string=false
    local string_char=""
    local i char prev_char
    for (( i=0; i<${#value}; i++ )); do
        char="${value:$i:1}"
        prev_char=""
        [ $i -gt 0 ] && prev_char="${value:$((i-1)):1}"
        if [ "$in_string" = false ]; then
            case "$char" in
                "[")
                    ((bracket_depth++))
                    if [ $bracket_depth -gt 1 ] || [ $brace_depth -gt 0 ]; then
                        return 0
                    fi
                    ;;
                "]") ((bracket_depth--)) ;;
                "{")
                    ((brace_depth++))
                    if [ $brace_depth -gt 1 ] || [ $bracket_depth -gt 0 ]; then
                        return 0
                    fi
                    ;;
                "}") ((brace_depth--)) ;;
                '"' | "'" | "\`")
                    in_string=true
                    string_char="$char"
                    ;;
            esac
        else
            if [ "$char" = "$string_char" ] && [ "$prev_char" != "\\" ]; then
                in_string=false
            fi
        fi
    done
    return 1
}

# ============================================================
# Functions for direct variable-reference assignment
# ============================================================

# Correct path: from js/ up two levels to dev/
OUTPUT_FILE="../../build_output.asm"

declare -A VAR_TYPES

# ----------------------------------------------------------------------
# load_existing_variable_types
#   Reads both static data declarations and runtime type assignments,
#   keeping the LATEST occurrence for each variable.
# ----------------------------------------------------------------------
load_existing_variable_types() {
    VAR_TYPES=()
    while IFS= read -r line; do
        # Static: varname_type dq TYPE_XXX
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)_type[[:space:]]+dq[[:space:]]+TYPE_([A-Z_]+) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local type_name="${BASH_REMATCH[2]}"
            VAR_TYPES["$var_name"]="$type_name"
        fi
        # Runtime: mov qword [varname_type], TYPE_XXX
        if [[ "$line" =~ ^[[:space:]]*mov[[:space:]]+qword[[:space:]]+\[([a-zA-Z_][a-zA-Z0-9_]*)_type\][[:space:]]*,[[:space:]]*TYPE_([A-Z_]+) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local type_name="${BASH_REMATCH[2]}"
            VAR_TYPES["$var_name"]="$type_name"
        fi
    done < "$OUTPUT_FILE"
}

# ----------------------------------------------------------------------
# insert_assembly_sections
# ----------------------------------------------------------------------
insert_assembly_sections() {
    local data_section="$1"
    local code_section="$2"
    local temp_file=$(mktemp)
    local in_data=0
    local in_start=0
    local data_done=0
    local code_done=0

    while IFS= read -r line; do
        if [[ "$line" == "section .data" ]]; then
            in_data=1
        elif [[ "$line" == section* ]] && [ "$in_data" -eq 1 ]; then
            if [ "$data_done" -eq 0 ] && [ -n "$data_section" ]; then
                echo "$data_section" >> "$temp_file"
                data_done=1
            fi
            in_data=0
        fi

        if [[ "$line" == "_start:" ]]; then
            in_start=1
        fi

        if [ "$in_start" -eq 1 ] && [ "$code_done" -eq 0 ] && \
           [[ "$line" =~ ^[[:space:]]*mov[[:space:]]+rax,[[:space:]]*60 ]] && \
           [ -n "$code_section" ]; then
            echo "$code_section" >> "$temp_file"
            code_done=1
        fi

        echo "$line" >> "$temp_file"
    done < "$OUTPUT_FILE"

    if [ "$in_data" -eq 1 ] && [ "$data_done" -eq 0 ] && [ -n "$data_section" ]; then
        echo "$data_section" >> "$temp_file"
    fi

    if [ "$code_done" -eq 0 ] && [ -n "$code_section" ]; then
        echo "$code_section" >> "$temp_file"
    fi

    mv "$temp_file" "$OUTPUT_FILE"
}

# ----------------------------------------------------------------------
# handle_variable_reference
# ----------------------------------------------------------------------
handle_variable_reference() {
    local new_var="$1"
    local source_var="$2"

    load_existing_variable_types

    if [ -z "${VAR_TYPES[$source_var]+x}" ]; then
        echo "Error: Referenced variable '$source_var' not found or has unknown type"
        exit 1
    fi

    local source_type="${VAR_TYPES[$source_var]}"
    source_type=$(echo "$source_type" | tr '[:upper:]' '[:lower:]')

    local data_section=""
    local code_section=""

    # In reassignment mode, skip data section
    if [[ "$REASSIGNMENT" != "true" ]]; then
        case "$source_type" in
            float)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: FLOAT (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var}_float_val dq 0"$'\n'
                data_section+="    ${new_var}_str times 32 db 0"$'\n'
                data_section+="    ${new_var} dq ${new_var}_str"$'\n'
                data_section+="    ${new_var}_type dq TYPE_FLOAT"$'\n'
                ;;
            number|int|integer)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: NUMBER (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_float_val dq 0"$'\n'
                data_section+="    ${new_var}_str times 32 db 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_NUMBER"$'\n'
                ;;
            string)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: STRING (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var} db 0"$'\n'
                data_section+="    times (256 - (\$ - ${new_var})) db 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_STRING"$'\n'
                ;;
            boolean)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: BOOLEAN (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_BOOLEAN"$'\n'
                ;;
            null)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: NULL (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_NULL"$'\n'
                ;;
            undefined)
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+=$'    ; Type: UNDEFINED (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 0"$'\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_UNDEFINED"$'\n'
                ;;
            *)
                local upper_type=$(echo "$source_type" | tr '[:lower:]' '[:upper:]')
                data_section+=$'    ; =========================================\n'
                data_section+="    ; Variable: $new_var (copy of $source_var)"$'\n'
                data_section+="    ; Type: $upper_type (copy)"$'\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var}_defined_flag db 1"$'\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_${upper_type}"$'\n'
                ;;
        esac
    fi

    # Code section is always generated
    case "$source_type" in
        float)
            code_section+=$'    ; Copy float variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}_float_val]"$'\n'
            code_section+="    mov qword [${new_var}_float_val], rax"$'\n'
            code_section+="    mov rdi, ${new_var}_str"$'\n'
            code_section+="    movsd xmm0, [${source_var}_float_val]"$'\n'
            code_section+=$'    call float_to_str
'
            code_section+="    mov qword [${new_var}], ${new_var}_str"$'\n'
            code_section+="    mov qword [${new_var}_type], TYPE_FLOAT"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
        number|int|integer)
            code_section+=$'    ; Copy integer variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
        string)
            code_section+=$'    ; Copy string variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rsi, ${source_var}"$'\n'
            code_section+="    mov rdi, ${new_var}"$'\n'
            code_section+=$'    ; copy up to 256 bytes (or until null)\n'
            code_section+="    mov rcx, 256"$'\n'
            code_section+=$'    call copy_string
'
            code_section+="    mov qword [${new_var}_type], TYPE_STRING"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
        boolean)
            code_section+=$'    ; Copy boolean variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
        null)
            code_section+=$'    ; Copy null variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov qword [${new_var}], 0"$'\n'
            code_section+="    mov qword [${new_var}_type], TYPE_NULL"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
        undefined)
            code_section+=$'    ; Copy undefined variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov qword [${new_var}], 0"$'\n'
            code_section+="    mov qword [${new_var}_type], TYPE_UNDEFINED"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 0"$'\n'
            ;;
        *)
            local upper_type=$(echo "$source_type" | tr '[:lower:]' '[:upper:]')
            code_section+=$'    ; Copy variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
            code_section+="    mov byte [${new_var}_defined_flag], 1"$'\n'
            ;;
    esac

    insert_assembly_sections "$data_section" "$code_section"

    if [[ "$REASSIGNMENT" == "true" ]]; then
        echo "✓ Successfully reassigned variable $new_var from $source_var"
    else
        echo "✓ Successfully copied variable $source_var to $new_var"
    fi
    echo "  - Type: $source_type"
    echo "  - Value copied at assembly runtime"
}

# ============================================================
# Main type determination logic
# ============================================================

# Check for direct variable reference assignment
if [[ "$VAR_VALUE" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && \
   [[ "$VAR_VALUE" != "null" && "$VAR_VALUE" != "undefined" && \
      "$VAR_VALUE" != "true" && "$VAR_VALUE" != "false" ]]; then
    handle_variable_reference "$VAR_NAME" "$VAR_VALUE"
    exit 0
fi

# Original type determination
TYPE="unknown"

if is_simple_type "$VAR_VALUE"; then
    TYPE="simple"
elif is_array_type "$VAR_VALUE"; then
    TYPE="array"
elif is_object_type "$VAR_VALUE"; then
    TYPE="object"
elif is_complex_type "$VAR_VALUE"; then
    TYPE="complex"
fi

echo "Detected variable type: $TYPE"
echo "Variable name: $VAR_NAME"
echo "Variable value: $VAR_VALUE"

mkdir -p "$VAR_TYPES_DIR"

TYPE_HANDLER="$VAR_TYPES_DIR/$TYPE.sh"

if [ ! -f "$TYPE_HANDLER" ]; then
    echo "Error: Type handler not found: $TYPE_HANDLER"
    exit 1
fi

export REASSIGNMENT="${REASSIGNMENT:-false}"
echo "Executing handler: $TYPE_HANDLER"
bash "$TYPE_HANDLER"
exit $?
