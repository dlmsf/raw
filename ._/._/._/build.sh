#!/bin/bash

# build.sh - Optimized version with single-pass processing
# Added execution time tracking with --silent option
# Added support for .sh files in addition to .asm and binaries
# Added --verbose mode to show full logs including nested executions
# NEW: Detects bare assignments (variable = value) and treats them as reassignments

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set strict mode for better error handling
set -euo pipefail

# Configuration - now using absolute paths based on script directory
ARCH_OUTPUT="${SCRIPT_DIR}/../arch_output"
BASH_RUNNER="${SCRIPT_DIR}/../basm/sbasm.sh"
JS_DIR="${SCRIPT_DIR}/js/"
CHAIN_DIR="${SCRIPT_DIR}/chain/"

# Maximum number of output lines to show per nested execution in verbose mode
MAX_VERBOSE_OUTPUT_LINES=20

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Initialize counters
processed_count=0
error_count=0

# Time tracking variables
START_TIME=0
TOTAL_CREATION_TIME=0
TOTAL_EXECUTION_TIME=0

# Output mode flags
SILENT_MODE=false
VERBOSE_MODE=false

# Buffer for accumulating content
declare -a TAG_BUFFER=()
CURRENT_TAG=""
CURRENT_CONTENT=""

# Execution depth tracking for verbose mode
EXECUTION_DEPTH=0
EXECUTION_PATH=()
EXECUTION_TREE=()

# Function to get current timestamp in milliseconds
get_timestamp_ms() {
    echo $(($(date +%s%N)/1000000))
}

# Function to format milliseconds to human readable time
format_duration() {
    local ms=$1
    local seconds=$((ms / 1000))
    local milliseconds=$((ms % 1000))
   
    if (( seconds > 0 )); then
        echo "${seconds}.${milliseconds}s"
    else
        echo "${milliseconds}ms"
    fi
}

# Function to get indentation based on execution depth
get_indent() {
    local depth=$1
    local indent=""
    for ((i=0; i<depth; i++)); do
        indent+="  "
    done
    echo "$indent"
}

# Function to build execution tree visualization
get_tree_prefix() {
    local depth=$1
    local is_last=$2
    local prefix=""
   
    for ((i=0; i<depth-1; i++)); do
        if [[ "${EXECUTION_TREE[$i]}" == "last" ]]; then
            prefix+="    "
        else
            prefix+="│   "
        fi
    done
   
    if [[ $depth -gt 0 ]]; then
        if [[ "$is_last" == "true" ]]; then
            prefix+="└── "
        else
            prefix+="├── "
        fi
    fi
   
    echo "$prefix"
}

# Function to log messages based on mode
log_info() {
    if [[ "$SILENT_MODE" == false ]]; then
        local indent=$(get_indent $EXECUTION_DEPTH)
        echo -e "${GREEN}[INFO]${NC} ${indent}$1"
    fi
}

log_warn() {
    if [[ "$SILENT_MODE" == false ]]; then
        local indent=$(get_indent $EXECUTION_DEPTH)
        echo -e "${YELLOW}[WARN]${NC} ${indent}$1"
    fi
}

log_error() {
    # Always show errors
    local indent=$(get_indent $EXECUTION_DEPTH)
    echo -e "${RED}[ERROR]${NC} ${indent}$1" >&2
}

# Function for verbose logging (only in verbose mode)
log_verbose() {
    if [[ "$VERBOSE_MODE" == true ]]; then
        local indent=$(get_indent $EXECUTION_DEPTH)
        echo -e "${CYAN}[VERBOSE]${NC} ${indent}$1"
    fi
}

# Function for debug logging (only in verbose mode, more detailed)
log_debug() {
    if [[ "$VERBOSE_MODE" == true ]]; then
        local indent=$(get_indent $EXECUTION_DEPTH)
        echo -e "${PURPLE}[DEBUG]${NC} ${indent}$1"
    fi
}

