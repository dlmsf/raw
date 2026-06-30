#!/bin/bash

# number.sh - Converts JavaScript number declarations to NASM assembly code
# Rewritten to support variables in expressions. All evaluation happens at assembly runtime.
# Variables from previous declarations are recognized and loaded appropriately.

set -x  # Debug: show commands being executed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SCRIPT_DIR/simple"

OUTPUT_FILE="../../../../build_output.asm"
INPUT_FILE="../../var_input"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
fi

# Read and clean the input
INPUT_CONTENT=$(cat "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
INPUT_CONTENT="${INPUT_CONTENT%;}"

echo "DEBUG: INPUT_CONTENT='$INPUT_CONTENT'" >&2

# Extract variable name and value
if [[ "$INPUT_CONTENT" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    VAR_NAME="${BASH_REMATCH[1]}"
    VAR_VALUE="${BASH_REMATCH[2]}"
    VAR_VALUE=$(echo "$VAR_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
else
    echo "Error: Invalid variable declaration format"
    exit 1
fi

echo "DEBUG: VAR_NAME='$VAR_NAME', VAR_VALUE='$VAR_VALUE'" >&2

# ----------------------------------------------------------------------
# Load existing variable types from build_output.asm
# ----------------------------------------------------------------------
declare -A VAR_TYPE

load_variable_types() {
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)_type[[:space:]]+dq[[:space:]]+TYPE_FLOAT ]]; then
            VAR_TYPE["${BASH_REMATCH[1]}"]="float"
        elif [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)_type[[:space:]]+dq[[:space:]]+TYPE_NUMBER ]]; then
            VAR_TYPE["${BASH_REMATCH[1]}"]="int"
        fi
    done < <(grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*_type\s+dq\s+TYPE_(FLOAT|NUMBER)' "$OUTPUT_FILE" 2>/dev/null || true)
}

load_variable_types

# ----------------------------------------------------------------------
# Tokenizer - handles integers, floats, variables, and parentheses
# ----------------------------------------------------------------------
tokenize() {
    local expr="$1"
    local tokens=()
    local i=0
    local len=${#expr}
    
    while [ $i -lt $len ]; do
        local c="${expr:$i:1}"
        
        # Skip whitespace
        if [[ "$c" =~ [[:space:]] ]]; then
            i=$((i+1))
            continue
        fi
        
        # Number (integer or float)
        if [[ "$c" =~ [0-9] ]] || [[ "$c" == "." ]]; then
            local num="$c"
            i=$((i+1))
            local has_dot=false
            [[ "$c" == "." ]] && has_dot=true
            
            while [ $i -lt $len ]; do
                local nc="${expr:$i:1}"
                if [[ "$nc" =~ [0-9] ]]; then
                    num="${num}${nc}"
                    i=$((i+1))
                elif [[ "$nc" == "." ]] && [ "$has_dot" = false ]; then
                    num="${num}${nc}"
                    has_dot=true
                    i=$((i+1))
                elif [[ "$nc" =~ [eE] ]]; then
                    num="${num}${nc}"
                    i=$((i+1))
                    if [ $i -lt $len ]; then
                        local sign="${expr:$i:1}"
                        if [[ "$sign" =~ [\+\-] ]]; then
                            num="${num}${sign}"
                            i=$((i+1))
                        fi
                    fi
                else
                    break
                fi
            done
            
            if [[ "$num" =~ \. ]] || [[ "$num" =~ [eE] ]]; then
                tokens+=("FLOAT:$num")
            else
                tokens+=("INT:$num")
            fi
            continue
        fi
        
        # Variable / identifier
        if [[ "$c" =~ [a-zA-Z_] ]]; then
            local name="$c"
            i=$((i+1))
            while [ $i -lt $len ]; do
                local nc="${expr:$i:1}"
                if [[ "$nc" =~ [a-zA-Z0-9_] ]]; then
                    name="${name}${nc}"
                    i=$((i+1))
                else
                    break
                fi
            done
            # Disallow reserved words that might appear in expressions
            case "$name" in
                var|let|const|if|else|while|for|function|return)
                    echo "Error: Unexpected keyword '$name' in expression" >&2
                    exit 1
                    ;;
            esac
            tokens+=("VAR:$name")
            continue
        fi
        
        # Operators and parentheses
        case "$c" in
            '+'|'-'|'*'|'/'|'%'|'('|')')
                tokens+=("OP:$c")
                i=$((i+1))
                ;;
            *)
                echo "Error: Unexpected character '$c'" >&2
                exit 1
                ;;
        esac
    done
    
    printf '%s\n' "${tokens[@]}"
}

