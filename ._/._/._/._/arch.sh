#!/bin/bash

# =============================================================================
# JavaScript Parser/Formatter Script - Replicating Assembly Code Functionality
# =============================================================================
# Processes JavaScript files to identify and tag statements and code blocks
# Output: Terminal (colored), File "arch_output" (no colors)
# =============================================================================

set -e  # Exit on error

# =============================================================================
# COLOR DEFINITIONS (Terminal only)
# =============================================================================
RESET_COLOR=$'\033[0m'
COLORS=(
    $'\033[1;33m'  # Bright yellow
    $'\033[1;36m'  # Bright cyan  
    $'\033[1;32m'  # Bright green
    $'\033[1;35m'  # Bright magenta
)

# =============================================================================
# TAGS FOR OUTPUT
# =============================================================================
JS_START_TAG="<js-start>"
JS_END_TAG="<js-end>"
CHAIN_START_TAG="<chain-start>"
CHAIN_END_TAG="<chain-end>"
NEWLINE=$'\n'
TAB="    "
CHAIN_TAB="    "

# =============================================================================
# ERROR MESSAGES
# =============================================================================
ERR_NO_FILE="Error: No input file specified."
ERR_OPEN="Error: Could not open file."
ERR_READ="Error: Could not read file."
ERR_CREATE="Error: Could not create output file."
ERR_WRITE="Error: Could not write to output file."

# =============================================================================
# STATE VARIABLES (Matching assembly code)
# =============================================================================
declare -i BRACE_DEPTH=0
declare -i PAREN_DEPTH=0
declare -i BRACKET_DEPTH=0
declare -i CHAIN_DEPTH=0
declare -i CHAIN_STACK_PTR=0
declare -i COLOR_INDEX=0
declare -i FILE_SIZE=0

declare IN_STRING=0
declare IN_TEMPLATE=0
declare IN_COMMENT=0  # 0=none, 1=single-line, 2=multi-line
declare STMT_STARTED=0
declare SKIP_NEXT_SPACE=0
declare IN_BLOCK=0
declare BLOCK_STARTED=0
declare EMPTY_STATEMENT=0
declare ARROW_PENDING=0
declare AT_BLOCK_START=0
declare IN_CHAIN_BLOCK=0
declare EXPECTING_BLOCK=0
declare BLOCK_DECLARATION=0
declare IN_BLOCK_STMT=0

# Buffers
CURRENT_STMT=""
BLOCK_STMT=""
KEYWORD_BUFFER=""
LAST_CHAR=""
CURRENT_KEYWORD=""

# Stacks for chain tracking (matching assembly)
declare -a CHAIN_STACK=()      # Stores chain colors
declare -a CHAIN_BRACE_STACK=() # Stores brace depth when chain started

# Output buffers
CLEAN_BUFFER=""      # For file output (no colors)
CLEAN_BUFFER_SIZE=0
MAX_CLEAN_BUFFER=2048

# File handles
INPUT_FILE=""
OUTPUT_FILE="arch_output"
OUTPUT_FD=""

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print error and exit
error_exit() {
    echo "$1" >&2
    exit "${2:-1}"
}

# Get current color based on rotation
get_next_color() {
    local color="${COLORS[$COLOR_INDEX]}"
    COLOR_INDEX=$(( (COLOR_INDEX + 1) % 4 ))
    echo "$color"
}

# Get chain color (current color when chain started)
get_chain_color() {
    echo "${CHAIN_STACK[$((CHAIN_STACK_PTR - 1))]}"
}

# String length helper
string_length() {
    local str="$1"
    echo "${#str}"
}

# Compare strings
strings_equal() {
    [[ "$1" == "$2" ]]
}