# Function to show execution header in verbose mode
log_execution_start() {
    if [[ "$VERBOSE_MODE" == true ]]; then
        local execution_type=$1
        local file_path=$2
        local tree_prefix=$(get_tree_prefix $EXECUTION_DEPTH "false")
       
        echo ""
        echo -e "${WHITE}${tree_prefix}▶ ${execution_type}: ${file_path}${NC}"
       
        if [[ $EXECUTION_DEPTH -gt 0 ]]; then
            local call_chain=""
            for ((i=0; i<${#EXECUTION_PATH[@]}; i++)); do
                if [[ $i -gt 0 ]]; then
                    call_chain+=" → "
                fi
                call_chain+="${EXECUTION_PATH[$i]}"
            done
            echo -e "${ORANGE}${tree_prefix}  Chain: ${call_chain}${NC}"
        fi
    fi
}

# Function to show execution footer in verbose mode
log_execution_end() {
    if [[ "$VERBOSE_MODE" == true ]]; then
        local status=$1
        local duration=$2
        local tree_prefix=$(get_tree_prefix $EXECUTION_DEPTH "false")
       
        if [[ $status -eq 0 ]]; then
            echo -e "${GREEN}${tree_prefix}✓ Completed: $(format_duration $duration)${NC}"
        else
            echo -e "${RED}${tree_prefix}✗ Failed (exit code: $status): $(format_duration $duration)${NC}"
        fi
        echo ""
    fi
}

# Function to show file content in verbose mode (truncated)
log_file_content() {
    if [[ "$VERBOSE_MODE" == true ]]; then
        local file_path="$1"
        local content="$2"
        local total_lines=$(echo "$content" | wc -l)
        local tree_prefix=$(get_tree_prefix $EXECUTION_DEPTH "false")
       
        echo -e "${CYAN}${tree_prefix}  File: $file_path${NC}"
        echo -e "${CYAN}${tree_prefix}  Content:${NC}"
        echo "$content" | head -5 | while IFS= read -r line; do
            echo -e "${CYAN}${tree_prefix}    $line${NC}"
        done
        if [[ $total_lines -gt 5 ]]; then
            echo -e "${CYAN}${tree_prefix}    ... (truncated, total lines: $total_lines)${NC}"
        fi
    fi
}

# Function to print truncated output with tree visualization
log_truncated_output() {
    local label="$1"
    local output="$2"
    local max_lines="$3"
    local total_lines=$(echo "$output" | wc -l)
    local tree_prefix=$(get_tree_prefix $EXECUTION_DEPTH "false")
   
    if [[ $total_lines -le $max_lines ]]; then
        echo "$output" | while IFS= read -r line; do
            echo -e "${CYAN}${tree_prefix}  │ ${line}${NC}"
        done
    else
        local half_lines=$((max_lines / 2))
        echo -e "${CYAN}${tree_prefix}  │ ── Output (showing ${half_lines}/${total_lines} lines) ──${NC}"
        echo "$output" | head -n $half_lines | while IFS= read -r line; do
            echo -e "${CYAN}${tree_prefix}  │ ${line}${NC}"
        done
        echo -e "${CYAN}${tree_prefix}  │ ... ($((total_lines - max_lines)) lines omitted) ...${NC}"
        echo "$output" | tail -n $half_lines | while IFS= read -r line; do
            echo -e "${CYAN}${tree_prefix}  │ ${line}${NC}"
        done
        echo -e "${CYAN}${tree_prefix}  │ ── End of output ──${NC}"
    fi
}

# Function to check if content is a declaration
is_declaration() {
    local content="$1"
   
    local trimmed="${content#"${content%%[![:space:]]*}"}"
   
    if [[ "$trimmed" =~ ^(let\ |const\ |var\ ) ]]; then
        echo "${BASH_REMATCH[1]% }"
    else
        echo ""
    fi
}

# Function to check if content is a bare assignment (variable = value)
is_assignment() {
    local content="$1"
    local trimmed="${content#"${content%%[![:space:]]*}"}"
    if [[ "$trimmed" =~ ^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to parse method name from expression
parse_method_name() {
    local content="$1"
    local trimmed="${content//[[:space:]]/}"
    local method_part="${trimmed%%(*}"
    echo "$method_part"
}

# Function to check for available executable files in order of preference
check_executable_exists() {
    local base_path="$1"
   
    if [[ -f "$base_path" ]] && [[ -x "$base_path" || -x "${base_path%.*}" ]]; then
        echo "binary"
        return 0
    elif [[ -f "${base_path}.asm" ]]; then
        echo "asm"
        return 0
    elif [[ -f "${base_path}.sh" ]]; then
        echo "sh"
        return 0
    else
        echo ""
        return 1
    fi
}

# Function to create temporary content file with time tracking
create_temp_file() {
    local file_path="$1"
    local content="$2"
    local creation_start_time=0
   
    mkdir -p "$(dirname "$file_path")"
    creation_start_time=$(get_timestamp_ms)
    echo -n "$content" > "$file_path"
    local result=$?
    local creation_end_time=$(get_timestamp_ms)
    local creation_duration=$((creation_end_time - creation_start_time))
    TOTAL_CREATION_TIME=$((TOTAL_CREATION_TIME + creation_duration))
   
    if [[ $result -eq 0 ]]; then
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Created file: $file_path ($(format_duration $creation_duration))"
        fi
        log_verbose "File created: $file_path (size: ${#content} bytes, time: $(format_duration $creation_duration))"
        log_file_content "$file_path" "$content"
        return 0
    else
        log_error "Failed to create file: $file_path ($(format_duration $creation_duration))"
        return 1
    fi
}

# Function to execute basm.sh for .asm files with truncated verbose output
execute_basm() {
    local input_file="$1"
    local asm_file="$2"
    local execution_start_time=0
    local output_file="${asm_file%.asm}_output.txt"
   
    EXECUTION_TREE+=("false")
    EXECUTION_PATH+=("$(basename "$asm_file")")
    EXECUTION_DEPTH=$((EXECUTION_DEPTH + 1))
   
    log_execution_start "BASM" "$asm_file"
   
    if [[ "$SILENT_MODE" == false ]]; then
        log_info "Executing: bash $BASH_RUNNER $asm_file"
    fi
   
    execution_start_time=$(get_timestamp_ms)
    local exit_code=0
   
    if [[ "$VERBOSE_MODE" == true ]]; then
        log_debug "Running basm with truncated verbose output capture..."
        bash "$BASH_RUNNER" "$asm_file" > "$output_file" 2>&1
        exit_code=$?
        if [[ -f "$output_file" ]]; then
            local captured_output=$(cat "$output_file")
            log_debug "Full output saved to: $output_file"
            if [[ -n "$captured_output" ]]; then
                log_truncated_output "BASM OUTPUT" "$captured_output" "$MAX_VERBOSE_OUTPUT_LINES"
            fi
        fi
    else
        if bash "$BASH_RUNNER" "$asm_file" >/dev/null 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi
   
    local execution_end_time=$(get_timestamp_ms)
    local execution_duration=$((execution_end_time - execution_start_time))
    TOTAL_EXECUTION_TIME=$((TOTAL_EXECUTION_TIME + execution_duration))
    log_execution_end $exit_code $execution_duration
   
    EXECUTION_DEPTH=$((EXECUTION_DEPTH - 1))
    unset 'EXECUTION_PATH[-1]'
    unset 'EXECUTION_TREE[-1]'
   
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Execution completed successfully ($(format_duration $execution_duration))"
        fi
        return 0
    else
        if [[ "$SILENT_MODE" == false ]]; then
            log_error "Execution failed with exit code: $exit_code ($(format_duration $execution_duration))"
        fi
        return $exit_code
    fi
}

# Function to execute binary files directly with truncated verbose output
execute_binary() {
    local input_file="$1"
    local binary_file="$2"
    local execution_start_time=0
    local output_file="${binary_file}_output.txt"
   
    chmod +x "$binary_file" 2>/dev/null || true
    EXECUTION_TREE+=("false")
    EXECUTION_PATH+=("$(basename "$binary_file")")
    EXECUTION_DEPTH=$((EXECUTION_DEPTH + 1))
    log_execution_start "BINARY" "$binary_file"
   
    if [[ "$SILENT_MODE" == false ]]; then
        log_info "Executing binary directly: $binary_file"
    fi
   
    execution_start_time=$(get_timestamp_ms)
    local exit_code=0
   
    if [[ "$VERBOSE_MODE" == true ]]; then
        log_debug "Running binary with truncated verbose output capture..."
        "$binary_file" > "$output_file" 2>&1
        exit_code=$?
        if [[ -f "$output_file" ]]; then
            local captured_output=$(cat "$output_file")
            log_debug "Full output saved to: $output_file"
            if [[ -n "$captured_output" ]]; then
                log_truncated_output "BINARY OUTPUT" "$captured_output" "$MAX_VERBOSE_OUTPUT_LINES"
            fi
        fi
    else
        if "$binary_file" >/dev/null 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi
   
    local execution_end_time=$(get_timestamp_ms)
    local execution_duration=$((execution_end_time - execution_start_time))
    TOTAL_EXECUTION_TIME=$((TOTAL_EXECUTION_TIME + execution_duration))
    log_execution_end $exit_code $execution_duration
   
    EXECUTION_DEPTH=$((EXECUTION_DEPTH - 1))
    unset 'EXECUTION_PATH[-1]'
    unset 'EXECUTION_TREE[-1]'
   
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Binary execution completed successfully ($(format_duration $execution_duration))"
        fi
        return 0
    else
        if [[ "$SILENT_MODE" == false ]]; then
            log_error "Binary execution failed with exit code: $exit_code ($(format_duration $execution_duration))"
        fi
        return $exit_code
    fi
}

# Function to execute .sh files directly with bash and truncated verbose output
execute_sh() {
    local input_file="$1"
    local sh_file="$2"
    local execution_start_time=0
    local output_file="${sh_file%.sh}_output.txt"
   
    chmod +x "$sh_file" 2>/dev/null || true
    EXECUTION_TREE+=("false")
    EXECUTION_PATH+=("$(basename "$sh_file")")
    EXECUTION_DEPTH=$((EXECUTION_DEPTH + 1))
    log_execution_start "SHELL" "$sh_file"
   
    if [[ "$SILENT_MODE" == false ]]; then
        log_info "Executing shell script: bash $sh_file"
    fi
   
    execution_start_time=$(get_timestamp_ms)
    local exit_code=0
   
    if [[ "$VERBOSE_MODE" == true ]]; then
        log_debug "Running shell script with truncated verbose output capture..."
        if [[ -f "$sh_file" ]]; then
            local script_content=$(cat "$sh_file")
            local script_total_lines=$(echo "$script_content" | wc -l)
            local tree_prefix=$(get_tree_prefix $EXECUTION_DEPTH "false")
            echo -e "${PURPLE}${tree_prefix}  Script preview (${script_total_lines} lines):${NC}"
            echo "$script_content" | head -10 | while IFS= read -r line; do
                echo -e "${PURPLE}${tree_prefix}  │ ${line}${NC}"
            done
            if [[ $script_total_lines -gt 10 ]]; then
                echo -e "${PURPLE}${tree_prefix}  │ ... ($((script_total_lines - 10)) more lines)${NC}"
            fi
        fi
        bash "$sh_file" > "$output_file" 2>&1
        exit_code=$?
        if [[ -f "$output_file" ]]; then
            local captured_output=$(cat "$output_file")
            log_debug "Full output saved to: $output_file"
            if [[ -n "$captured_output" ]]; then
                log_truncated_output "SH OUTPUT" "$captured_output" "$MAX_VERBOSE_OUTPUT_LINES"
            fi
        fi
    else
        if bash "$sh_file" >/dev/null 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi
   
    local execution_end_time=$(get_timestamp_ms)
    local execution_duration=$((execution_end_time - execution_start_time))
    TOTAL_EXECUTION_TIME=$((TOTAL_EXECUTION_TIME + execution_duration))
    log_execution_end $exit_code $execution_duration
   
    EXECUTION_DEPTH=$((EXECUTION_DEPTH - 1))
    unset 'EXECUTION_PATH[-1]'
    unset 'EXECUTION_TREE[-1]'
   
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Shell script execution completed successfully ($(format_duration $execution_duration))"
        fi
        return 0
    else
        if [[ "$SILENT_MODE" == false ]]; then
            log_error "Shell script execution failed with exit code: $exit_code ($(format_duration $execution_duration))"
        fi
        return $exit_code
    fi
}

# Function to handle JavaScript-like content with support for .sh files
handle_js_content() {
    local content="$1"
   
    if [[ "$SILENT_MODE" == false ]]; then
        log_info "Processing JS content: ${content:0:50}..."
    fi
   
    log_verbose "Processing JS content (length: ${#content} chars)"
    log_debug "Content preview: ${content:0:100}..."
   
    local trimmed_content=$(echo "$content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if this is a bare assignment (no var/let/const keyword)
    if [[ "$(is_assignment "$trimmed_content")" == "true" ]]; then
        log_info "Detected bare assignment (reassignment) - treating as var declaration"
        export REASSIGNMENT=true
        local declaration_type="var"
        local input_file="${JS_DIR}${declaration_type}_input"
        local base_file="${JS_DIR}${declaration_type}"
        if create_temp_file "$input_file" "$content"; then
            local file_type
            file_type=$(check_executable_exists "$base_file")
            log_verbose "Executable type found: $file_type"
            case "$file_type" in
                "binary")
                    if execute_binary "$input_file" "$base_file"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                "asm")
                    if execute_basm "$input_file" "${base_file}.asm"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                "sh")
                    if execute_sh "$input_file" "${base_file}.sh"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                *)
                    log_error "No executable found for assignment (checked: $base_file, ${base_file}.asm, ${base_file}.sh)"
                    error_count=$((error_count + 1))
                    ;;
            esac
        else
            error_count=$((error_count + 1))
        fi
        unset REASSIGNMENT
        return
    fi
   
    # Check for declarations (var/let/const)
    local declaration_type
    declaration_type=$(is_declaration "$content")
   
    if [[ -n "$declaration_type" ]]; then
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Processing declaration: $declaration_type"
        fi
        log_verbose "Detected declaration type: $declaration_type"
        local input_file="${JS_DIR}${declaration_type}_input"
        local base_file="${JS_DIR}${declaration_type}"
        if create_temp_file "$input_file" "$content"; then
            local file_type
            file_type=$(check_executable_exists "$base_file")
            log_verbose "Executable type found: $file_type"
            case "$file_type" in
                "binary")
                    if execute_binary "$input_file" "$base_file"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                "asm")
                    if execute_basm "$input_file" "${base_file}.asm"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                "sh")
                    if execute_sh "$input_file" "${base_file}.sh"; then
                        processed_count=$((processed_count + 1))
                    else
                        error_count=$((error_count + 1))
                    fi
                    ;;
                *)
                    log_error "No executable found for declaration: $declaration_type (checked: $base_file, ${base_file}.asm, ${base_file}.sh)"
                    error_count=$((error_count + 1))
                    ;;
            esac
        else
            error_count=$((error_count + 1))
        fi
        return
    fi
   
    # Try to parse as method call
    local method_name
    method_name=$(parse_method_name "$content")
   
    if [[ -n "$method_name" ]]; then
        log_verbose "Parsed method name: $method_name"
        local parts
        IFS='.' read -ra parts <<< "$method_name"
        local dir_path="$JS_DIR"
        local file_name=""
        if [[ ${#parts[@]} -eq 1 ]]; then
            dir_path+="${parts[0]}/"
            file_name="${parts[0]}"
        else
            for ((i=0; i<${#parts[@]}-1; i++)); do
                dir_path+="${parts[i]}/"
            done
            file_name="${parts[-1]}"
        fi
        log_verbose "Resolved path: $dir_path, file: $file_name"
        local input_file="${dir_path}${file_name}_input"
        local base_file="${dir_path}${file_name}"
        if [[ "$SILENT_MODE" == false ]]; then
            log_info "Checking for executable: $base_file (binary, .asm, or .sh)"
        fi
        local file_type
        file_type=$(check_executable_exists "$base_file")
        log_verbose "Found executable type: $file_type"
        if [[ -n "$file_type" ]]; then
            if create_temp_file "$input_file" "$content"; then
                case "$file_type" in
                    "binary")
                        if execute_binary "$input_file" "$base_file"; then
                            processed_count=$((processed_count + 1))
                        else
                            error_count=$((error_count + 1))
                        fi
                        ;;
                    "asm")
                        if execute_basm "$input_file" "${base_file}.asm"; then
                            processed_count=$((processed_count + 1))
                        else
                            error_count=$((error_count + 1))
                        fi
                        ;;
                    "sh")
                        if execute_sh "$input_file" "${base_file}.sh"; then
                            processed_count=$((processed_count + 1))
                        else
                            error_count=$((error_count + 1))
                        fi
                        ;;
                esac
                return
            else
                error_count=$((error_count + 1))
                return
            fi
        fi
    fi
   
    # Fallback
    if [[ "$SILENT_MODE" == false ]]; then
        log_warn "No specific handler found, using fallback"
    fi
    log_verbose "Using fallback handler for content"
    local input_file="${JS_DIR}call_input"
    local base_file="${JS_DIR}call"
    if create_temp_file "$input_file" "$content"; then
        local file_type
        file_type=$(check_executable_exists "$base_file")
        log_verbose "Fallback executable type: $file_type"
        case "$file_type" in
            "binary")
                if execute_binary "$input_file" "$base_file"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            "asm")
                if execute_basm "$input_file" "${base_file}.asm"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            "sh")
                if execute_sh "$input_file" "${base_file}.sh"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            *)
                log_error "Fallback executable not found: $base_file (binary, .asm, or .sh)"
                error_count=$((error_count + 1))
                ;;
        esac
    else
        error_count=$((error_count + 1))
    fi
}

