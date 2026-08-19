#!/bin/bash

# consolelog.sh - Transform complex console.log arguments into variable declarations
# Generates declarations that match the const.sh transformation style

INPUT_FILE="$1"
OUTPUT_FILE="${2:-output.js}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <input.js> [output.js]"
    exit 1
fi

CONTENT=$(<"$INPUT_FILE")

# Generate unique variable name matching const.sh style
generate_name() {
    local prefix="${1:-log}"
    prefix=$(echo "$prefix" | tr -cd 'a-zA-Z0-9_')
    if [ -z "$prefix" ]; then prefix="log"; fi
    echo "${prefix}_$(date +%s%N)_${RANDOM}"
}

# Check if argument is simple
is_simple() {
    local arg="$1"
    arg=$(echo "$arg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # Identifier (covers true, false, null, undefined)
    if echo "$arg" | grep -qP '^[a-zA-Z_$][a-zA-Z0-9_$]*$'; then
        return 0
    fi
    # Number
    if echo "$arg" | grep -qP '^[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$'; then
        return 0
    fi
    # Single-quoted string
    if echo "$arg" | grep -qP "^'([^'\\\\]|\\\\.)*'$"; then
        return 0
    fi
    # Double-quoted string
    if echo "$arg" | grep -qP '^"([^"\\]|\\.)*"$'; then
        return 0
    fi
    return 1
}

# Main processing function
process_js() {
    local input="$1"
    local len=${#input}
    local output=""
    local stmt_buffer=""
    local declarations_to_prepend=""
    
    local i=0
    
    # State flags
    local in_sq=0
    local in_dq=0
    local in_bt=0
    local in_cmt_l=0
    local in_cmt_b=0
    local brace_depth=0

    while (( i < len )); do
        local char="${input:$i:1}"
        local next_char="${input:$((i+1)):1}"
        
        # Handle strings and comments
        if (( in_sq )); then
            stmt_buffer+="$char"
            if [[ "$char" == "'" && "${input:$((i-1)):1}" != "\\" ]]; then in_sq=0; fi
            ((i++)); continue
        elif (( in_dq )); then
            stmt_buffer+="$char"
            if [[ "$char" == '"' && "${input:$((i-1)):1}" != "\\" ]]; then in_dq=0; fi
            ((i++)); continue
        elif (( in_bt )); then
            stmt_buffer+="$char"
            if [[ "$char" == '`' && "${input:$((i-1)):1}" != "\\" ]]; then in_bt=0; fi
            ((i++)); continue
        elif (( in_cmt_l )); then
            stmt_buffer+="$char"
            if [[ "$char" == $'\n' ]]; then in_cmt_l=0; fi
            ((i++)); continue
        elif (( in_cmt_b )); then
            stmt_buffer+="$char"
            if [[ "$char" == '*' && "$next_char" == '/' ]]; then
                stmt_buffer+="/"
                in_cmt_b=0
                ((i+=2)); continue
            fi
            ((i++)); continue
        else
            if [[ "$char" == "'" ]]; then in_sq=1; stmt_buffer+="$char"; ((i++)); continue; fi
            if [[ "$char" == '"' ]]; then in_dq=1; stmt_buffer+="$char"; ((i++)); continue; fi
            if [[ "$char" == '`' ]]; then in_bt=1; stmt_buffer+="$char"; ((i++)); continue; fi
            if [[ "$char" == '/' && "$next_char" == '/' ]]; then in_cmt_l=1; stmt_buffer+="//"; ((i+=2)); continue; fi
            if [[ "$char" == '/' && "$next_char" == '*' ]]; then in_cmt_b=1; stmt_buffer+="/*"; ((i+=2)); continue; fi
        fi

        # Detect console.log call
        if [[ "$char" == "c" && "${input:$i:11}" == "console.log" ]]; then
            local prev_char="${input:$((i-1)):1}"
            if [[ "$prev_char" =~ [a-zA-Z0-9_$] ]]; then
                stmt_buffer+="$char"
                ((i++))
                continue
            fi

            local after_log=$((i+11))
            while [[ "${input:$after_log:1}" =~ [[:space:]] ]]; do ((after_log++)); done
            if [[ "${input:$after_log:1}" != "(" ]]; then
                stmt_buffer+="$char"
                ((i++))
                continue
            fi

            local paren_open=$after_log
            local j=$((paren_open+1))
            local depth=1
            local in_str=0
            local str_char=""
            local in_tmpl=0
            local in_line_comment=0
            local in_block_comment=0

            while (( j < len )); do
                local c="${input:$j:1}"
                local cnext="${input:$((j+1)):1}"
                if (( in_line_comment )); then
                    if [[ "$c" == $'\n' ]]; then in_line_comment=0; fi
                elif (( in_block_comment )); then
                    if [[ "$c" == '*' && "$cnext" == '/' ]]; then in_block_comment=0; ((j++)); fi
                elif [[ "$c" == "'" || "$c" == '"' ]]; then
                    if [[ "$c" == "'" ]]; then str_char="'"; else str_char='"'; fi
                    in_str=1
                elif [[ "$c" == '`' ]]; then
                    in_tmpl=1
                elif (( in_str )); then
                    if [[ "$c" == "$str_char" && "${input:$((j-1)):1}" != "\\" ]]; then in_str=0; fi
                elif (( in_tmpl )); then
                    if [[ "$c" == '`' && "${input:$((j-1)):1}" != "\\" ]]; then in_tmpl=0; fi
                elif [[ "$c" == '/' && "$cnext" == '/' ]]; then
                    in_line_comment=1; ((j++))
                elif [[ "$c" == '/' && "$cnext" == '*' ]]; then
                    in_block_comment=1; ((j++))
                elif [[ "$c" == '(' ]]; then
                    ((depth++))
                elif [[ "$c" == ')' ]]; then
                    ((depth--))
                    if (( depth == 0 )); then break; fi
                fi
                ((j++))
            done

            if (( j >= len )); then
                stmt_buffer+="$char"
                ((i++))
                continue
            fi

            local args="${input:$((paren_open+1)):$((j - paren_open - 1))}"
            local new_i=$((j+1))
            local trimmed_args="$(echo "$args" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

            if [[ "$trimmed_args" == *","* ]]; then
                stmt_buffer+="${input:$i:$((new_i - i))}"
                i=$new_i
                continue
            fi

            if is_simple "$trimmed_args"; then
                stmt_buffer+="${input:$i:$((new_i - i))}"
                i=$new_i
                continue
            fi

            # Generate declaration using const (will match const.sh style)
            local name=$(generate_name "log")
            local declaration="const ${name} = ${trimmed_args};"
            declarations_to_prepend+="$declaration"$'\n'
            stmt_buffer+="console.log(${name})"
            i=$new_i
            continue
        fi

        # Normal character processing
        stmt_buffer+="$char"
        if [[ "$char" == "{" ]]; then ((brace_depth++)); fi
        if [[ "$char" == "}" ]]; then ((brace_depth--)); fi
        
        if [[ "$char" == ";" && $brace_depth -eq 0 ]]; then
            output+="$declarations_to_prepend$stmt_buffer"
            stmt_buffer=""
            declarations_to_prepend=""
        fi
        
        ((i++))
    done

    output+="$declarations_to_prepend$stmt_buffer"
    echo "$output"
}

RESULT=$(process_js "$CONTENT")
echo "$RESULT" > "$OUTPUT_FILE"
echo "Transformation complete. Output saved to $OUTPUT_FILE"