# Append to clean buffer (for file output)
append_to_clean_buffer() {
    local str="$1"
    local len=${#str}
    
    if (( CLEAN_BUFFER_SIZE + len >= MAX_CLEAN_BUFFER )); then
        write_to_file
    fi
    
    CLEAN_BUFFER+="$str"
    CLEAN_BUFFER_SIZE=$((CLEAN_BUFFER_SIZE + len))
}

# Write clean buffer to output file
write_to_file() {
    if [[ -n "$CLEAN_BUFFER" ]]; then
        echo -n "$CLEAN_BUFFER" >&${OUTPUT_FD} || error_exit "$ERR_WRITE" 5
        CLEAN_BUFFER=""
        CLEAN_BUFFER_SIZE=0
    fi
}

# Print string (terminal with colors, file without)
print_string() {
    local str="$1"
    local color="$2"
    
    # Skip color codes for file output
    if [[ ! "$str" =~ ^\\033 ]]; then
        append_to_clean_buffer "$str"
    fi
    
    # Terminal output (with color if provided)
    if [[ -n "$color" ]]; then
        echo -n "${color}${str}${RESET_COLOR}"
    else
        echo -n "$str"
    fi
}

# Clear statement buffer
clear_stmt_buffer() {
    CURRENT_STMT=""
}

# Clear block statement buffer
clear_block_stmt_buffer() {
    BLOCK_STMT=""
}

# Clear keyword buffer
clear_keyword_buffer() {
    KEYWORD_BUFFER=""
}

# Append to current statement
append_to_stmt() {
    local char="$1"
    CURRENT_STMT+="$char"
}

# Append to keyword buffer
append_to_keyword_buffer() {
    local char="$1"
    if (( ${#KEYWORD_BUFFER} < 15 )); then
        KEYWORD_BUFFER+="$char"
    fi
}

# Copy current statement to block statement
copy_to_block_stmt() {
    BLOCK_STMT="$CURRENT_STMT"
}

# Check and set block keyword
check_and_set_block_keyword() {
    if [[ -z "$KEYWORD_BUFFER" ]]; then
        CURRENT_KEYWORD=0
        return
    fi
    
    case "$KEYWORD_BUFFER" in
        "if"|"else"|"for"|"while"|"function"|"do")
            CURRENT_KEYWORD=1
            ;;
        *)
            CURRENT_KEYWORD=0
            ;;
    esac
}

# Check if statement is empty
check_empty_statement() {
    EMPTY_STATEMENT=1
    local stmt="$CURRENT_STMT"
    
    # Remove all whitespace and semicolons
    local cleaned="${stmt//[[:space:];]/}"
    
    if [[ -n "$cleaned" ]]; then
        EMPTY_STATEMENT=0
    fi
}

# Trim trailing spaces from current statement
trim_trailing_spaces() {
    # Remove trailing spaces and tabs
    CURRENT_STMT="${CURRENT_STMT%"${CURRENT_STMT##*[![:space:]]}"}"
}

# =============================================================================
# CHARACTER PROCESSING FUNCTIONS
# =============================================================================

process_start_string() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    clear_keyword_buffer
    append_to_stmt '"'
    LAST_CHAR='"'
    IN_STRING=1
}

process_start_template() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    clear_keyword_buffer
    append_to_stmt '`'
    LAST_CHAR='`'
    IN_TEMPLATE=1
}

check_for_comment() {
    if [[ "$NEXT_CHAR" == "/" ]]; then
        IN_COMMENT=1
        CHAR_POS=$((CHAR_POS + 1))
    elif [[ "$NEXT_CHAR" == "*" ]]; then
        IN_COMMENT=2
        CHAR_POS=$((CHAR_POS + 1))
    else
        SKIP_NEXT_SPACE=0
        EMPTY_STATEMENT=0
        ARROW_PENDING=0
        clear_keyword_buffer
        append_to_stmt '/'
        LAST_CHAR='/'
    fi
}

process_space() {
    check_and_set_block_keyword
    clear_keyword_buffer
    
    if (( SKIP_NEXT_SPACE == 1 )); then
        return
    fi
    
    case "$LAST_CHAR" in
        '('|'['|'{'|';'|':'|',')
            # Skip space after these characters
            ;;
        *)
            append_to_stmt ' '
            SKIP_NEXT_SPACE=1
            LAST_CHAR=' '
            ;;
    esac
}

