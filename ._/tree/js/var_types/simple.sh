#!/bin/bash

# simple.sh - Handler for JavaScript var declarations
# Determines the type and calls the appropriate script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_FILE="../../../build_output.asm"
INPUT_FILE="../var_input"

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

# ----------------------------------------------------------------------
#  is_arithmetic_expression
#  (retained for any possible future use, but no longer called in type
#   detection – the new logic handles all cases directly and robustly)
# ----------------------------------------------------------------------
is_arithmetic_expression() {
    local value="$1"
    # Remove all whitespace
    local clean_value=$(echo "$value" | sed 's/[[:space:]]//g')
    
    # Handle parenthesized expressions recursively
    if [[ "$clean_value" =~ \( ]]; then
        local check_value="$clean_value"
        while [[ "$check_value" =~ \(([^()]+)\) ]]; do
            local inner="${BASH_REMATCH[1]}"
            if ! is_arithmetic_expression "$inner"; then
                return 1
            fi
            # Replace the validated parenthesized expression with a placeholder
            check_value="${check_value//(${inner})/1}"
        done
        # Check the remaining expression with placeholders
        if ! is_arithmetic_expression "$check_value"; then
            return 1
        fi
        return 0
    fi
    
    # Pattern for numbers: decimal, float, scientific notation, hex, octal, binary
    local number_pattern='-?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?|-?0[xX][0-9a-fA-F]+|-?0[oO][0-7]+|-?0[bB][01]+'
    
    # Check if the expression is number (operator number)*
    if [[ "$clean_value" =~ ^${number_pattern}([-+*/%]${number_pattern})*$ ]]; then
        return 0
    fi
    
    return 1
}

# ----------------------------------------------------------------------
#  determine_type
#  (rewritten logic – more robust detection of number expressions)
# ----------------------------------------------------------------------
determine_type() {
    local value="$1"
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 1. Check for null / undefined
    if [ "$value" = "null" ]; then
        echo "null"
        return
    fi
    if [ "$value" = "undefined" ]; then
        echo "undefined"
        return
    fi
    
    # 2. Check for boolean
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        echo "boolean"
        return
    fi
    
    # 3. If it contains any quotes, it's definitely a string
    if [[ "$value" =~ [\"\'\`] ]]; then
        echo "string"
        return
    fi
    
    # 4. Check for arithmetic expressions of any kind
    #    Any value that contains an arithmetic operator or parentheses
    #    is treated as a numeric expression (variables + numbers allowed).
    #    This catches complex cases like: 2+(a+b)*(c-15)/2
    #    and all previously working numeric expressions.
    if [[ "$value" =~ [+*/%()-] ]]; then
        echo "number"
        return
    fi
    
    # 5. Check for pure numbers (all formats) without operators
    # Decimal integer
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "number"
        return
    fi
    
    # Decimal with decimal point (various formats)
    if [[ "$value" =~ ^-?[0-9]+\.[0-9]*$ ]] || \
       [[ "$value" =~ ^-?\.[0-9]+$ ]] || \
       [[ "$value" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        echo "number"
        return
    fi
    
    # Scientific notation
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]*)?[eE][+-]?[0-9]+$ ]]; then
        echo "number"
        return
    fi
    
    # Hex: 0x... or 0X...
    if [[ "$value" =~ ^-?0[xX][0-9a-fA-F]+$ ]]; then
        echo "number"
        return
    fi
    
    # Octal: 0o... or 0O... (modern JavaScript octal)
    if [[ "$value" =~ ^-?0[oO][0-7]+$ ]]; then
        echo "number"
        return
    fi
    
    # Binary: 0b... or 0B...
    if [[ "$value" =~ ^-?0[bB][01]+$ ]]; then
        echo "number"
        return
    fi
    
    # Legacy octal: 0... (but not 0x, 0o, 0b)
    if [[ "$value" =~ ^-?0[0-7]+$ ]] && [[ ! "$value" =~ ^-?0[xXoObB] ]]; then
        echo "number"
        return
    fi
    
    # 6. Check for variable reference (single identifier)
    if [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "reference"
        return
    fi
    
    # 7. Default to string
    echo "string"
}

# Determine the type of the value
TYPE=$(determine_type "$VAR_VALUE")

echo "Variable: $VAR_NAME = $VAR_VALUE"
echo "Detected type: $TYPE"

# Check if the simple directory exists
if [ ! -d "./simple" ]; then
    echo "Error: ./simple directory not found"
    exit 1
fi

# Call the appropriate script based on type
case "$TYPE" in
    "string")
        if [ -f "./simple/string.sh" ]; then
            bash "./simple/string.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed string variable"
                exit 0
            else
                echo "Error: string.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: string.sh not found in ./simple/"
            exit 1
        fi
        ;;
    "number")
        if [ -f "./simple/number.sh" ]; then
            bash "./simple/number.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed number variable"
                exit 0
            else
                echo "Error: number.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: number.sh not found in ./simple/"
            exit 1
        fi
        ;;
    "boolean")
        if [ -f "./simple/boolean.sh" ]; then
            bash "./simple/boolean.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed boolean variable"
                exit 0
            else
                echo "Error: boolean.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: boolean.sh not found in ./simple/"
            exit 1
        fi
        ;;
    "null")
        if [ -f "./simple/null.sh" ]; then
            bash "./simple/null.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed null variable"
                exit 0
            else
                echo "Error: null.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: null.sh not found in ./simple/"
            exit 1
        fi
        ;;
    "undefined")
        if [ -f "./simple/undefined.sh" ]; then
            bash "./simple/undefined.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed undefined variable"
                exit 0
            else
                echo "Error: undefined.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: undefined.sh not found in ./simple/"
            exit 1
        fi
        ;;
    "reference")
        if [ -f "./simple/reference.sh" ]; then
            bash "./simple/reference.sh"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "Successfully processed reference variable"
                exit 0
            else
                echo "Error: reference.sh failed with exit code $EXIT_CODE"
                exit $EXIT_CODE
            fi
        else
            echo "Error: reference.sh not found in ./simple/"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unknown type '$TYPE'"
        exit 1
        ;;
esac