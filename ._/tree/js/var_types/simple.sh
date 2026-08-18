#!/bin/bash

# simple.sh - Handler for JavaScript var declarations
# Determines the type and calls the appropriate script
# Supports REASSIGNMENT mode (bare assignment) by passing the flag along.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_FILE="../../../build_output.asm"
INPUT_FILE="../var_input"

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
    echo "Expected format: var variableName = value"
    exit 1
fi

VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# ----------------------------------------------------------------------
#  determine_type
# ----------------------------------------------------------------------
determine_type() {
    local value="$1"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$value" = "null" ]; then
        echo "null"
        return
    fi
    if [ "$value" = "undefined" ]; then
        echo "undefined"
        return
    fi
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        echo "boolean"
        return
    fi
    if [[ "$value" =~ [\"\'\`] ]]; then
        echo "string"
        return
    fi
    if [[ "$value" =~ [+*/%()-] ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?[0-9]+\.[0-9]*$ ]] || \
       [[ "$value" =~ ^-?\.[0-9]+$ ]] || \
       [[ "$value" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]*)?[eE][+-]?[0-9]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?0[xX][0-9a-fA-F]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?0[oO][0-7]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?0[bB][01]+$ ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^-?0[0-7]+$ ]] && [[ ! "$value" =~ ^-?0[xXoObB] ]]; then
        echo "number"
        return
    fi
    if [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "reference"
        return
    fi
    echo "string"
}

TYPE=$(determine_type "$VAR_VALUE")

echo "Variable: $VAR_NAME = $VAR_VALUE"
echo "Detected type: $TYPE"

if [ ! -d "./simple" ]; then
    echo "Error: ./simple directory not found"
    exit 1
fi

export REASSIGNMENT="${REASSIGNMENT:-false}"

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