process_newline() {
    check_and_set_block_keyword
    clear_keyword_buffer
    SKIP_NEXT_SPACE=1
}

process_semicolon() {
    SKIP_NEXT_SPACE=0
    ARROW_PENDING=0
    clear_keyword_buffer
    append_to_stmt ';'
    LAST_CHAR=';'
    
    if (( IN_CHAIN_BLOCK == 1 )); then
        # In chain
        check_empty_statement
        if (( EMPTY_STATEMENT == 0 )); then
            print_chain_statement
            clear_stmt_buffer
            STMT_STARTED=0
        else
            clear_stmt_buffer
            STMT_STARTED=0
            EMPTY_STATEMENT=0
        fi
    else
        # Regular semicolon at top level
        if (( BRACE_DEPTH == 0 && PAREN_DEPTH == 0 && BRACKET_DEPTH == 0 && IN_BLOCK == 0 )); then
            check_empty_statement
            if (( EMPTY_STATEMENT == 0 )); then
                print_current_statement
                clear_stmt_buffer
                STMT_STARTED=0
                get_next_color > /dev/null  # Just rotate color
            else
                clear_stmt_buffer
                STMT_STARTED=0
                EMPTY_STATEMENT=0
            fi
        fi
    fi
}

process_open_brace() {
    SKIP_NEXT_SPACE=0
    ARROW_PENDING=0
    EMPTY_STATEMENT=0
    
    # Check if this looks like an object literal or a block
    if (( CURRENT_KEYWORD == 1 )); then
        IS_BLOCK_BRACE=1
    else
        case "$LAST_CHAR" in
            '='|':'|','|'('|'['|'{')
                IS_BLOCK_BRACE=0  # Object literal
                ;;
            *)
                # Check if in expression context
                if (( PAREN_DEPTH == 0 && BRACKET_DEPTH == 0 )); then
                    IS_BLOCK_BRACE=1  # Block
                else
                    IS_BLOCK_BRACE=0  # Object literal
                fi
                ;;
        esac
    fi
    
    if (( IS_BLOCK_BRACE == 0 )); then
        # Object literal - add to current statement
        append_to_stmt '{'
        LAST_CHAR='{'
        BRACE_DEPTH=$((BRACE_DEPTH + 1))
    else
        # Block start - save current statement as block declaration
        copy_to_block_stmt
        clear_stmt_buffer
        STMT_STARTED=0
        BRACE_DEPTH=$((BRACE_DEPTH + 1))
        
        # Save current brace depth for chain
        local prev_brace_depth=$((BRACE_DEPTH - 1))
        
        # Push onto chain stack
        CHAIN_BRACE_STACK[$CHAIN_STACK_PTR]=$prev_brace_depth
        CHAIN_STACK[$CHAIN_STACK_PTR]=$(get_next_color)
        
        # Start a chain
        start_chain
        CHAIN_STACK_PTR=$((CHAIN_STACK_PTR + 1))
    fi
}

process_close_brace() {
    SKIP_NEXT_SPACE=0
    ARROW_PENDING=0
    BRACE_DEPTH=$((BRACE_DEPTH - 1))
    
    if (( IN_CHAIN_BLOCK == 1 )); then
        # Check if this ends the current chain
        local current_idx=$((CHAIN_STACK_PTR - 1))
        if (( BRACE_DEPTH == CHAIN_BRACE_STACK[current_idx] )); then
            # End current chain
            end_chain
            CHAIN_STACK_PTR=$((CHAIN_STACK_PTR - 1))
        else
            # Nested brace in chain
            append_to_stmt '}'
            LAST_CHAR='}'
        fi
    else
        # Regular brace
        append_to_stmt '}'
        LAST_CHAR='}'
        
        # Check if top level
        if (( BRACE_DEPTH == 0 )); then
            check_empty_statement
            if (( EMPTY_STATEMENT == 0 )); then
                print_current_statement
                clear_stmt_buffer
                STMT_STARTED=0
                get_next_color > /dev/null
            else
                clear_stmt_buffer
                STMT_STARTED=0
                EMPTY_STATEMENT=0
            fi
        fi
    fi
}