# ----------------------------------------------------------------------
# Shunting-yard algorithm - infix to postfix (RPN)
# ----------------------------------------------------------------------
precedence() {
    case "$1" in
        '+'|'-') echo 1 ;;
        '*'|'/'|'%') echo 2 ;;
        *) echo 0 ;;
    esac
}

to_rpn() {
    local tokens=("$@")
    local output=()
    local stack=()
    
    for token in "${tokens[@]}"; do
        local type="${token%%:*}"
        local val="${token#*:}"
        
        if [ "$type" = "INT" ] || [ "$type" = "FLOAT" ] || [ "$type" = "VAR" ]; then
            output+=("$token")
        elif [ "$type" = "OP" ]; then
            case "$val" in
                '(')
                    stack+=("$token")
                    ;;
                ')')
                    while [ ${#stack[@]} -gt 0 ] && [ "${stack[-1]#*:}" != "(" ]; do
                        output+=("${stack[-1]}")
                        unset 'stack[-1]'
                    done
                    [ ${#stack[@]} -gt 0 ] && unset 'stack[-1]'
                    ;;
                *)
                    local prec=$(precedence "$val")
                    while [ ${#stack[@]} -gt 0 ]; do
                        local top="${stack[-1]}"
                        local top_op="${top#*:}"
                        [ "$top_op" = "(" ] && break
                        local top_prec=$(precedence "$top_op")
                        [ $top_prec -lt $prec ] && break
                        output+=("$top")
                        unset 'stack[-1]'
                    done
                    stack+=("$token")
                    ;;
            esac
        fi
    done
    
    while [ ${#stack[@]} -gt 0 ]; do
        output+=("${stack[-1]}")
        unset 'stack[-1]'
    done
    
    printf '%s\n' "${output[@]}"
}

# ----------------------------------------------------------------------
# Determine if expression must be evaluated as float
# ----------------------------------------------------------------------
is_float_expression() {
    local tokens=("$@")
    for token in "${tokens[@]}"; do
        local type="${token%%:*}"
        local val="${token#*:}"
        if [ "$type" = "FLOAT" ]; then return 0; fi
        if [ "$type" = "OP" ] && [ "$val" = "/" ]; then return 0; fi
        if [ "$type" = "VAR" ]; then
            local vtype="${VAR_TYPE[$val]}"
            if [ "$vtype" = "float" ]; then return 0; fi
            if [ -z "$vtype" ]; then
                echo "Error: Variable '$val' used before declaration" >&2
                exit 1
            fi
        fi
    done
    return 1
}

# ----------------------------------------------------------------------
# Generate assembly code from RPN tokens (handles variables)
# ----------------------------------------------------------------------
generate_full_asm() {
    local use_float=$1
    shift
    local rpn_tokens=("$@")
    local const_idx=0
    
    # Data section
    echo "    ; ========================================="
    echo "    ; Variable: $VAR_NAME"
    echo "    ; Expression: $VAR_VALUE"
    
    if [ "$use_float" = true ]; then
        echo "    ; Type: FLOAT (runtime evaluated)"
        echo "    ; ========================================="
        for token in "${rpn_tokens[@]}"; do
            if [[ "$token" == FLOAT:* ]]; then
                local val="${token#*:}"
                echo "    ${VAR_NAME}_float${const_idx} dd ${val}"
                echo "    ${VAR_NAME}_float${const_idx}_type dq TYPE_FLOAT"
                const_idx=$((const_idx+1))
            fi
        done
        echo "    ${VAR_NAME}_float_val dq 0    ; Storage for float result"
        echo "    ${VAR_NAME}_str times 32 db 0    ; Per-variable string buffer"
        echo "    ${VAR_NAME} dq ${VAR_NAME}_str    ; Pointer for printing"
        echo "    ${VAR_NAME}_type dq TYPE_FLOAT    ; RUNTIME TYPE TAG"
    else
        echo "    ; Type: INTEGER (runtime evaluated)"
        echo "    ; ========================================="
        echo "    ${VAR_NAME} dq 0    ; Storage for integer result"
        echo "    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"
    fi
    
    echo ""
    echo "DATA_CODE_SEPARATOR"
    echo ""
    
    # Code section
    echo "    ; ========================================="
    echo "    ; Runtime evaluation of: $VAR_VALUE"
    echo "    ; Variable: $VAR_NAME"
    if [ "$use_float" = true ]; then
        echo "    ; Type: FLOAT (using x87 FPU)"
    else
        echo "    ; Type: INTEGER"
    fi
    echo "    ; ========================================="
    
    const_idx=0
    for token in "${rpn_tokens[@]}"; do
        local type="${token%%:*}"
        local val="${token#*:}"
        
        if [ "$type" = "INT" ]; then
            if [ "$use_float" = true ]; then
                echo "    ; Push integer $val and convert to float"
                echo "    push $val"
                echo "    fild qword [rsp]"
                echo "    add rsp, 8"
            else
                echo "    ; Push integer $val"
                echo "    push $val"
            fi
        elif [ "$type" = "FLOAT" ]; then
            echo "    ; Load float constant ${VAR_NAME}_float${const_idx}"
            echo "    fld dword [${VAR_NAME}_float${const_idx}]"
            const_idx=$((const_idx+1))
        elif [ "$type" = "VAR" ]; then
            local var="$val"
            local vtype="${VAR_TYPE[$var]}"
            if [ -z "$vtype" ]; then
                echo "Error: Variable '$var' not defined" >&2
                exit 1
            fi
            if [ "$use_float" = true ]; then
                if [ "$vtype" = "float" ]; then
                    echo "    ; Load float variable $var"
                    echo "    fld qword [${var}_float_val]"
                else
                    echo "    ; Load integer variable $var and convert to float"
                    echo "    fild qword [${var}]"
                fi
            else
                if [ "$vtype" != "int" ]; then
                    echo "Error: Variable '$var' is not an integer (cannot mix types in integer expression)" >&2
                    exit 1
                fi
                echo "    ; Push integer variable $var"
                echo "    push qword [${var}]"
            fi
        elif [ "$type" = "OP" ]; then
            if [ "$use_float" = true ]; then
                case "$val" in
                    '+') echo "    ; Float addition"
                         echo "    faddp st1, st0" ;;
                    '-') echo "    ; Float subtraction"
                         echo "    fsubp st1, st0" ;;
                    '*') echo "    ; Float multiplication"
                         echo "    fmulp st1, st0" ;;
                    '/') echo "    ; Float division"
                         echo "    fdivp st1, st0" ;;
                    '%') echo "    ; Float modulo"
                         echo "    fprem"
                         echo "    fstp st1" ;;
                esac
            else
                case "$val" in
                    '+') echo "    ; Integer addition"
                         echo "    pop rbx"
                         echo "    pop rax"
                         echo "    add rax, rbx"
                         echo "    push rax" ;;
                    '-') echo "    ; Integer subtraction"
                         echo "    pop rbx"
                         echo "    pop rax"
                         echo "    sub rax, rbx"
                         echo "    push rax" ;;
                    '*') echo "    ; Integer multiplication"
                         echo "    pop rbx"
                         echo "    pop rax"
                         echo "    imul rbx"
                         echo "    push rax" ;;
                    '/') echo "    ; Integer division"
                         echo "    xor rdx, rdx"
                         echo "    pop rbx"
                         echo "    pop rax"
                         echo "    idiv rbx"
                         echo "    push rax" ;;
                    '%') echo "    ; Integer modulo"
                         echo "    xor rdx, rdx"
                         echo "    pop rbx"
                         echo "    pop rax"
                         echo "    idiv rbx"
                         echo "    push rdx" ;;
                esac
            fi
        fi
    done
    
    echo ""
    echo "    ; Store result in variable with type tag"
    if [ "$use_float" = true ]; then
        echo "    ; Store float result"
        echo "    sub rsp, 8"
        echo "    fstp qword [rsp]"
        echo "    movsd xmm0, [rsp]"
        echo "    add rsp, 8"
        echo "    movsd [${VAR_NAME}_float_val], xmm0"
        echo "    mov rdi, ${VAR_NAME}_str    ; output buffer"
        echo "    movsd xmm0, [${VAR_NAME}_float_val]"
        echo "    call float_to_str"
        echo "    mov qword [${VAR_NAME}], ${VAR_NAME}_str    ; Store pointer to string"
        echo "    mov qword [${VAR_NAME}_type], TYPE_FLOAT    ; Set runtime type tag"
    else
        echo "    ; Store integer result"
        echo "    pop rax"
        echo "    mov [${VAR_NAME}], rax"
        echo "    mov qword [${VAR_NAME}_type], TYPE_NUMBER    ; Set runtime type tag"
    fi
}

