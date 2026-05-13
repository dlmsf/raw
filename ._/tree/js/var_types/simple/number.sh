#!/bin/bash

# number.sh - Converts JavaScript number declarations to NASM assembly code
# Generates runtime evaluation code for expressions including floats.
# ALL type information is embedded as runtime _type tags

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
# Detect if expression contains any operators
# ----------------------------------------------------------------------
has_operators() {
    local expr="$1"
    if [[ "$expr" =~ [+*/().%-] ]]; then
        return 0
    else
        return 1
    fi
}

# ----------------------------------------------------------------------
# Detect if expression needs float
# ----------------------------------------------------------------------
contains_float() {
    local expr="$1"
    if [[ "$expr" =~ [0-9]*\.[0-9]+ ]] || [[ "$expr" =~ [0-9]+[eE][-+]?[0-9]+ ]] || [[ "$expr" =~ / ]]; then
        return 0
    else
        return 1
    fi
}

# ----------------------------------------------------------------------
# Tokenizer - handles integers AND floats
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
        
        if [ "$type" = "INT" ] || [ "$type" = "FLOAT" ]; then
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
# Generate float constant declarations with type tags
# ----------------------------------------------------------------------
generate_float_constants() {
    local tokens=("$@")
    local idx=0
    local result=""
    for token in "${tokens[@]}"; do
        if [[ "$token" == FLOAT:* ]]; then
            local val="${token#*:}"
            result="${result}    ${VAR_NAME}_float${idx} dd ${val}"$'\n'
            result="${result}    ${VAR_NAME}_float${idx}_type dq TYPE_FLOAT"$'\n'
            idx=$((idx+1))
        fi
    done
    echo "$result"
}

# ----------------------------------------------------------------------
# Generate assembly code from RPN tokens (ALL RUNTIME EXECUTION)
# ----------------------------------------------------------------------
generate_asm_code() {
    local use_float=$1
    shift
    local rpn_tokens=("$@")
    local code=""
    local const_idx=0
    
    code="${code}    ; ========================================="$'\n'
    code="${code}    ; Runtime evaluation of: $VAR_VALUE"$'\n'
    code="${code}    ; Variable: $VAR_NAME"$'\n'
    
    if [ "$use_float" = true ]; then
        code="${code}    ; Type: FLOAT (using x87 FPU)"$'\n'
    else
        code="${code}    ; Type: INTEGER"$'\n'
    fi
    code="${code}    ; ========================================="$'\n'
    
    for token in "${rpn_tokens[@]}"; do
        local type="${token%%:*}"
        local val="${token#*:}"
        
        if [ "$type" = "INT" ]; then
            if [ "$use_float" = true ]; then
                code="${code}    push $val"$'\n'
                code="${code}    fild qword [rsp]"$'\n'
                code="${code}    add rsp, 8"$'\n'
            else
                code="${code}    push $val"$'\n'
            fi
            
        elif [ "$type" = "FLOAT" ]; then
            local label="${VAR_NAME}_float${const_idx}"
            code="${code}    fld dword [${label}]"$'\n'
            const_idx=$((const_idx+1))
            
        elif [ "$type" = "OP" ]; then
            if [ "$use_float" = true ]; then
                case "$val" in
                    '+') code="${code}    faddp st1, st0"$'\n' ;;
                    '-') code="${code}    fsubp st1, st0"$'\n' ;;
                    '*') code="${code}    fmulp st1, st0"$'\n' ;;
                    '/') code="${code}    fdivp st1, st0"$'\n' ;;
                    '%') code="${code}    fprem"$'\n'
                         code="${code}    fstp st1"$'\n' ;;
                esac
            else
                case "$val" in
                    '+') code="${code}    pop rbx"$'\n'
                         code="${code}    pop rax"$'\n'
                         code="${code}    add rax, rbx"$'\n'
                         code="${code}    push rax"$'\n' ;;
                    '-') code="${code}    pop rbx"$'\n'
                         code="${code}    pop rax"$'\n'
                         code="${code}    sub rax, rbx"$'\n'
                         code="${code}    push rax"$'\n' ;;
                    '*') code="${code}    pop rbx"$'\n'
                         code="${code}    pop rax"$'\n'
                         code="${code}    imul rbx"$'\n'
                         code="${code}    push rax"$'\n' ;;
                    '/') code="${code}    xor rdx, rdx"$'\n'
                         code="${code}    pop rbx"$'\n'
                         code="${code}    pop rax"$'\n'
                         code="${code}    idiv rbx"$'\n'
                         code="${code}    push rax"$'\n' ;;
                    '%') code="${code}    xor rdx, rdx"$'\n'
                         code="${code}    pop rbx"$'\n'
                         code="${code}    pop rax"$'\n'
                         code="${code}    idiv rbx"$'\n'
                         code="${code}    push rdx"$'\n' ;;
                esac
            fi
        fi
    done
    
    # Store result with runtime type tag
    code="${code}    "$'\n'
    code="${code}    ; Store result in variable with type tag"$'\n'
    if [ "$use_float" = true ]; then
        code="${code}    sub rsp, 8"$'\n'
        code="${code}    fstp qword [rsp]"$'\n'
        code="${code}    movsd xmm0, [rsp]"$'\n'
        code="${code}    add rsp, 8"$'\n'
        code="${code}    movsd [${VAR_NAME}_float_val], xmm0"$'\n'
        code="${code}    mov rdi, ${VAR_NAME}_str    ; output buffer"$'\n'
        code="${code}    movsd xmm0, [${VAR_NAME}_float_val]"$'\n'
        code="${code}    call float_to_str"$'\n'
        code="${code}    mov qword [${VAR_NAME}], ${VAR_NAME}_str    ; Store pointer to string"$'\n'
        code="${code}    mov qword [${VAR_NAME}_type], TYPE_FLOAT    ; Set runtime type tag"$'\n'
    else
        code="${code}    pop rax"$'\n'
        code="${code}    mov [${VAR_NAME}], rax"$'\n'
        code="${code}    mov qword [${VAR_NAME}_type], TYPE_NUMBER    ; Set runtime type tag"$'\n'
    fi
    
    echo "$code"
}