# Function to handle chain blocks with .sh support
handle_chain_block() {
    local content="$1"
   
    if [[ "$SILENT_MODE" == false ]]; then
        log_info "Processing chain block (length: ${#content})"
    fi
    log_verbose "Processing chain block (length: ${#content} chars)"
    log_debug "Chain block preview: ${content:0:100}..."
    local input_file="${CHAIN_DIR}chain_input"
    local base_file="${CHAIN_DIR}chain"
    if create_temp_file "$input_file" "$content"; then
        local file_type
        file_type=$(check_executable_exists "$base_file")
        log_verbose "Chain executable type: $file_type"
        case "$file_type" in
            "binary")
                if execute_binary "$input_file" "$base_file"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            "asm")
                if execute_basm "$input_file" "${base_file}.asm"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            "sh")
                if execute_sh "$input_file" "${base_file}.sh"; then
                    processed_count=$((processed_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                ;;
            *)
                log_error "Chain executable not found: $base_file (binary, .asm, or .sh)"
                error_count=$((error_count + 1))
                ;;
        esac
    else
        error_count=$((error_count + 1))
    fi
}

# Function to process buffered content when a tag ends
process_buffered_content() {
    local content="$CURRENT_CONTENT"
    local tag="$CURRENT_TAG"
    content=$(echo "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ -n "$content" ]]; then
        log_verbose "Processing buffered content for tag: $tag (length: ${#content})"
        case "$tag" in
            "<js-start>")
                handle_js_content "$content"
                ;;
            "<chain-start>")
                handle_chain_block "$content"
                ;;
        esac
    fi
    CURRENT_CONTENT=""
    CURRENT_TAG=""
}

