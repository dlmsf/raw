#!/usr/bin/env bash

# runtest.sh - Run tests with generated JS files (fully recursive)
# Usage:
#   ./runtest.sh           # Normal execution (uses node if available, falls back to cached)
#   ./runtest.sh --save    # Execute and save node outputs to .sh files
#   ./runtest.sh --saveforce # Execute and force overwrite saved node outputs
#   ./runtest.sh --cached  # Force using saved outputs (no node required)
#   ./runtest.sh --error   # Enable error logging with verbose mode rerun

set -e

# ============================================
# ERROR LOGGING MODULE
# ============================================
# Capture caller's directory before any cd operations
if [[ -n "$OLDPWD" ]]; then
    CALLER_DIR="$OLDPWD"
else
    CALLER_DIR="$(pwd)"
fi
ERROR_LOG="${CALLER_DIR}/errorlog.txt"
ERROR_MODE=false

# Parse arguments
SAVE_MODE=false
SAVEFORCE_MODE=false
CACHED_MODE=false
AUTO_MODE=true

for arg in "$@"; do
    case "$arg" in
        --save)
            SAVE_MODE=true
            AUTO_MODE=false
            ;;
        --saveforce)
            SAVEFORCE_MODE=true
            AUTO_MODE=false
            ;;
        --cached)
            CACHED_MODE=true
            AUTO_MODE=false
            ;;
        --error)
            ERROR_MODE=true
            ;;
        *)
            echo -e "\033[0;31m\033[1mError:\033[0m Unknown argument: $arg"
            echo "Usage: $0 [--save | --saveforce | --cached] [--error]"
            exit 1
            ;;
    esac
done