# ----------------------------------------------------------------------
# Main logic - Determine variable type and generate appropriate code
# ----------------------------------------------------------------------
DATA_SECTION=""
CODE_SECTION=""
IS_FLOAT=false

# CHECK FOR OPERATORS FIRST (runtime evaluation needed)
if has_operators "$VAR_VALUE"; then
    echo "DEBUG: Expression contains operators, generating runtime evaluation code" >&2
    
    mapfile -t tokens < <(tokenize "$VAR_VALUE")
    mapfile -t rpn_tokens < <(to_rpn "${tokens[@]}")
    
    if contains_float "$VAR_VALUE"; then
        IS_FLOAT=true
        FLOAT_CONSTANTS=$(generate_float_constants "${rpn_tokens[@]}")
        
        DATA_SECTION="    ; ========================================="$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Variable: $VAR_NAME"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Expression: $VAR_VALUE"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Type: FLOAT (runtime evaluated)"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; ========================================="$'\n'
        DATA_SECTION="${DATA_SECTION}${FLOAT_CONSTANTS}"
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_float_val dq 0    ; Storage for float result"$'\n'
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_str times 32 db 0    ; Per-variable string buffer"$'\n'
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME} dq ${VAR_NAME}_str    ; Pointer for printing"$'\n'
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_type dq TYPE_FLOAT    ; RUNTIME TYPE TAG"$'\n'
        
        CODE_SECTION=$(generate_asm_code true "${rpn_tokens[@]}")
    else
        IS_FLOAT=false
        DATA_SECTION="    ; ========================================="$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Variable: $VAR_NAME"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Expression: $VAR_VALUE"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; Type: INTEGER (runtime evaluated)"$'\n'
        DATA_SECTION="${DATA_SECTION}    ; ========================================="$'\n'
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME} dq 0    ; Storage for integer result"$'\n'
        DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"$'\n'
        
        CODE_SECTION=$(generate_asm_code false "${rpn_tokens[@]}")
    fi

# HANDLE HEX, BINARY, OCTAL LITERALS
elif [[ "$VAR_VALUE" =~ ^-?0[xX][0-9a-fA-F]+$ ]] || \
     [[ "$VAR_VALUE" =~ ^-?0[bB][01]+$ ]] || \
     [[ "$VAR_VALUE" =~ ^-?0[0-7]+$ ]]; then
    echo "DEBUG: Non-decimal literal detected" >&2
    
    DATA_SECTION="    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Variable: $VAR_NAME = $VAR_VALUE"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Type: INTEGER (literal)"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME} dq $VAR_VALUE"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"$'\n'