process_open_paren() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    append_to_stmt '('
    LAST_CHAR='('
    PAREN_DEPTH=$((PAREN_DEPTH + 1))
}

process_close_paren() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    append_to_stmt ')'
    LAST_CHAR=')'
    PAREN_DEPTH=$((PAREN_DEPTH - 1))
}

process_open_bracket() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    append_to_stmt '['
    LAST_CHAR='['
    BRACKET_DEPTH=$((BRACKET_DEPTH + 1))
}

process_close_bracket() {
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    append_to_stmt ']'
    LAST_CHAR=']'
    BRACKET_DEPTH=$((BRACKET_DEPTH - 1))
}

process_equals() {
    clear_keyword_buffer
    SKIP_NEXT_SPACE=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=1
    append_to_stmt '='
    LAST_CHAR='='
}

process_colon() {
    clear_keyword_buffer
    SKIP_NEXT_SPACE=0
    append_to_stmt ':'
    LAST_CHAR=':'
}

process_greater() {
    if (( ARROW_PENDING == 1 )); then
        # Arrow function
        ARROW_PENDING=0
        SKIP_NEXT_SPACE=0
        EMPTY_STATEMENT=0
        append_to_stmt '>'
        LAST_CHAR='>'
    else
        ARROW_PENDING=0
        SKIP_NEXT_SPACE=0
        EMPTY_STATEMENT=0
        append_to_stmt '>'
        LAST_CHAR='>'
    fi
}

handle_string_char() {
    local char="$1"
    append_to_stmt "$char"
    LAST_CHAR="$char"
    
    if [[ "$char" == '"' ]]; then
        # Check if escaped
        if [[ "$PREV_CHAR" != '\\' ]]; then
            IN_STRING=0
        fi
    fi
}

handle_template_char() {
    local char="$1"
    append_to_stmt "$char"
    LAST_CHAR="$char"
    
    if [[ "$char" == '`' ]]; then
        # Check if escaped
        if [[ "$PREV_CHAR" != '\\' ]]; then
            IN_TEMPLATE=0
        fi
    fi
}

handle_single_line_comment() {
    local char="$1"
    if [[ "$char" == $'\n' ]]; then
        IN_COMMENT=0
    fi
}

handle_multi_line_comment() {
    local char="$1"
    if [[ "$char" == '*' && "$NEXT_CHAR" == '/' ]]; then
        IN_COMMENT=0
        CHAR_POS=$((CHAR_POS + 1))  # Skip the '/'
    fi
}

# =============================================================================
# CHAIN MANAGEMENT
# =============================================================================

start_chain() {
    local chain_color="${CHAIN_STACK[$((CHAIN_STACK_PTR))]}"
    
    # Print chain start
    print_string "$CHAIN_START_TAG" ""
    print_string "$NEWLINE" ""
    
    # Print block declaration if any
    if [[ -n "$BLOCK_STMT" ]]; then
        print_string "$CHAIN_TAB" ""
        print_string "$BLOCK_STMT" ""
        print_string "$NEWLINE" ""
    fi
    
    # Set chain state
    IN_CHAIN_BLOCK=1
    CHAIN_DEPTH=$((CHAIN_DEPTH + 1))
    
    # Clear block buffer
    clear_block_stmt_buffer
    CURRENT_KEYWORD=0  # Reset keyword after starting chain
}

end_chain() {
    # Print any remaining statement
    if [[ -n "$CURRENT_STMT" ]]; then
        check_empty_statement
        if (( EMPTY_STATEMENT == 0 )); then
            print_chain_statement
            clear_stmt_buffer
            STMT_STARTED=0
        fi
    fi
    
    EMPTY_STATEMENT=0
    
    # Print chain end
    print_string "$CHAIN_END_TAG" ""
    print_string "$NEWLINE" ""
    
    # Reset chain state if this was the last chain
    CHAIN_DEPTH=$((CHAIN_DEPTH - 1))
    
    if (( CHAIN_DEPTH == 0 )); then
        IN_CHAIN_BLOCK=0
        # Get new color for next statements (just rotate)
        get_next_color > /dev/null
    fi
}

