#!/bin/bash

# var.sh - Main handler that analyzes JavaScript var declarations
# and delegates to specific type handlers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VAR_TYPES_DIR="./var_types"

if [ ! -f "var_input" ]; then
    echo "Error: var_input file not found in $(pwd)"
    exit 1
fi

# Read the input (no need to clean js-start/js-end)
INPUT_CONTENT=$(cat var_input | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Extract variable name and value
if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
    # Remove trailing semicolon if present
    VAR_VALUE="${VAR_VALUE%;}"
else
    echo "Error: Invalid variable declaration format"
    exit 1
fi

# Export variables so handlers can access them
export VAR_NAME
export VAR_VALUE

# Function to check if a string looks like a pure arithmetic expression
is_arithmetic_expression() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/[[:space:]]//g')
    
    # Check for parenthesized expressions recursively
    if [[ "$value" =~ \( ]]; then
        # Extract and validate parenthesized groups
        local check_value="$value"
        while [[ "$check_value" =~ \(([^()]+)\) ]]; do
            local inner="${BASH_REMATCH[1]}"
            if ! is_arithmetic_expression "$inner"; then
                return 1
            fi
            # Replace the validated parenthesized expression with a placeholder number
            check_value="${check_value//(${inner})/1}"
        done
        # Now check if the remaining expression with placeholders is valid
        if ! is_arithmetic_expression "$check_value"; then
            return 1
        fi
        return 0
    fi
    
    # Pattern for decimal numbers, integers, hex, octal, binary
    # Allows for: 123, 12.34, .5, 5., 0x1A, 0o77, 0b11, 1e10, 1.5e-3
    local number_pattern='-?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?|-?0[xX][0-9a-fA-F]+|-?0[oO][0-7]+|-?0[bB][01]+'
    
    # Check if the entire expression matches: number (operator number)*
    if [[ "$value" =~ ^${number_pattern}([-+*/%]${number_pattern})*$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to check if string is a simple number
is_simple_number() {
    local str="$1"
    
    # Decimal integer
    if [[ "$str" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi
    
    # Decimal with decimal point
    if [[ "$str" =~ ^-?[0-9]+\.[0-9]*$ ]] || [[ "$str" =~ ^-?\.[0-9]+$ ]] || [[ "$str" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        return 0
    fi
    
    # Scientific notation
    if [[ "$str" =~ ^-?[0-9]+(\.[0-9]*)?[eE][+-]?[0-9]+$ ]]; then
        return 0
    fi
    
    # Hexadecimal
    if [[ "$str" =~ ^-?0[xX][0-9a-fA-F]+$ ]]; then
        return 0
    fi
    
    # Octal (with 0o or 0O prefix)
    if [[ "$str" =~ ^-?0[oO][0-7]+$ ]]; then
        return 0
    fi
    
    # Binary
    if [[ "$str" =~ ^-?0[bB][01]+$ ]]; then
        return 0
    fi
    
    # Legacy octal (leading 0, but not 0x, 0o, 0b)
    if [[ "$str" =~ ^-?0[0-7]+$ ]] && [[ ! "$str" =~ ^-?0[xXoObB] ]]; then
        return 0
    fi
    
    return 1
}

# Function to check if content is a simple type
is_simple_type() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check for arithmetic expressions first (includes decimals and parentheses)
    if is_arithmetic_expression "$value"; then
        return 0
    fi
    
    # Check for null/undefined
    if [ "$value" = "null" ] || [ "$value" = "undefined" ]; then
        return 0
    fi
    
    # Check for boolean
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
        return 0
    fi
    
    # Check for simple number
    if is_simple_number "$value"; then
        return 0
    fi
    
    # Check for string (with any quotes)
    if [[ "$value" =~ ^\"([^\"]*)\"$ ]] || [[ "$value" =~ ^\'([^\']*)\'$ ]] || [[ "$value" =~ ^\`([^\`]*)\`$ ]]; then
        return 0
    fi
    
    # Check for string concatenation with quotes
    if [[ "$value" =~ [\"\'] ]]; then
        # Contains quotes anywhere, treat as string expression
        return 0
    fi
    
    # Check for reference to another variable (simple identifier)
    if [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 0
    fi
    
    # Check for expressions with variables (e.g., a + b, a * 2.5)
    if [[ "$value" =~ [+\-*/%] ]]; then
        # Contains operators but no quotes, could be mixed variable/numbers
        # For now, treat as simple (will be handled by the simple.sh type detector)
        return 0
    fi
    
    # Check for parenthesized expressions with variables
    if [[ "$value" =~ \( ]]; then
        return 0
    fi
    
    return 1
}

# Function to check if content is an array
is_array_type() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Must start with [ and end with ]
    if [[ ! "$value" =~ ^\[.*\]$ ]]; then
        return 1
    fi
    
    # Get content inside brackets
    local content="${value:1:${#value}-2}"
    
    # Check for arithmetic expressions in brackets (they're not arrays)
    if is_arithmetic_expression "$content" || is_simple_number "$content"; then
        # This is just a number/expression in brackets, treat as simple
        return 1
    fi
    
    # Get content inside brackets for array processing
    local array_content="${value:1:${#value}-2}"
    array_content=$(echo "$array_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # If empty array, it's simple array
    if [ -z "$array_content" ]; then
        return 0
    fi
    
    # Parse array elements
    local elements=()
    local current=""
    local bracket_depth=0
    local brace_depth=0
    local parenthese_depth=0
    local in_string=false
    local string_char=""
    
    for (( index=0; index<${#array_content}; index++ )); do
        local char="${array_content:$index:1}"
        local prev_char=""
        [ $index -gt 0 ] && prev_char="${array_content:$((index-1)):1}"
        
        if [ "$in_string" = false ]; then
            case "$char" in
                "[") ((bracket_depth++)) ;;
                "]") ((bracket_depth--)) ;;
                "{") ((brace_depth++)) ;;
                "}") ((brace_depth--)) ;;
                "(") ((parenthese_depth++)) ;;
                ")") ((parenthese_depth--)) ;;
                '"' | "'" | "\`")
                    in_string=true
                    string_char="$char"
                    ;;
            esac
            
            if [ "$char" = "," ] && [ $bracket_depth -eq 0 ] && [ $brace_depth -eq 0 ] && [ $parenthese_depth -eq 0 ]; then
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
    
    # Add the last element if not empty
    if [ -n "$current" ]; then
        elements+=("$current")
    fi
    
    # Check each element for simple type
    for element in "${elements[@]}"; do
        element=$(echo "$element" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if ! is_simple_type "$element"; then
            return 1
        fi
    done
    
    return 0
}

# Function to check if content is an object
is_object_type() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Must start with { and end with }
    if [[ ! "$value" =~ ^\{.*\}$ ]]; then
        return 1
    fi
    
    # Get content inside braces
    local object_content="${value:1:${#value}-2}"
    object_content=$(echo "$object_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # If empty object, it's simple object
    if [ -z "$object_content" ]; then
        return 0
    fi
    
    # Parse object properties
    local properties=()
    local current=""
    local bracket_depth=0
    local brace_depth=0
    local parenthese_depth=0
    local in_string=false
    local string_char=""
    
    for (( index=0; index<${#object_content}; index++ )); do
        local char="${object_content:$index:1}"
        local prev_char=""
        [ $index -gt 0 ] && prev_char="${object_content:$((index-1)):1}"
        
        if [ "$in_string" = false ]; then
            case "$char" in
                "[") ((bracket_depth++)) ;;
                "]") ((bracket_depth--)) ;;
                "{") ((brace_depth++)) ;;
                "}") ((brace_depth--)) ;;
                "(") ((parenthese_depth++)) ;;
                ")") ((parenthese_depth--)) ;;
                '"' | "'" | "\`")
                    in_string=true
                    string_char="$char"
                    ;;
            esac
            
            if [ "$char" = "," ] && [ $bracket_depth -eq 0 ] && [ $brace_depth -eq 0 ] && [ $parenthese_depth -eq 0 ]; then
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
    
    # Add the last property if not empty
    if [ -n "$current" ]; then
        properties+=("$current")
    fi
    
    # Check each property value for simple type
    for prop in "${properties[@]}"; do
        prop=$(echo "$prop" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Extract value part (after colon)
        if [[ "$prop" =~ ^[^:]*:[[:space:]]*(.*)$ ]]; then
            local prop_value="${BASH_REMATCH[1]}"
            prop_value=$(echo "$prop_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if ! is_simple_type "$prop_value"; then
                return 1
            fi
        fi
    done
    
    return 0
}

# Function to check if content is complex (mixed arrays and objects)
is_complex_type() {
    local value="$1"
    
    # Trim whitespace
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Must start with [ or { and end with ] or }
    if [[ ! "$value" =~ ^[\[\{].*[\]\}]$ ]]; then
        return 1
    fi
    
    # Check for nested structures
    local bracket_depth=0
    local brace_depth=0
    local in_string=false
    local string_char=""
    
    for (( index=0; index<${#value}; index++ )); do
        local char="${value:$index:1}"
        local prev_char=""
        [ $index -gt 0 ] && prev_char="${value:$((index-1)):1}"
        
        if [ "$in_string" = false ]; then
            case "$char" in
                "[") 
                    ((bracket_depth++))
                    # If we have nested brackets/braces beyond the first level, it's complex
                    if [ $bracket_depth -gt 1 ] || [ $brace_depth -gt 0 ]; then
                        return 0
                    fi
                    ;;
                "]") ((bracket_depth--)) ;;
                "{") 
                    ((brace_depth++))
                    # If we have nested brackets/braces beyond the first level, it's complex
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

# Determine the type of the variable
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

# Create var_types directory if it doesn't exist
mkdir -p "$VAR_TYPES_DIR"

# Check if the type handler exists
TYPE_HANDLER="$VAR_TYPES_DIR/$TYPE.sh"

if [ ! -f "$TYPE_HANDLER" ]; then
    echo "Error: Type handler not found: $TYPE_HANDLER"
    exit 1
fi

# Execute the appropriate handler
echo "Executing handler: $TYPE_HANDLER"
bash "$TYPE_HANDLER"

# Exit with the same code as the handler
exit $?