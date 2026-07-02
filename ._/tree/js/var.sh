#!/bin/bash

# ============================================================
# var.sh - Main handler that analyzes JavaScript var declarations
# and delegates to specific type handlers.
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
# ------------------------------------------------------------
if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
    # Remove an optional trailing semicolon
    VAR_VALUE="${VAR_VALUE%;}"
else
    echo "Error: Invalid variable declaration format"
    exit 1
fi

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
# Main type determination logic
# ============================================================
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

echo "Executing handler: $TYPE_HANDLER"
bash "$TYPE_HANDLER"
exit $?