close_all_chains() {
    while (( CHAIN_DEPTH > 0 )); do
        print_string "$CHAIN_END_TAG" ""
        print_string "$NEWLINE" ""
        CHAIN_DEPTH=$((CHAIN_DEPTH - 1))
        CHAIN_STACK_PTR=$((CHAIN_STACK_PTR - 1))
    done
    IN_CHAIN_BLOCK=0
}

# =============================================================================
# PRINTING FUNCTIONS
# =============================================================================

print_current_statement() {
    if [[ -z "$CURRENT_STMT" ]]; then
        return
    fi
    
    # Trim spaces
    trim_trailing_spaces
    
    # Get color
    local color
    color=$(get_next_color)
    
    # Print opening tag with color to terminal, without color to file
    print_string "$color" ""
    print_string "$JS_START_TAG" ""
    print_string "$RESET_COLOR" ""
    
    # Indentation
    print_string "$TAB" ""
    
    # Statement with color to terminal, without to file
    print_string "$color" ""
    print_string "$CURRENT_STMT" ""
    print_string "$RESET_COLOR" ""
    
    # Closing indentation and tag
    print_string "$TAB" ""
    
    print_string "$color" ""
    print_string "$JS_END_TAG" ""
    print_string "$NEWLINE" ""
    print_string "$RESET_COLOR" ""
}

print_chain_statement() {
    if [[ -z "$CURRENT_STMT" ]]; then
        return
    fi
    
    # Trim spaces
    trim_trailing_spaces
    
    # Get chain color from current chain
    local chain_color
    if (( CHAIN_STACK_PTR > 0 )); then
        chain_color="${CHAIN_STACK[$((CHAIN_STACK_PTR - 1))]}"
    else
        chain_color="${COLORS[0]}"
    fi
    
    # Double indentation for chain content
    print_string "$CHAIN_TAB" ""
    print_string "$CHAIN_TAB" ""
    
    # Print as js statement with color to terminal, without to file
    print_string "$chain_color" ""
    print_string "$JS_START_TAG" ""
    print_string "$RESET_COLOR" ""
    
    # Indentation
    print_string "$TAB" ""
    
    # Statement with color to terminal, without to file
    print_string "$chain_color" ""
    print_string "$CURRENT_STMT" ""
    print_string "$RESET_COLOR" ""
    
    # Closing indentation and tag
    print_string "$TAB" ""
    
    print_string "$chain_color" ""
    print_string "$JS_END_TAG" ""
    print_string "$NEWLINE" ""
    print_string "$RESET_COLOR" ""
}

# =============================================================================
# MAIN PROCESSING FUNCTION
# =============================================================================

