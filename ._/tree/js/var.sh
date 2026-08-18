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
# We still parse it as if it were a declaration, using the variable name.
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
#   Returns 0 (true) if the argument contains ONLY numbers, decimal
#   points, arithmetic operators (+ - * / %), and parentheses,
#   i.e. a pure arithmetic expression without any variable names.
# ----------------------------------------------------------------------
is_arithmetic_expression() {
    local value="$1"
    # Remove all whitespace
    value=$(echo "$value" | sed 's/[[:space:]]//g')

    # If parentheses exist, recursively validate each parenthesised group
    if [[ "$value" =~ \( ]]; then
        local check_value="$value"
        while [[ "$check_value" =~ \(([^()]+)\) ]]; do
            local inner="${BASH_REMATCH[1]}"
            if ! is_arithmetic_expression "$inner"; then
                return 1
            fi
            # Replace the validated parenthesised expression with a placeholder number
            check_value="${check_value//(${inner})/1}"
        done
        # Now check the remaining expression (which contains only placeholders)
        if ! is_arithmetic_expression "$check_value"; then
            return 1
        fi
        return 0
    fi

    # Pattern for any numeric literal (decimal, hex, octal, binary, scientific)
    local number_pattern='-?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?|-?0[xX][0-9a-fA-F]+|-?0[oO][0-7]+|-?0[bB][01]+'

    # A pure arithmetic expression is: number (operator number)*
    if [[ "$value" =~ ^${number_pattern}([-+*/%]${number_pattern})*$ ]]; then
        return 0
    fi

    return 1
}

# ----------------------------------------------------------------------
# is_simple_number
#   Returns 0 if the argument is a single numeric literal (no operators).
# ----------------------------------------------------------------------
is_simple_number() {
    local str="$1"

    # Decimal integer
    if [[ "$str" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi

    # Decimal with a decimal point (e.g. 1.2, .5, 5.)
    if [[ "$str" =~ ^-?[0-9]+\.[0-9]*$ ]] || \
       [[ "$str" =~ ^-?\.[0-9]+$ ]] || \
       [[ "$str" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        return 0
    fi

    # Scientific notation
    if [[ "$str" =~ ^-?[0-9]+(\.[0-9]*)?[eE][+-]?[0-9]+$ ]]; then
        return 0
    fi

    # Hexadecimal (0x or 0X)
    if [[ "$str" =~ ^-?0[xX][0-9a-fA-F]+$ ]]; then
        return 0
    fi

    # Octal with 0o/0O prefix
    if [[ "$str" =~ ^-?0[oO][0-7]+$ ]]; then
        return 0
    fi

    # Binary with 0b/0B prefix
    if [[ "$str" =~ ^-?0[bB][01]+$ ]]; then
        return 0
    fi

    # Legacy octal (leading zero, no prefix, only digits 0-7)
    if [[ "$str" =~ ^-?0[0-7]+$ ]] && [[ ! "$str" =~ ^-?0[xXoObB] ]]; then
        return 0
    fi

    return 1
}

# ----------------------------------------------------------------------
# is_simple_type
#   Returns 0 if the value is a "simple" type:
#   null, undefined, boolean, number, string, an arithmetic expression
#   with only numbers, an expression containing operators and/or
#   variable names (e.g. a + b, p*q+2), or a single variable reference.
# ----------------------------------------------------------------------
is_simple_type() {
    local value="$1"
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 1. Pure arithmetic expression (numbers + operators + parentheses)
    if is_arithmetic_expression "$value"; then
        return 0
    fi

    # 2. null or undefined
    if [ "$value" = "null" ] || [ "$value" = "undefined" ]; then
        return 0
    fi

    # 3. Boolean literals
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        return 0
    fi

    # 4. Simple number (no operators)
    if is_simple_number "$value"; then
        return 0
    fi

    # 5. Quoted string (single, double, backtick)
    if [[ "$value" =~ ^\"([^\"]*)\"$ ]] || \
       [[ "$value" =~ ^\'([^\']*)\'$ ]] || \
       [[ "$value" =~ ^\`([^\`]*)\`$ ]]; then
        return 0
    fi

    # 6. String concatenation / any expression containing quotes
    if [[ "$value" =~ [\"\'] ]]; then
        return 0
    fi

    # 7. A single identifier (variable reference)
    if [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 0
    fi

    # 8. Expression that contains at least one arithmetic operator.
    #    This catches mixed expressions like "a + b", "p*q+2", etc.
    #    NOTE: The hyphen is placed at the start of the bracket expression
    #          to avoid any ambiguity with character ranges.
    if [[ "$value" =~ [-+*/%] ]]; then
        return 0
    fi

    # 9. Parenthesised expression that hasn't been caught above
    #    (e.g. "(a)" or "(123)" where the inner part is simple)
    if [[ "$value" =~ \( ]]; then
        return 0
    fi

    return 1
}

# ----------------------------------------------------------------------
# is_array_type
#   Returns 0 if the value looks like a simple array (all elements
#   are of a simple type) and is NOT a parenthesised arithmetic
#   expression mistakenly written with brackets.
# ----------------------------------------------------------------------
is_array_type() {
    local value="$1"
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Must start with [ and end with ]
    if [[ ! "$value" =~ ^\[.*\]$ ]]; then
        return 1
    fi

    # Content inside the brackets
    local content="${value:1:${#value}-2}"

    # Exclude cases where the content is a plain number or arithmetic
    # expression – those belong to the "simple" category.
    if is_arithmetic_expression "$content" || is_simple_number "$content"; then
        return 1
    fi

    # Trim the inner content
    local array_content="$content"
    array_content=$(echo "$array_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # An empty array is a simple array
    if [ -z "$array_content" ]; then
        return 0
    fi

    # ---- Parse comma-separated elements, respecting nesting ----
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

    # Add the last element (if any)
    if [ -n "$current" ]; then
        elements+=("$current")
    fi

    # Verify every element is a simple type
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
#   Returns 0 if the value looks like a simple object (all property
#   values are of a simple type).
# ----------------------------------------------------------------------
is_object_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Must start with { and end with }
    if [[ ! "$value" =~ ^\{.*\}$ ]]; then
        return 1
    fi

    local object_content="${value:1:${#value}-2}"
    object_content=$(echo "$object_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # An empty object is a simple object
    if [ -z "$object_content" ]; then
        return 0
    fi

    # ---- Parse comma-separated properties ----
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

    # Extract the value part of each property (after the colon) and test it
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
#   Returns 0 if the value is an array or object that contains at
#   least one nested array or object, making it "complex".
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
                    # Nested structure detected
                    if [ $bracket_depth -gt 1 ] || [ $brace_depth -gt 0 ]; then
                        return 0
                    fi
                    ;;
                "]") ((bracket_depth--)) ;;
                "{")
                    ((brace_depth++))
                    # Nested structure detected
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
# NEW: Functions for direct variable-reference assignment
#      (var x = y)
# ============================================================

# Path to the assembly output file (same relative depth as in simple.sh/number.sh)
OUTPUT_FILE="../../build_output.asm"

# Associative array to store types of already declared variables
declare -A VAR_TYPES

# ----------------------------------------------------------------------
# load_existing_variable_types
#   Reads build_output.asm and fills VAR_TYPES with variable name -> type
# ----------------------------------------------------------------------
load_existing_variable_types() {
    VAR_TYPES=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)_type[[:space:]]+dq[[:space:]]+TYPE_([A-Z_]+) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local type_name="${BASH_REMATCH[2]}"
            VAR_TYPES["$var_name"]="$type_name"
        fi
    done < <(grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*_type\s+dq\s+TYPE_[A-Z_]+' "$OUTPUT_FILE" 2>/dev/null || true)
}

# ----------------------------------------------------------------------
# insert_assembly_sections
#   Inserts DATA_SECTION and CODE_SECTION into build_output.asm
#   exactly like number.sh does.
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
#   Called when VAR_VALUE is a single identifier (e.g. "othervariable").
#   Generates assembly that copies the value and type from the source
#   variable to the new variable at runtime.
#   In REASSIGNMENT mode, only generates code (no data section).
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
    # Convert to lowercase for easier handling
    source_type=$(echo "$source_type" | tr '[:upper:]' '[:lower:]')

    local data_section=""
    local code_section=""

    # In reassignment mode, we do not need a data section.
    if [[ "$REASSIGNMENT" != "true" ]]; then
        case "$source_type" in
            float)
                data_section=$'    ; =========================================\n'
                data_section+=$'    ; Variable: '"$new_var"$' (copy of '"$source_var"$')\n'
                data_section+=$'    ; Type: FLOAT (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_float_val dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_FLOAT"$'\n'
                ;;
            number|int|integer)
                data_section=$'    ; =========================================\n'
                data_section+=$'    ; Variable: '"$new_var"$' (copy of '"$source_var"$')\n'
                data_section+=$'    ; Type: NUMBER (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_NUMBER"$'\n'
                ;;
            *)
                local upper_type=$(echo "$source_type" | tr '[:lower:]' '[:upper:]')
                data_section=$'    ; =========================================\n'
                data_section+=$'    ; Variable: '"$new_var"$' (copy of '"$source_var"$')\n'
                data_section+=$'    ; Type: '"$upper_type"$' (copy)\n'
                data_section+=$'    ; =========================================\n'
                data_section+="    ${new_var} dq 0"$'\n'
                data_section+="    ${new_var}_type dq TYPE_${upper_type}"$'\n'
                ;;
        esac
    fi

    # Code section is always generated
    case "$source_type" in
        float)
            code_section=$'    ; Copy float variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}_float_val]"$'\n'
            code_section+="    mov qword [${new_var}_float_val], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
            ;;
        number|int|integer)
            code_section=$'    ; Copy integer variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
            ;;
        *)
            local upper_type=$(echo "$source_type" | tr '[:lower:]' '[:upper:]')
            code_section=$'    ; Copy variable '"$source_var"$' to '"$new_var"$'\n'
            code_section+="    mov rax, qword [${source_var}]"$'\n'
            code_section+="    mov qword [${new_var}], rax"$'\n'
            code_section+="    mov rax, qword [${source_var}_type]"$'\n'
            code_section+="    mov qword [${new_var}_type], rax"$'\n'
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

# ------------------------------------------------------------
# NEW: Check for direct variable reference assignment
#      e.g.  var teste = othervariable
#      Also catches reassignment mode (bare assignment)
# ------------------------------------------------------------
if [[ "$VAR_VALUE" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && \
   [[ "$VAR_VALUE" != "null" && "$VAR_VALUE" != "undefined" && \
      "$VAR_VALUE" != "true" && "$VAR_VALUE" != "false" ]]; then
    handle_variable_reference "$VAR_NAME" "$VAR_VALUE"
    exit 0
fi

# ------------------------------------------------------------
# Original type determination (unchanged)
# ------------------------------------------------------------
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

# Ensure the handler directory exists
mkdir -p "$VAR_TYPES_DIR"

TYPE_HANDLER="$VAR_TYPES_DIR/$TYPE.sh"

if [ ! -f "$TYPE_HANDLER" ]; then
    echo "Error: Type handler not found: $TYPE_HANDLER"
    exit 1
fi

# Pass the REASSIGNMENT flag to the type handler
export REASSIGNMENT="${REASSIGNMENT:-false}"
echo "Executing handler: $TYPE_HANDLER"
bash "$TYPE_HANDLER"
exit $?