# Prevent using both --save and --cached simultaneously
if [[ "$SAVE_MODE" == true ]] && [[ "$CACHED_MODE" == true ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m Cannot use --save and --cached simultaneously"
    exit 1
fi

if [[ "$SAVEFORCE_MODE" == true ]] && [[ "$CACHED_MODE" == true ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m Cannot use --saveforce and --cached simultaneously"
    exit 1
fi

if [[ "$SAVE_MODE" == true ]] && [[ "$SAVEFORCE_MODE" == true ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m Cannot use --save and --saveforce simultaneously"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're running from within a /dev directory structure
if [[ "$SCRIPT_DIR" == */dev/* ]] || [[ "$SCRIPT_DIR" == */dev ]]; then
    # Go back to one level before /dev
    DEV_PARENT="$SCRIPT_DIR"
    while [[ "$DEV_PARENT" != "/" ]]; do
        if [[ "$(basename "$DEV_PARENT")" == "dev" ]]; then
            DEV_PARENT="$(dirname "$DEV_PARENT")"
            break
        fi
        DEV_PARENT="$(dirname "$DEV_PARENT")"
    done
    
    # From DEV_PARENT, search through ._/ directories to find runtest.sh
    REPO_ROOT=""
    if [[ -n "$DEV_PARENT" ]] && [[ "$DEV_PARENT" != "/" ]]; then
        # Search for runtest.sh in nested ._ directories
        while IFS= read -r dir; do
            if [[ -f "${dir}/runtest.sh" ]] && [[ -d "${dir}/.test_cache" ]]; then
                REPO_ROOT="$dir"
                break
            fi
        done < <(find "$DEV_PARENT" -type d -name "._" 2>/dev/null | sort)
        
        # If not found in ._ directories, check DEV_PARENT itself
        if [[ -z "$REPO_ROOT" ]] && [[ -f "${DEV_PARENT}/runtest.sh" ]] && [[ -d "${DEV_PARENT}/.test_cache" ]]; then
            REPO_ROOT="$DEV_PARENT"
        fi
    fi
    
    # If found, use that directory for cache
    if [[ -n "$REPO_ROOT" ]]; then
        CACHE_DIR="${REPO_ROOT}/.test_cache"
    else
        CACHE_DIR="${SCRIPT_DIR}/.test_cache"
    fi
else
    CACHE_DIR="${SCRIPT_DIR}/.test_cache"
fi

# Define paths
TESTS_DIR="${SCRIPT_DIR}/tests"
DUAL_SCRIPT="${SCRIPT_DIR}/dual.sh"
NODE_CACHE_DIR="${CACHE_DIR}/node_outputs"

# Find Raw.sh - navigate up from SCRIPT_DIR to find it
RAW_SCRIPT=""
CURRENT_DIR="$SCRIPT_DIR"
for i in {1..6}; do
    if [[ -f "${CURRENT_DIR}/Raw.sh" ]]; then
        RAW_SCRIPT="${CURRENT_DIR}/Raw.sh"
        break
    fi
    CURRENT_DIR="$(dirname "$CURRENT_DIR")"
done

# If not found by navigating up, try to find it in the filesystem
if [[ -z "$RAW_SCRIPT" ]]; then
    # Search for Raw.sh in parent directories
    SEARCH_DIR="$SCRIPT_DIR"
    for i in {1..6}; do
        SEARCH_DIR="$(dirname "$SEARCH_DIR")"
        if [[ -f "${SEARCH_DIR}/Raw.sh" ]]; then
            RAW_SCRIPT="${SEARCH_DIR}/Raw.sh"
            break
        fi
    done
fi


# Color definitions
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'

# Check if dual.sh exists
if [[ ! -f "$DUAL_SCRIPT" ]]; then
    echo -e "${RED}${BOLD}Error:${RESET} dual.sh not found at ${DUAL_SCRIPT}"
    exit 1
fi

# Check if tests directory exists
if [[ ! -d "$TESTS_DIR" ]]; then
    echo -e "${RED}${BOLD}Error:${RESET} tests directory not found at ${TESTS_DIR}"
    exit 1
fi

# ============================================
# ERROR LOGGING FUNCTIONS
# ============================================
init_error_log() {
    if [[ "$ERROR_MODE" == true ]]; then
        echo "Error Log - Generated by runtest.sh --error" > "$ERROR_LOG"
        echo "Started at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$ERROR_LOG"
        echo "Caller Directory: ${CALLER_DIR}" >> "$ERROR_LOG"
        echo "Script Directory: ${SCRIPT_DIR}" >> "$ERROR_LOG"
        echo "Raw.sh Location: ${RAW_SCRIPT}" >> "$ERROR_LOG"
        echo "=========================================" >> "$ERROR_LOG"
        echo "" >> "$ERROR_LOG"
        
        echo -e "${YELLOW}${BOLD}Error logging enabled${RESET} - Will save errors to: $ERROR_LOG"
        if [[ -n "$RAW_SCRIPT" ]]; then
            echo -e "${YELLOW}${BOLD}Raw.sh found at:${RESET} $RAW_SCRIPT"
        else
            echo -e "${RED}${BOLD}Warning:${RESET} Raw.sh not found, verbose mode will not be captured"
        fi
    fi
}

log_error() {
    local error_message="$1"
    local test_info="$2"
    
    if [[ "$ERROR_MODE" == true ]]; then
        {
            echo "========================================="
            echo "Error detected at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            echo "Test: ${test_info}"
            echo "Error: ${error_message}"
            echo ""
        } >> "$ERROR_LOG"
    fi
}

rerun_verbose_on_error() {
    local test_path="$1"
    local test_info="$2"
    local error_code="$3"
    local diff_output="$4"
    
    if [[ "$ERROR_MODE" == true ]]; then
        echo -e "${YELLOW}${BOLD}Error detected - Running with --verbose mode...${RESET}"
        
        # Run the test again with --verbose mode using Raw.sh
        local verbose_output=""
        local verbose_exit=1
        
        if [[ -n "$RAW_SCRIPT" ]] && [[ -f "$RAW_SCRIPT" ]]; then
            verbose_output=$(bash "$RAW_SCRIPT" --verbose "$test_path" 2>&1 || true)
            verbose_exit=$?
        else
            verbose_output="Raw.sh not found at ${RAW_SCRIPT:-unknown location}"
        fi
        
        # Append both the difference output and verbose output to error log
        {
            echo "--- Difference Output ---"
            echo "$diff_output"
            echo ""
            echo "--- Verbose Mode Output ---"
            echo "Command: bash $RAW_SCRIPT --verbose $test_path"
            echo "Exit Code: ${verbose_exit}"
            echo ""
            echo "$verbose_output"
            echo ""
            echo "========================================="
            echo ""
        } >> "$ERROR_LOG"
        
        echo -e "${RED}${BOLD}Complete output saved to:${RESET} $ERROR_LOG"
        echo -e "${YELLOW}${BOLD}Continuing to next test...${RESET}"
    fi
}

# Initialize error log if enabled
init_error_log

# Auto-detect mode based on node availability and cache existence
NODE_AVAILABLE=false
if command -v node &> /dev/null; then
    NODE_AVAILABLE=true
fi

CACHE_AVAILABLE=false
if [[ -d "$NODE_CACHE_DIR" ]] && [[ -n "$(ls -A "$NODE_CACHE_DIR" 2>/dev/null)" ]]; then
    CACHE_AVAILABLE=true
fi

# Determine execution mode
if [[ "$AUTO_MODE" == true ]]; then
    if [[ "$NODE_AVAILABLE" == true ]]; then
        # Node is available, use it normally
        CACHED_MODE=false
        echo -e "${GREEN}${BOLD}Node.js detected${RESET} - Running in ${GREEN}normal mode${RESET}"
    elif [[ "$CACHE_AVAILABLE" == true ]]; then
        # No node, but cache exists - use cached mode
        CACHED_MODE=true
        echo -e "${YELLOW}${BOLD}Node.js not found${RESET} - ${CYAN}Automatically falling back to cached mode${RESET}"
    else
        echo -e "${RED}${BOLD}Error:${RESET} Node.js is not installed and no cache found."
        echo -e "${YELLOW}Options:${RESET}"
        echo -e "  1. Install Node.js to run tests normally"
        echo -e "  2. Run on a system with Node.js using ${BOLD}--save${RESET} to generate cache"
        echo -e "  3. Copy the ${BOLD}.test_cache${RESET} directory from another system"
        exit 1
    fi
elif [[ "$CACHED_MODE" == true ]]; then
    if [[ "$CACHE_AVAILABLE" == false ]]; then
        echo -e "${RED}${BOLD}Error:${RESET} --cached mode requested but no cache found at ${NODE_CACHE_DIR}"
        echo -e "${YELLOW}Run with --save first (on a system with Node.js) to generate cache files${RESET}"
        exit 1
    fi
    echo -e "${CYAN}${BOLD}Forced cached mode${RESET} - Using pre-saved outputs"
elif [[ "$SAVE_MODE" == true ]]; then
    if [[ "$NODE_AVAILABLE" == false ]]; then
        echo -e "${RED}${BOLD}Error:${RESET} --save mode requires Node.js to be installed"
        exit 1
    fi
    echo -e "${YELLOW}${BOLD}Save mode${RESET} - Will cache all node outputs"
elif [[ "$SAVEFORCE_MODE" == true ]]; then
    if [[ "$NODE_AVAILABLE" == false ]]; then
        echo -e "${RED}${BOLD}Error:${RESET} --saveforce mode requires Node.js to be installed"
        exit 1
    fi
    echo -e "${YELLOW}${BOLD}Save force mode${RESET} - Will cache all node outputs (overwriting existing files)"
fi

# Create cache directories if in save mode
if [[ "$SAVE_MODE" == true ]] || [[ "$SAVEFORCE_MODE" == true ]]; then
    mkdir -p "$NODE_CACHE_DIR"
    echo -e "${CYAN}${BOLD}Cache directory:${RESET} ${NODE_CACHE_DIR}"
fi

echo ""

# Arrays to track test results (associative by group path)
declare -A passed_tests
declare -A failed_tests
declare -a group_order

# Function to get relative path from TESTS_DIR
get_group_name() {
    local dir_path="$1"
    local rel_path="${dir_path#$TESTS_DIR}"
    rel_path="${rel_path#/}"
    if [[ -z "$rel_path" ]]; then
        echo "general"
    else
        echo "$rel_path"
    fi
}

# Function to get cache file path for a specific JS file
get_node_cache_file() {
    local js_file="$1"
    local js_basename=$(basename "$js_file" .js)
    local js_dir=$(dirname "$js_file")
    local rel_path="${js_dir#$TESTS_DIR}"
    rel_path="${rel_path#/}"
    
    if [[ -z "$rel_path" ]]; then
        echo "${NODE_CACHE_DIR}/${js_basename}.sh"
    else
        local flat_path="${rel_path//\//_}"
        mkdir -p "${NODE_CACHE_DIR}/${flat_path}" 2>/dev/null || true
        echo "${NODE_CACHE_DIR}/${flat_path}/${js_basename}.sh"
    fi
}

# Function to create a temporary node wrapper that returns cached output
create_node_wrapper() {
    local js_file="$1"
    local cache_file="$2"
    local wrapper_script=$(mktemp)
    
    cat > "$wrapper_script" << WRAPPEREOF
#!/usr/bin/env bash
# Node wrapper for cached execution
# Returns pre-captured output for: ${js_file}

if echo "\$@" | grep -q "$(basename "${js_file}")"; then
    # Execute the cached .sh file to get the output
    bash "${cache_file}"
    exit \$?
else
    # If it's a different file, use real node (if available)
    if command -v node &> /dev/null; then
        \$(command -v node) "\$@"
    else
        echo "Error: node not available and no cache for this file" >&2
        exit 1
    fi
fi
WRAPPEREOF

    chmod +x "$wrapper_script"
    echo "$wrapper_script"
}

# Function to save node output as executable .sh file
save_node_output() {
    local js_file="$1"
    local cache_file="$2"
    
    # If in --save mode (not --saveforce) and the cache file already exists, skip it
    if [[ "$SAVEFORCE_MODE" != true ]] && [[ -f "$cache_file" ]]; then
        echo -e "${DIM}Cache file already exists, skipping:${RESET} ${cache_file}"
        return
    fi
    
    # Capture the actual output from running node on the JS file
    local node_output
    node_output=$(node "$js_file" 2>&1) || true
    local node_exit=$?
    
    # Create an executable .sh file that outputs the captured content
    {
        echo "#!/usr/bin/env bash"
        echo "# Cached node output - Generated by runtest.sh --save"
        echo "# Original file: ${js_file}"
        echo "# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo ""
        echo "# This file contains pre-captured node output"
        echo "# Execute it to get the same output as running: node ${js_file}"
        echo ""
        echo "cat << 'NODEOUTPUT'"
        echo "$node_output"
        echo "NODEOUTPUT"
        echo ""
        echo "exit ${node_exit}"
    } > "$cache_file"
    
    chmod +x "$cache_file"
    
    if [[ "$SAVEFORCE_MODE" == true ]]; then
        echo -e "${GREEN}✓ Node output saved (overwritten):${RESET} ${cache_file}"
    else
        echo -e "${GREEN}✓ Node output saved:${RESET} ${cache_file}"
    fi
}

# Function to process a test directory recursively
process_test_directory() {
    local dir_path="$1"
    local group_name="$2"
    
    local has_content=false
    
    # Enter the test directory
    cd "$dir_path"
    
    # Get all .sh files sorted numerically
    sh_files=$(ls -1v *.sh 2>/dev/null | grep -E '^[0-9]+\.sh$' || true)
    
    if [[ -n "$sh_files" ]]; then
        has_content=true
        
        if [[ "$group_name" != "general" ]] || [[ -n "$sh_files" ]]; then
            if [[ "$SAVE_MODE" == true ]]; then
                echo -e "${BG_BLUE}${WHITE}${BOLD} Processing test group: ${group_name} ${RESET} ${YELLOW}[SAVE MODE]${RESET}"
            elif [[ "$SAVEFORCE_MODE" == true ]]; then
                echo -e "${BG_BLUE}${WHITE}${BOLD} Processing test group: ${group_name} ${RESET} ${YELLOW}[SAVE FORCE MODE]${RESET}"
            elif [[ "$CACHED_MODE" == true ]]; then
                echo -e "${BG_BLUE}${WHITE}${BOLD} Processing test group: ${group_name} ${RESET} ${CYAN}[CACHED MODE]${RESET}"
            else
                echo -e "${BG_BLUE}${WHITE}${BOLD} Processing test group: ${group_name} ${RESET}"
            fi
            echo -e "${DIM}Directory: ${dir_path}${RESET}"
            echo ""
        fi
        
        # Execute generators (skip in cached mode if not needed, but run if JS files don't exist)
        if [[ "$CACHED_MODE" == false ]] || [[ ! -f "$(ls -1v *.js 2>/dev/null | head -1)" ]]; then
            if [[ "$CACHED_MODE" == true ]]; then
                echo -e "${CYAN}${BOLD}JS files not found, executing generators even in cached mode${RESET}"
            fi
            echo -e "${CYAN}${BOLD}Found test generator scripts:${RESET}"
            echo "$sh_files"
            echo ""
            
            # Execute each .sh file to generate corresponding .js files
            for sh_file in $sh_files; do
                echo -e "${MAGENTA}Executing generator:${RESET} ${BOLD}$sh_file${RESET}"
                bash "$sh_file"
                
                test_num="${sh_file%.sh}"
                
                if [[ ! -f "${test_num}.js" ]]; then
                    echo -e "${YELLOW}${BOLD}Warning:${RESET} ${test_num}.js was not generated by ${sh_file}"
                    log_error "Generator ${sh_file} did not produce ${test_num}.js" "${group_name}/${test_num}"
                else
                    echo -e "${GREEN}Generated:${RESET} ${test_num}.js"
                fi
                echo ""
            done
        fi
        
        # Get all generated .js files sorted numerically
        js_files=$(ls -1v *.js 2>/dev/null | grep -E '^[0-9]+\.js$' || true)
        
        if [[ -n "$js_files" ]]; then
            if [[ "$CACHED_MODE" == false ]]; then
                echo -e "${CYAN}${BOLD}Found test files:${RESET}"
                echo "$js_files"
                echo ""
            fi
            
            # Execute dual.sh for each .js file in order
            for js_file in $js_files; do
                test_path="${dir_path}/${js_file}"
                test_num="${js_file%.js}"
                
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                
                if [[ "$CACHED_MODE" == true ]]; then
                    echo -e "${WHITE}${BOLD}Running test ${test_num} [${group_name}]:${RESET} dual.sh ${js_file} ${CYAN}(cached)${RESET}"
                elif [[ "$SAVE_MODE" == true ]]; then
                    echo -e "${WHITE}${BOLD}Running test ${test_num} [${group_name}]:${RESET} dual.sh ${js_file} ${YELLOW}(saving)${RESET}"
                elif [[ "$SAVEFORCE_MODE" == true ]]; then
                    echo -e "${WHITE}${BOLD}Running test ${test_num} [${group_name}]:${RESET} dual.sh ${js_file} ${YELLOW}(saving force)${RESET}"
                else
                    echo -e "${WHITE}${BOLD}Running test ${test_num} [${group_name}]:${RESET} dual.sh ${js_file}"
                fi
                
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                
                if [[ "$CACHED_MODE" == true ]]; then
                    # Get the cache file for this JS file
                    local node_cache_file=$(get_node_cache_file "$test_path")
                    
                    if [[ ! -f "$node_cache_file" ]]; then
                        echo -e "${BG_RED}${WHITE}${BOLD} ✗ Cache file not found: ${node_cache_file} ${RESET}"
                        echo -e "${YELLOW}Run with --save first to generate cache files${RESET}"
                        if [[ -z "${failed_tests[$group_name]}" ]]; then
                            failed_tests["$group_name"]="${test_num}"
                        else
                            failed_tests["$group_name"]="${failed_tests[$group_name]} ${test_num}"
                        fi
                        log_error "Cache file not found: ${node_cache_file}" "${group_name}/${test_num}"
                    else
                        # Create a temporary node wrapper that returns cached output
                        local node_wrapper=$(create_node_wrapper "$test_path" "$node_cache_file")
                        
                        # Run dual.sh with PATH modified to use our node wrapper
                        local wrapper_dir=$(dirname "$node_wrapper")
                        local original_path="$PATH"
                        export PATH="${wrapper_dir}:${PATH}"
                        
                        # Rename our wrapper to 'node' temporarily
                        mv "$node_wrapper" "${wrapper_dir}/node"
                        
                        if bash "$DUAL_SCRIPT" "$test_path"; then
                            exit_code=0
                            echo -e "${BG_GREEN}${WHITE}${BOLD} ✓ Test ${test_num} completed successfully (cached) ${RESET}"
                            if [[ -z "${passed_tests[$group_name]}" ]]; then
                                passed_tests["$group_name"]="${test_num}"
                            else
                                passed_tests["$group_name"]="${passed_tests[$group_name]} ${test_num}"
                            fi
                        else
                            exit_code=$?
                            echo -e "${BG_RED}${WHITE}${BOLD} ✗ Test ${test_num} failed with exit code: ${exit_code} ${RESET}"
                            if [[ -z "${failed_tests[$group_name]}" ]]; then
                                failed_tests["$group_name"]="${test_num}"
                            else
                                failed_tests["$group_name"]="${failed_tests[$group_name]} ${test_num}"
                            fi
                            
                            # Capture the diff output from the failed test
                            local diff_output
                            diff_output=$(bash "$DUAL_SCRIPT" "$test_path" 2>&1 || true)
                            
                            log_error "Test failed with exit code: ${exit_code}" "${group_name}/${test_num}"
                            rerun_verbose_on_error "$test_path" "${group_name}/${test_num}" "$exit_code" "$diff_output"
                        fi
                        
                        # Restore original PATH and cleanup
                        export PATH="$original_path"
                        rm -f "${wrapper_dir}/node"
                    fi
                else
                    # Normal mode or save mode: execute dual.sh
                    if bash "$DUAL_SCRIPT" "$test_path"; then
                        exit_code=0
                        echo -e "${BG_GREEN}${WHITE}${BOLD} ✓ Test ${test_num} completed successfully ${RESET}"
                        if [[ -z "${passed_tests[$group_name]}" ]]; then
                            passed_tests["$group_name"]="${test_num}"
                        else
                            passed_tests["$group_name"]="${passed_tests[$group_name]} ${test_num}"
                        fi
                    else
                        exit_code=$?
                        echo -e "${BG_RED}${WHITE}${BOLD} ✗ Test ${test_num} failed with exit code: ${exit_code} ${RESET}"
                        if [[ -z "${failed_tests[$group_name]}" ]]; then
                            failed_tests["$group_name"]="${test_num}"
                        else
                            failed_tests["$group_name"]="${failed_tests[$group_name]} ${test_num}"
                        fi
                        
                        # Capture the diff output from the failed test
                        local diff_output
                        diff_output=$(bash "$DUAL_SCRIPT" "$test_path" 2>&1 || true)
                        
                        log_error "Test failed with exit code: ${exit_code}" "${group_name}/${test_num}"
                        rerun_verbose_on_error "$test_path" "${group_name}/${test_num}" "$exit_code" "$diff_output"
                    fi
                    
                    # Save node output if in save mode
                    if [[ "$SAVE_MODE" == true ]] || [[ "$SAVEFORCE_MODE" == true ]]; then
                        local node_cache_file=$(get_node_cache_file "$test_path")
                        echo -e "${YELLOW}Saving node output to:${RESET} ${node_cache_file}"
                        save_node_output "$test_path" "$node_cache_file"
                    fi
                fi
                echo ""
            done
        fi
    fi
    
    # Now process subdirectories recursively
    if [[ -d "$dir_path" ]]; then
        # Find all immediate subdirectories, sorted alphabetically
        local subdirs=$(find "$dir_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
        
        if [[ -n "$subdirs" ]]; then
            for subdir in $subdirs; do
                local sub_group_name=$(get_group_name "$subdir")
                process_test_directory "$subdir" "$sub_group_name"
            done
        fi
    fi
    
    # Only add to group_order if this group actually had tests
    if [[ -n "${passed_tests[$group_name]}" ]] || [[ -n "${failed_tests[$group_name]}" ]]; then
        group_order+=("$group_name")
    fi
    
    # Return to original directory
    cd "$SCRIPT_DIR"
}

# Display mode information
echo -e "${BG_CYAN}${WHITE}${BOLD} Starting test generation and execution phase ${RESET}"
if [[ "$SAVE_MODE" == true ]]; then
    echo -e "${YELLOW}${BOLD}Mode: SAVE${RESET} - Node outputs will be cached to ${NODE_CACHE_DIR}"
elif [[ "$SAVEFORCE_MODE" == true ]]; then
    echo -e "${YELLOW}${BOLD}Mode: SAVE FORCE${RESET} - Node outputs will be cached (overwriting existing) to ${NODE_CACHE_DIR}"
elif [[ "$CACHED_MODE" == true ]]; then
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${CYAN}${BOLD}Mode: AUTO (CACHED)${RESET} - Node.js not available, using cache from ${NODE_CACHE_DIR}"
    else
        echo -e "${CYAN}${BOLD}Mode: CACHED${RESET} - Using pre-saved outputs from ${NODE_CACHE_DIR}"
    fi
else
    echo -e "${GREEN}${BOLD}Mode: NORMAL${RESET} - Using Node.js for execution"
fi

if [[ "$ERROR_MODE" == true ]]; then
    echo -e "${RED}${BOLD}Error Logging: ENABLED${RESET} - Errors will be saved to: $ERROR_LOG"
fi
echo ""

# Record overall start time
overall_start=$(date +%s%N)

# Start recursive processing from the root tests directory
process_test_directory "$TESTS_DIR" "general"

# Record overall end time and calculate elapsed
overall_end=$(date +%s%N)
elapsed_ns=$(( overall_end - overall_start ))

echo -e "${BG_CYAN}${WHITE}${BOLD} All tests completed ${RESET}"
echo ""

# Print final summary grouped by test group
echo -e "${BG_MAGENTA}${WHITE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BG_MAGENTA}${WHITE}${BOLD}║              TEST EXECUTION SUMMARY              ║${RESET}"
echo -e "${BG_MAGENTA}${WHITE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""

total_passed=0
total_failed=0
total_tests=0

# Print results only for groups that have test results
if [[ ${#group_order[@]} -gt 0 ]]; then
    for group in "${group_order[@]}"; do
        echo -e "${CYAN}${BOLD}┏━━━ Group: ${group} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET}"
        
        # Parse passed tests for this group
        if [[ -n "${passed_tests[$group]}" ]]; then
            passed_array=(${passed_tests[$group]})
            passed_count=${#passed_array[@]}
            total_passed=$((total_passed + passed_count))
            echo -e "${GREEN}${BOLD}✓ PASSED (${passed_count}):${RESET}"
            for test in "${passed_array[@]}"; do
                echo -e "  ${GREEN}•${RESET} Test ${test}"
            done
        else
            echo -e "${GREEN}${BOLD}✓ PASSED (0):${RESET}"
        fi
        
        # Parse failed tests for this group
        if [[ -n "${failed_tests[$group]}" ]]; then
            failed_array=(${failed_tests[$group]})
            failed_count=${#failed_array[@]}
            total_failed=$((total_failed + failed_count))
            echo -e "${RED}${BOLD}✗ FAILED (${failed_count}):${RESET}"
            for test in "${failed_array[@]}"; do
                echo -e "  ${RED}•${RESET} Test ${test}"
            done
        else
            echo -e "${RED}${BOLD}✗ FAILED (0):${RESET}"
        fi
        
        echo ""
    done
else
    echo -e "${YELLOW}${BOLD}No test results to display${RESET}"
    echo ""
fi

# Calculate totals
total_tests=$((total_passed + total_failed))

# Print overall statistics with colors
echo -e "${MAGENTA}${BOLD}┏━━━ Overall Statistics ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET}"
echo -e "${BOLD}Total groups with tests:${RESET} ${#group_order[@]}"
echo -e "${BOLD}Total tests:${RESET} ${total_tests}"
echo -e "${GREEN}${BOLD}Total passed:${RESET} ${total_passed}"
echo -e "${RED}${BOLD}Total failed:${RESET} ${total_failed}"

# Calculate and display success rate with color coding
if [[ $total_tests -gt 0 ]]; then
    success_rate=$(( (total_passed * 100) / total_tests ))
    
    # Color code the success rate
    if [[ $success_rate -eq 100 ]]; then
        echo -e "Success rate: ${BG_GREEN}${WHITE}${BOLD} ${success_rate}% ${RESET} (${total_passed}/${total_tests} tests passed)"
    elif [[ $success_rate -ge 75 ]]; then
        echo -e "Success rate: ${YELLOW}${BOLD}${success_rate}%${RESET} (${total_passed}/${total_tests} tests passed)"
    else
        echo -e "Success rate: ${RED}${BOLD}${success_rate}%${RESET} (${total_passed}/${total_tests} tests passed)"
    fi
else
    echo -e "Success rate: ${YELLOW}${BOLD}N/A${RESET} (no tests found)"
fi

# Format and display total execution time
if (( elapsed_ns >= 1000000000 )); then
    elapsed_s=$(echo "scale=3; $elapsed_ns / 1000000000" | bc)
    echo -e "${BOLD}Total execution time:${RESET} ${elapsed_s}s"
elif (( elapsed_ns >= 1000000 )); then
    elapsed_ms=$(echo "scale=2; $elapsed_ns / 1000000" | bc)
    echo -e "${BOLD}Total execution time:${RESET} ${elapsed_ms}ms"
else
    elapsed_us=$(echo "scale=2; $elapsed_ns / 1000" | bc)
    echo -e "${BOLD}Total execution time:${RESET} ${elapsed_us}µs"
fi

# Display execution mode summary
echo ""
if [[ "$SAVE_MODE" == true ]]; then
    echo -e "${YELLOW}${BOLD}Node outputs cached as .sh files in:${RESET} ${NODE_CACHE_DIR}"
    echo -e "${DIM}Cache can be used on systems without Node.js${RESET}"
elif [[ "$SAVEFORCE_MODE" == true ]]; then
    echo -e "${YELLOW}${BOLD}Node outputs forcefully cached as .sh files in:${RESET} ${NODE_CACHE_DIR}"
    echo -e "${DIM}Cache can be used on systems without Node.js${RESET}"
elif [[ "$CACHED_MODE" == true ]]; then
    echo -e "${CYAN}${BOLD}Execution mode: CACHED${RESET} - Node.js was not required"
    echo -e "${DIM}To update cache, run with --save on a system with Node.js${RESET}"
else
    echo -e "${GREEN}${BOLD}Execution mode: NORMAL${RESET} - Node.js was used for all tests"
    echo -e "${DIM}Use --save to create cache for Node.js-less systems${RESET}"
fi

# Display error log information if in error mode
if [[ "$ERROR_MODE" == true ]]; then
    if [[ $total_failed -gt 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}✗ Errors detected!${RESET}"
        echo -e "${RED}${BOLD}Error log saved to:${RESET} $ERROR_LOG"
        echo -e "${YELLOW}The error log contains verbose outputs for each failed test${RESET}"
    else
        echo ""
        echo -e "${GREEN}${BOLD}✓ No errors detected!${RESET}"
        echo -e "${GREEN}${BOLD}Error log is empty:${RESET} $ERROR_LOG"
    fi
fi

# Exit with non-zero if any tests failed
if [[ $total_failed -gt 0 ]]; then
    exit 1
fi