# HANDLE FLOAT LITERALS
elif [[ "$VAR_VALUE" =~ ^-?[0-9]*\.[0-9]+$ ]] || [[ "$VAR_VALUE" =~ ^-?[0-9]+[eE][-+]?[0-9]+$ ]]; then
    echo "DEBUG: Float literal detected" >&2
    IS_FLOAT=true
    FLOAT_VAL=$(printf "%.10f" "$VAR_VALUE" 2>/dev/null | sed 's/\.0*$//' || echo "$VAR_VALUE")
    
    DATA_SECTION="    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Variable: $VAR_NAME = $VAR_VALUE"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Type: FLOAT (literal)"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_float_val dq 0    ; Storage for float value"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_float dd $FLOAT_VAL    ; The actual float constant"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_float_str db '$FLOAT_VAL', 0    ; String representation"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME} dq ${VAR_NAME}_float_str    ; Pointer for printing"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_type dq TYPE_FLOAT    ; RUNTIME TYPE TAG"$'\n'
    
    CODE_SECTION="    ; Initialize float value at runtime"$'\n'
    CODE_SECTION="${CODE_SECTION}    fld dword [${VAR_NAME}_float]"$'\n'
    CODE_SECTION="${CODE_SECTION}    fstp qword [${VAR_NAME}_float_val]"$'\n'

# HANDLE INTEGER LITERALS (default case)
else
    echo "DEBUG: Integer literal detected" >&2
    
    DATA_SECTION="    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Variable: $VAR_NAME = $VAR_VALUE"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; Type: INTEGER (literal)"$'\n'
    DATA_SECTION="${DATA_SECTION}    ; ========================================="$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME} dq $VAR_VALUE"$'\n'
    DATA_SECTION="${DATA_SECTION}    ${VAR_NAME}_type dq TYPE_NUMBER    ; RUNTIME TYPE TAG"$'\n'
fi

# ----------------------------------------------------------------------
# Insert into build_output.asm with type tag support
# ----------------------------------------------------------------------
echo "DEBUG: Inserting data section and code section into $OUTPUT_FILE" >&2

TEMP_FILE=$(mktemp)
IN_DATA=0
IN_START=0
DATA_DONE=0
CODE_DONE=0

while IFS= read -r line; do
    # Track which section we're in
    if [[ "$line" == "section .data" ]]; then
        IN_DATA=1
    elif [[ "$line" == section* ]] && [ "$IN_DATA" -eq 1 ]; then
        if [ "$DATA_DONE" -eq 0 ] && [ -n "$DATA_SECTION" ]; then
            echo "$DATA_SECTION" >> "$TEMP_FILE"
            DATA_DONE=1
        fi
        IN_DATA=0
    fi
    
    # Track when we enter _start
    if [[ "$line" == "_start:" ]]; then
        IN_START=1
    fi
    
    # Insert code before the exit syscall
    if [ "$IN_START" -eq 1 ] && [ "$CODE_DONE" -eq 0 ] && \
       [[ "$line" =~ ^[[:space:]]*mov[[:space:]]+rax,[[:space:]]*60 ]] && \
       [ -n "$CODE_SECTION" ]; then
        echo "$CODE_SECTION" >> "$TEMP_FILE"
        CODE_DONE=1
    fi
    
    echo "$line" >> "$TEMP_FILE"
done < "$OUTPUT_FILE"

# Handle edge cases where sections weren't found
if [ "$IN_DATA" -eq 1 ] && [ "$DATA_DONE" -eq 0 ] && [ -n "$DATA_SECTION" ]; then
    echo "$DATA_SECTION" >> "$TEMP_FILE"
fi

if [ "$CODE_DONE" -eq 0 ] && [ -n "$CODE_SECTION" ]; then
    echo "$CODE_SECTION" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$OUTPUT_FILE"

# Final status message
if [ "$IS_FLOAT" = true ]; then
    echo "✓ Successfully added float variable: $VAR_NAME = $VAR_VALUE"
    echo "  - Runtime type tag: TYPE_FLOAT"
    echo "  - All calculations performed at assembly runtime"
else
    echo "✓ Successfully added integer variable: $VAR_NAME = $VAR_VALUE"
    echo "  - Runtime type tag: TYPE_NUMBER"
    if has_operators "$VAR_VALUE"; then
        echo "  - Expression evaluated at assembly runtime"
    else
        echo "  - Literal value stored directly"
    fi
fi

echo "  - Variable accessible via: mov rax, [$VAR_NAME]"
echo "  - Type accessible via: mov rdx, [${VAR_NAME}_type]"

exit 0