# ----------------------------------------------------------------------
# Main logic
# ----------------------------------------------------------------------
DATA_SECTION=""
CODE_SECTION=""
IS_FLOAT=false
FULL_OUTPUT=""

# 1) Handle hex/binary/octal literals directly (they are always integer)
if [[ "$VAR_VALUE" =~ ^-?0[xX][0-9a-fA-F]+$ ]] || \
   [[ "$VAR_VALUE" =~ ^-?0[bB][01]+$ ]] || \
   [[ "$VAR_VALUE" =~ ^-?0[0-7]+$ ]]; then
    echo "DEBUG: Non-decimal literal detected" >&2
    DATA_SECTION="    ; ========================================="$'\n'
    DATA_SECTION+="    ; Variable: $VAR_NAME = $VAR_VALUE"$'\n'
    DATA_SECTION+="    ; Type: INTEGER (literal)"$'\n'
    DATA_SECTION+="    ; ========================================="$'\n'
    DATA_SECTION+="    ${VAR_NAME} dq $VAR_VALUE"$'\n'
    DATA_SECTION+="    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"

# 2) Tokenize and decide
else
    mapfile -t tokens < <(tokenize "$VAR_VALUE")
    echo "DEBUG: Tokens: ${tokens[*]}" >&2

    # Single literal (int/float)
    if [ ${#tokens[@]} -eq 1 ]; then
        token="${tokens[0]}"
        ttype="${token%%:*}"
        tval="${token#*:}"
        if [ "$ttype" = "FLOAT" ]; then
            echo "DEBUG: Float literal detected" >&2
            IS_FLOAT=true
            FLOAT_VAL=$(printf "%.10f" "$tval" 2>/dev/null | sed 's/\.0*$//' || echo "$tval")
            DATA_SECTION="    ; ========================================="$'\n'
            DATA_SECTION+="    ; Variable: $VAR_NAME = $tval"$'\n'
            DATA_SECTION+="    ; Type: FLOAT (literal)"$'\n'
            DATA_SECTION+="    ; ========================================="$'\n'
            DATA_SECTION+="    ${VAR_NAME}_float_val dq 0    ; Storage for float value"$'\n'
            DATA_SECTION+="    ${VAR_NAME}_float dd $FLOAT_VAL    ; The actual float constant"$'\n'
            DATA_SECTION+="    ${VAR_NAME}_float_str db '$FLOAT_VAL', 0    ; String representation"$'\n'
            DATA_SECTION+="    ${VAR_NAME} dq ${VAR_NAME}_float_str    ; Pointer for printing"$'\n'
            DATA_SECTION+="    ${VAR_NAME}_type dq TYPE_FLOAT    ; RUNTIME TYPE TAG"$'\n'
            CODE_SECTION="    ; Initialize float value at runtime"$'\n'
            CODE_SECTION+="    fld dword [${VAR_NAME}_float]"$'\n'
            CODE_SECTION+="    fstp qword [${VAR_NAME}_float_val]"
        elif [ "$ttype" = "INT" ]; then
            echo "DEBUG: Integer literal detected" >&2
            DATA_SECTION="    ; ========================================="$'\n'
            DATA_SECTION+="    ; Variable: $VAR_NAME = $tval"$'\n'
            DATA_SECTION+="    ; Type: INTEGER (literal)"$'\n'
            DATA_SECTION+="    ; ========================================="$'\n'
            DATA_SECTION+="    ${VAR_NAME} dq $tval"$'\n'
            DATA_SECTION+="    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"
        else
            # Single variable (assignment)
            echo "DEBUG: Assignment from variable '$tval'" >&2
            # Fall through to expression handling
            EXPRESSION=true
        fi
    fi

    # If not a simple literal, treat as expression
    if [ -z "$DATA_SECTION" ]; then
        echo "DEBUG: Expression detected, generating runtime evaluation" >&2
        mapfile -t rpn_tokens < <(to_rpn "${tokens[@]}")
        echo "DEBUG: RPN: ${rpn_tokens[*]}" >&2

        if is_float_expression "${tokens[@]}"; then
            IS_FLOAT=true
            FULL_OUTPUT=$(generate_full_asm true "${rpn_tokens[@]}")
        else
            IS_FLOAT=false
            FULL_OUTPUT=$(generate_full_asm false "${rpn_tokens[@]}")
        fi

        # Split at separator
        DATA_SECTION=$(echo "$FULL_OUTPUT" | sed -n '1,/DATA_CODE_SEPARATOR/p' | head -n -1)
        CODE_SECTION=$(echo "$FULL_OUTPUT" | sed -n '/DATA_CODE_SEPARATOR/,$p' | tail -n +2)
    fi
fi

# ----------------------------------------------------------------------
# Insert into build_output.asm
# ----------------------------------------------------------------------
echo "DEBUG: Inserting data section and code section into $OUTPUT_FILE" >&2

TEMP_FILE=$(mktemp)
IN_DATA=0
IN_START=0
DATA_DONE=0
CODE_DONE=0

while IFS= read -r line; do
    if [[ "$line" == "section .data" ]]; then
        IN_DATA=1
    elif [[ "$line" == section* ]] && [ "$IN_DATA" -eq 1 ]; then
        if [ "$DATA_DONE" -eq 0 ] && [ -n "$DATA_SECTION" ]; then
            echo "$DATA_SECTION" >> "$TEMP_FILE"
            DATA_DONE=1
        fi
        IN_DATA=0
    fi

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

if [ "$IN_DATA" -eq 1 ] && [ "$DATA_DONE" -eq 0 ] && [ -n "$DATA_SECTION" ]; then
    echo "$DATA_SECTION" >> "$TEMP_FILE"
fi

if [ "$CODE_DONE" -eq 0 ] && [ -n "$CODE_SECTION" ]; then
    echo "$CODE_SECTION" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$OUTPUT_FILE"

# Final status
if [ "$IS_FLOAT" = true ]; then
    echo "✓ Successfully added float variable: $VAR_NAME = $VAR_VALUE"
    echo "  - Runtime type tag: TYPE_FLOAT"
    echo "  - All calculations performed at assembly runtime"
else
    echo "✓ Successfully added integer variable: $VAR_NAME = $VAR_VALUE"
    echo "  - Runtime type tag: TYPE_NUMBER"
    if [ -n "$rpn_tokens" ]; then
        echo "  - Expression evaluated at assembly runtime"
    else
        echo "  - Literal value stored directly"
    fi
fi

echo "  - Variable accessible via: mov rax, [$VAR_NAME]"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0