process_file() {
    local content="$1"
    local length=${#content}
    local char
    local prev_char=""
    
    # Initialize state
    BRACE_DEPTH=0
    PAREN_DEPTH=0
    BRACKET_DEPTH=0
    CHAIN_DEPTH=0
    CHAIN_STACK_PTR=0
    IN_STRING=0
    IN_TEMPLATE=0
    IN_COMMENT=0
    STMT_STARTED=0
    LAST_CHAR=""
    SKIP_NEXT_SPACE=0
    IN_BLOCK=0
    BLOCK_STARTED=0
    EMPTY_STATEMENT=0
    ARROW_PENDING=0
    AT_BLOCK_START=0
    IN_CHAIN_BLOCK=0
    EXPECTING_BLOCK=0
    BLOCK_DECLARATION=0
    IN_BLOCK_STMT=0
    CURRENT_KEYWORD=0
    COLOR_INDEX=0
    
    # Clear buffers
    clear_stmt_buffer
    clear_block_stmt_buffer
    clear_keyword_buffer
    
    # Get first color
    get_next_color > /dev/null
    
    # Process character by character
    for (( CHAR_POS=0; CHAR_POS < length; CHAR_POS++ )); do
        char="${content:CHAR_POS:1}"
        NEXT_CHAR=""
        if (( CHAR_POS + 1 < length )); then
            NEXT_CHAR="${content:CHAR_POS+1:1}"
        fi
        
        # Skip whitespace at beginning of statement
        if (( STMT_STARTED == 0 )); then
            case "$char" in
                ' '|$'\t'|$'\n'|$'\r')
                    continue
                    ;;
            esac
            STMT_STARTED=1
        fi
        
        # Handle special contexts
        if (( IN_STRING == 1 )); then
            handle_string_char "$char"
            prev_char="$char"
            continue
        elif (( IN_TEMPLATE == 1 )); then
            handle_template_char "$char"
            prev_char="$char"
            continue
        elif (( IN_COMMENT == 1 )); then
            handle_single_line_comment "$char"
            prev_char="$char"
            continue
        elif (( IN_COMMENT == 2 )); then
            handle_multi_line_comment "$char"
            prev_char="$char"
            continue
        fi
        
        # Handle special characters
        case "$char" in
            '"')
                process_start_string
                ;;
            '`')
                process_start_template
                ;;
            '/')
                PREV_CHAR="$prev_char"
                check_for_comment
                ;;
            ' '|$'\t')
                process_space
                ;;
            $'\n'|$'\r')
                process_newline
                ;;
            ';')
                process_semicolon
                ;;
            '{')
                process_open_brace
                ;;
            '}')
                process_close_brace
                ;;
            '(')
                process_open_paren
                ;;
            ')')
                process_close_paren
                ;;
            '[')
                process_open_bracket
                ;;
            ']')
                process_close_bracket
                ;;
            '=')
                process_equals
                ;;
            ':')
                process_colon
                ;;
            '>')
                process_greater
                ;;
            *)
                # Regular character
                SKIP_NEXT_SPACE=0
                EMPTY_STATEMENT=0
                ARROW_PENDING=0
                
                # Check if alpha char for keyword
                if [[ "$char" =~ [a-zA-Z] ]]; then
                    append_to_keyword_buffer "$char"
                else
                    # Non-alpha ends keyword
                    check_and_set_block_keyword
                    clear_keyword_buffer
                fi
                
                append_to_stmt "$char"
                LAST_CHAR="$char"
                ;;
        esac
        
        prev_char="$char"
    done
    
    # Print any remaining statement
    if [[ -n "$CURRENT_STMT" ]]; then
        check_empty_statement
        if (( EMPTY_STATEMENT == 0 )); then
            if (( IN_CHAIN_BLOCK == 1 )); then
                print_chain_statement
            else
                print_current_statement
            fi
        fi
    fi
    
    # Close any open chains
    close_all_chains
    
    # Write any remaining data to file
    write_to_file
}

# =============================================================================
# MAIN PROGRAM
# =============================================================================

main() {
    # Check for input file
    if [[ $# -lt 1 ]]; then
        error_exit "$ERR_NO_FILE" 1
    fi
    
    INPUT_FILE="$1"
    
    # Open input file
    if [[ ! -f "$INPUT_FILE" ]]; then
        error_exit "$ERR_OPEN" 2
    fi
    
    # Read file content
    CONTENT=""
    if ! CONTENT=$(cat "$INPUT_FILE" 2>/dev/null); then
        error_exit "$ERR_READ" 3
    fi
    
    FILE_SIZE=${#CONTENT}
    if (( FILE_SIZE > 65536 )); then
        error_exit "Error: File too large (max 64KB)" 3
    fi
    
    # Create output file
    if ! exec {OUTPUT_FD}>"$OUTPUT_FILE"; then
        error_exit "$ERR_CREATE" 4
    fi
    
    # Process file
    process_file "$CONTENT"
    
    # Close output file
    eval "exec ${OUTPUT_FD}>&-"
    
    echo "Processing complete. Output written to $OUTPUT_FILE"
    exit 0
}

# Run main function
main "$@"