# Main function to process the arch_output file
main() {
    START_TIME=$(get_timestamp_ms)
    cd "$SCRIPT_DIR"
    if [[ "$SILENT_MODE" == false ]]; then
        if [[ "$VERBOSE_MODE" == true ]]; then
            echo -e "${WHITE}╔══════════════════════════════════════════╗${NC}"
            echo -e "${WHITE}║         BUILD PROCESS - VERBOSE MODE      ║${NC}"
            echo -e "${WHITE}╚══════════════════════════════════════════╝${NC}"
            echo ""
            log_debug "Script PID: $$"
            log_debug "Script directory: $SCRIPT_DIR"
            log_debug "Using BASH_RUNNER: $BASH_RUNNER"
            log_debug "ARCH_OUTPUT: $ARCH_OUTPUT"
            log_debug "Max verbose output lines per execution: $MAX_VERBOSE_OUTPUT_LINES"
            echo ""
        fi
        log_info "Starting build process..."
        log_info "Working directory: $SCRIPT_DIR"
        log_info "Reading from: $ARCH_OUTPUT"
    fi
    if [[ ! -f "$ARCH_OUTPUT" ]]; then
        log_error "Input file not found: $ARCH_OUTPUT"
        exit 1
    fi
    if [[ ! -f "$BASH_RUNNER" ]]; then
        log_error "BASH runner not found: $BASH_RUNNER"
        exit 1
    fi
    mkdir -p "$JS_DIR"
    mkdir -p "$CHAIN_DIR"
    local line
    local in_tag=0
    local chain_depth=0
    local chain_buffer=""
    local in_chain=0
    log_verbose "Starting to parse $ARCH_OUTPUT"
    while IFS= read -r line; do
        log_debug "Processing line: ${line:0:50}..."
        if [[ $in_chain -eq 1 ]]; then
            chain_buffer+="$line"$'\n'
            if [[ "$line" == *"<chain-start>"* ]]; then
                ((chain_depth++))
                log_debug "Nested chain-start detected, depth: $chain_depth"
            fi
            if [[ "$line" == *"<chain-end>"* ]]; then
                ((chain_depth--))
                log_debug "Chain-end detected, remaining depth: $chain_depth"
                if [[ $chain_depth -eq 0 ]]; then
                    log_verbose "End of chain block reached, processing..."
                    handle_chain_block "$chain_buffer"
                    chain_buffer=""
                    in_chain=0
                fi
            fi
            continue
        fi
        if [[ "$line" == *"<chain-start>"* ]]; then
            if [[ $in_tag -eq 0 ]]; then
                chain_buffer="$line"$'\n'
                in_chain=1
                chain_depth=1
                log_verbose "Chain block started"
                continue
            fi
        fi
        if [[ $in_tag -eq 0 ]]; then
            if [[ "$line" == *"<js-start>"* ]]; then
                CURRENT_TAG="<js-start>"
                in_tag=1
                line="${line#*<js-start>}"
                log_debug "js-start tag found"
            fi
        fi
        if [[ $in_tag -eq 1 ]]; then
            if [[ "$line" == *"<js-end>"* ]]; then
                CURRENT_CONTENT+="${line%<js-end>*}"
                log_debug "js-end tag found, processing buffered content"
                process_buffered_content
                remaining="${line#*<js-end>}"
                if [[ -n "$remaining" ]]; then
                    if [[ "$remaining" == *"<js-start>"* ]]; then
                        CURRENT_TAG="<js-start>"
                        in_tag=1
                        CURRENT_CONTENT="${remaining#*<js-start>}"
                        log_debug "Another js-start found in same line"
                    else
                        in_tag=0
                    fi
                else
                    in_tag=0
                fi
            else
                CURRENT_CONTENT+="$line"$'\n'
            fi
        else
            if [[ "$line" == *"<js-start>"* ]]; then
                CURRENT_TAG="<js-start>"
                in_tag=1
                CURRENT_CONTENT="${line#*<js-start>}"
                log_debug "js-start tag found (outside of tag context)"
            fi
        fi
    done < "$ARCH_OUTPUT"
    if [[ -n "$CURRENT_CONTENT" && -n "$CURRENT_TAG" ]]; then
        log_verbose "Processing remaining buffered content"
        process_buffered_content
    fi
    if [[ $in_chain -eq 1 ]]; then
        log_error "Unclosed chain block detected"
        error_count=$((error_count + 1))
    fi
    local END_TIME=$(get_timestamp_ms)
    local TOTAL_DURATION=$((END_TIME - START_TIME))
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}[INFO]${NC} Build process completed"
    echo -e "${GREEN}[INFO]${NC} Total execution time: $(format_duration $TOTAL_DURATION)"
    echo -e "${GREEN}[INFO]${NC} File creation time: $(format_duration $TOTAL_CREATION_TIME)"
    echo -e "${GREEN}[INFO]${NC} Script execution time: $(format_duration $TOTAL_EXECUTION_TIME)"
    echo -e "${GREEN}[INFO]${NC} Successfully processed: $processed_count"
    echo -e "${GREEN}[INFO]${NC} Errors encountered: $error_count"
    if [[ "$VERBOSE_MODE" == true ]]; then
        echo -e "${GREEN}[INFO]${NC} Verbose mode was enabled"
        echo -e "${GREEN}[INFO]${NC} Max execution depth reached: $EXECUTION_DEPTH"
    fi
    echo -e "${BLUE}========================================${NC}"
    if [[ $error_count -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

show_usage() {
    echo "Usage: $0 [--silent | --verbose | --help]"
    echo ""
    echo "Options:"
    echo "  --silent    Execute without verbose logging, only show final summary"
    echo "  --verbose   Show detailed execution logs including nested execution tree"
    echo "  -h, --help  Show this help message"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --silent)
                if [[ "$VERBOSE_MODE" == true ]]; then
                    log_error "Cannot use --silent and --verbose together"
                    show_usage
                fi
                SILENT_MODE=true
                shift
                ;;
            --verbose)
                if [[ "$SILENT_MODE" == true ]]; then
                    log_error "Cannot use --silent and --verbose together"
                    show_usage
                fi
                VERBOSE_MODE=true
                SILENT_MODE=false
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

parse_args "$@"
cd "$SCRIPT_DIR"
if [[ -f "$ARCH_OUTPUT" ]]; then
    main
else
    log_error "File not found: $ARCH_OUTPUT"
    exit 1
fi
