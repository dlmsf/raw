#!/bin/bash

# Raw.sh - Main build script with conditional compilation (silent mode)

# ============================================
# CONFIGURATION FILE MANAGEMENT (NEW)
# ============================================
CONFIG_FILE="$SCRIPT_DIR/config.txt"  # Will be set after SCRIPT_DIR is defined

# Function: Load configuration from config.txt
# Format: Each line is "key=value"
load_config() {
    CONFIG_DEV_MODE="false"  # Default value
    
    if [ -f "$CONFIG_FILE" ]; then
        while IFS='=' read -r key value; do
            case "$key" in
                "dev_mode") CONFIG_DEV_MODE="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

# Function: Save configuration to config.txt
save_config() {
    # Preserve existing config and update only the changed values
    local temp_file="${CONFIG_FILE}.tmp"
    local dev_mode_written=false
    
    # Copy existing config if it exists
    if [ -f "$CONFIG_FILE" ]; then
        while IFS='=' read -r key value; do
            if [ "$key" = "dev_mode" ]; then
                echo "dev_mode=$CONFIG_DEV_MODE" >> "$temp_file"
                dev_mode_written=true
            else
                echo "$key=$value" >> "$temp_file"
            fi
        done < "$CONFIG_FILE"
    fi
    
    # Add dev_mode if not already written
    if [ "$dev_mode_written" = false ]; then
        echo "dev_mode=$CONFIG_DEV_MODE" >> "$temp_file"
    fi
    
    mv "$temp_file" "$CONFIG_FILE"
}

# Function: Toggle dev mode
toggle_dev_mode() {
    load_config
    if [ "$CONFIG_DEV_MODE" = "true" ]; then
        CONFIG_DEV_MODE="false"
        echo -e "${YELLOW}Dev mode disabled. Raw.sh without arguments will show usage.${NC}"
    else
        CONFIG_DEV_MODE="true"
        echo -e "${GREEN}Dev mode enabled. Raw.sh without arguments will launch CLI.${NC}"
    fi
    save_config
}

# ============================================
# ANSI STRIPPING FUNCTION
# ============================================
strip_ansi_codes() {
    local input="$1"
    
    # Use sed with simpler patterns that work on both GNU and BusyBox sed
    echo "$input" | sed -E 's/\x1b\[[0-9;]*[mK]//g; s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)//g; s/\x1b[()][AB012]//g; s/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b[^a-zA-Z]*[a-zA-Z]//g'
}

# ============================================
# SAVE CALLER'S DIRECTORY AND RESOLVE JS FILE FIRST
# ============================================
CALLER_DIR="$(pwd)"  # Save where the script was called from

# Check for special flags FIRST before processing JS file
SPECIAL_MODE=""
FORCE_LOG_MODE="false"  # New flag for --log (only for normal JS execution)
VERBOSE_MODE="false"    # New flag for --verbose (enables log mode and passes --verbose to tree/build.sh)
TOOL_MODE="false"       # New flag for --tool
TOOL_COMMAND=""         # Store the tool command
TOOL_ARGS=""           # Store tool arguments
ASM_MODE="false"        # New flag for --asm
ASM_ONLY_MODE="false"   # Flag for --asm without JS file
BIN_OUTPUT_MODE="false" # Flag for --bin output generation with JS processing
BIN_OUTPUT_NAME=""      # Store the output name for --bin mode
CLI_MODE="false"        # New flag for --cli

if [ $# -gt 0 ]; then
    if [ "$1" = "--test" ] || [ "$1" = "--reset" ]; then
        SPECIAL_MODE="$1"
        shift  # Remove the flag from arguments
    elif [ "$1" = "--dev" ]; then
        # NEW: Toggle dev mode
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        CONFIG_FILE="$SCRIPT_DIR/config.txt"
        load_config
        toggle_dev_mode
        exit 0
    elif [ "$1" = "--cli" ]; then
        CLI_MODE="true"
        shift  # Remove --cli flag
    elif [ "$1" = "--tool" ]; then
        TOOL_MODE="true"
        shift  # Remove --tool flag
        
        # Check if a command was provided
        if [ $# -gt 0 ]; then
            TOOL_COMMAND="$1"
            shift  # Remove command name
            
            # Store remaining arguments as tool args
            TOOL_ARGS="$@"
        fi
    elif [ "$1" = "--tools" ] || [ "$1" = "--stools" ] || [ "$1" = "--stool" ]; then
        # Support both --tools (full) and --stools/--stool (compact)
        if [ "$1" = "--stools" ] || [ "$1" = "--stool" ]; then
            SPECIAL_MODE="--stools"
        else
            SPECIAL_MODE="--tools"
        fi
        shift
    elif [ "$1" = "--asm" ]; then
        ASM_MODE="true"
        shift  # Remove --asm flag
        
        # Check if there's a JS file after --asm
        if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
            # There's a JS file - will process normally and then copy asm
            ASM_ONLY_MODE="false"
        else
            # No JS file - just copy the asm file
            ASM_ONLY_MODE="true"
        fi
    elif [ "$1" = "--version" ] || [ "$1" = "--v" ] || [ "$1" = "-v" ] || [ "$1" = "-version" ]; then
        # Get script's own directory to read package.json
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        # Read version from package.json
        if [ -f "$SCRIPT_DIR/package.json" ]; then
            VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCRIPT_DIR/package.json" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
            if [ -n "$VERSION" ]; then
                echo "RawJS - $VERSION"
            else
                echo "RawJS - version unknown"
            fi
        else
            echo "RawJS - version unknown"
        fi
        exit 0
    elif [ "$1" = "--verbose" ]; then
        # Enable verbose mode (enables log mode and passes --verbose to tree/build.sh)
        VERBOSE_MODE="true"
        FORCE_LOG_MODE="true"
        shift  # Remove --verbose flag
    elif [ "$1" = "--bin" ]; then
        # Check if --bin is being used as a tool command (no JS file follows)
        shift  # Remove --bin flag
        
        # Check if there are more arguments
        if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
            # Check if next argument looks like a JS file
            if [[ "$1" == *.js ]] || [[ "$1" == *.JS ]]; then
                # It's a JS file - use --bin mode for JS processing
                BIN_OUTPUT_MODE="true"
                # JS file will be processed in the JS file section below
            elif [ -f "$CALLER_DIR/$1" ] && [[ "$1" == *.asm || "$1" == *.ASM ]]; then
                # It's an existing .asm file - use as tool command
                TOOL_MODE="true"
                TOOL_COMMAND="bin"
                TOOL_ARGS="$@"
                # Reset the arguments to prevent further processing
                set -- "$@"
            else
                # Could be an output name for --bin mode with JS processing
                # Check if the next argument after this might be a JS file
                if [ $# -gt 1 ] && ([[ "$2" == *.js ]] || [[ "$2" == *.JS ]]); then
                    BIN_OUTPUT_MODE="true"
                    BIN_OUTPUT_NAME="$1"
                    shift  # Remove output name
                    # JS file will be processed in the JS file section below
                else
                    # Treat as tool command with arguments
                    TOOL_MODE="true"
                    TOOL_COMMAND="bin"
                    TOOL_ARGS="$1 $@"
                    shift
                    set -- "$@"
                fi
            fi
        else
            # No arguments after --bin, or next is a flag - treat as tool command
            TOOL_MODE="true"
            TOOL_COMMAND="bin"
            TOOL_ARGS="$@"
            # Reset the arguments to prevent further processing
            set -- "$@"
        fi
    else
        # NEW: Check if first argument is a tool name (starts with -- and not a known flag)
        if [[ "$1" == --* ]] && [ "$1" != "--log" ] && [ "$1" != "--verbose" ] && [ "$1" != "--asm" ] && [ "$1" != "--bin" ] && [ "$1" != "--test" ] && [ "$1" != "--reset" ] && [ "$1" != "--version" ] && [ "$1" != "--v" ] && [ "$1" != "-v" ] && [ "$1" != "-version" ] && [ "$1" != "--tools" ] && [ "$1" != "--stools" ] && [ "$1" != "--stool" ] && [ "$1" != "--cli" ] && [ "$1" != "--dev" ]; then
            # Extract tool name by removing leading --
            TOOL_COMMAND="${1#--}"
            TOOL_MODE="true"
            shift  # Remove the tool flag
            
            # Store remaining arguments as tool args
            TOOL_ARGS="$@"
        fi
    fi
fi

# Only check for --log and --verbose if we're NOT in a special mode or tool mode
if [ -z "$SPECIAL_MODE" ] && [ "$TOOL_MODE" = "false" ] && [ "$CLI_MODE" = "false" ] && [ $# -gt 0 ]; then
    if [ "$1" = "--verbose" ]; then
        # Enable verbose mode (enables log mode and passes --verbose to tree/build.sh)
        VERBOSE_MODE="true"
        FORCE_LOG_MODE="true"
        shift  # Remove the flag from arguments
    fi
    if [ "$1" = "--log" ]; then
        FORCE_LOG_MODE="true"
        shift  # Remove the flag from arguments
    fi
fi

# Process JS file argument BEFORE changing directories (only if not in tool mode and not asm-only mode and not cli mode)
JS_FILE=""
JS_ARGS=""
if [ "$TOOL_MODE" = "false" ] && [ "$CLI_MODE" = "false" ] && [ $# -gt 0 ] && [ -z "$SPECIAL_MODE" ] && [ "$ASM_ONLY_MODE" = "false" ]; then
    # Check if BIN_OUTPUT_MODE is already set (from --bin parsing above)
    if [ "$BIN_OUTPUT_MODE" = "false" ]; then
        # Check for --bin flag before JS file (in case it wasn't caught above)
        if [ "$1" = "--bin" ]; then
            BIN_OUTPUT_MODE="true"
            shift  # Remove --bin flag
            
            # Check if next argument is an output name
            if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
                # Check if it looks like an output name (not a JS file)
                if [[ "$1" != *.js ]] && [[ "$1" != *.JS ]]; then
                    BIN_OUTPUT_NAME="$1"
                    shift
                fi
            fi
        fi
    fi
    
    # Now process JS file if arguments remain
    if [ $# -gt 0 ]; then
        # Resolve JS file path relative to caller's directory
        if [[ "$1" = /* ]]; then
            # Absolute path
            JS_FILE="$1"
        else
            # Relative path - resolve from caller's directory
            JS_FILE="$CALLER_DIR/$1"
        fi
        shift
        JS_ARGS="$@"
    fi
fi

# ============================================
# GET SCRIPT'S OWN DIRECTORY (not caller's directory)
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"  # Change to script's directory to ensure consistent paths

# NOW load configuration
CONFIG_FILE="$SCRIPT_DIR/config.txt"
load_config

# Now JS_FILE contains the absolute path to the JS file from caller's perspective
# The rest of the script continues exactly as before...

# ============================================
# VERBOSITY CONTROL FOR DEV COMPILATION STEP
# ============================================
# Set to "true" to enable compilation error/output (for debugging)
# Set to "false" for complete silent operation (default for production)
# 
# When false: NO output at all from compilation step (not even errors)
# When true: Shows all compilation details including errors
# ============================================
VERBOSE_DEV="${VERBOSE_DEV:-false}"  # Default: completely silent

# ============================================
# GLOBAL EXECUTION PATH CONFIGURATION
# ============================================
# Controls where to look for files to execute
# "dev" - uses ./dev directory (default, contains compiled binaries)
# "source" - uses ./._ directory (contains source files, will be compiled on-demand)
# ============================================
EXECUTION_SOURCE="${EXECUTION_SOURCE:-dev}"  # Default: use compiled binaries from ./dev

# ============================================
# TOOL GROUPS CONFIGURATION
# ============================================
# Define tool groups, their colors, and tool order
# Groups are displayed in the order defined here
# Tools not assigned to any group go to "General" group
# 
# COLOR OPTIONS (use ANSI color codes without \033[ or \e[):
#   Black: 0;30, Dark Gray: 1;30
#   Red: 0;31, Light Red: 1;31
#   Green: 0;32, Light Green: 1;32
#   Brown/Orange: 0;33, Yellow: 1;33
#   Blue: 0;34, Light Blue: 1;34
#   Purple: 0;35, Light Purple: 1;35
#   Cyan: 0;36, Light Cyan: 1;36
#   Light Gray: 0;37, White: 1;37
#
# TO ADD A NEW GROUP:
#   1. Add a new array TOOL_GROUP_<groupname>_TOOLS with tools in desired order
#   2. Add the group name to TOOL_GROUPS_ORDER array
#   3. Define TOOL_GROUP_<groupname>_COLOR with the color code
#
# TO ADD A TOOL TO EXISTING GROUP:
#   1. Add tool name to the group's TOOL_GROUP_<groupname>_TOOLS array
#   2. Add tool function (tool_<toolname>) in TOOL COMMAND HANDLERS section
#   3. Add working directory config in get_tool_working_dir() function
#
# TO CHANGE ORDER OF GROUPS:
#   - Modify TOOL_GROUPS_ORDER array
#
# TO CHANGE ORDER OF TOOLS IN A GROUP:
#   - Modify the group's TOOL_GROUP_<groupname>_TOOLS array
# ============================================

# Define the order of groups (first group appears first)
TOOL_GROUPS_ORDER=(
    "Main"
)

# Define tools for "Main" group (in desired order)
TOOL_GROUP_Main_TOOLS=(
    "min"
    "polish"
    "arch"
    "build"
    "bin"
)

# Define color for "Main" group
TOOL_GROUP_Main_COLOR="1;36"  # Light Cyan

# Define color for default "General" group
TOOL_GROUP_General_COLOR="1;33"  # Yellow

# ============================================
# TOOL WORKING DIRECTORY CONFIGURATION
# ============================================
# WORKING DIRECTORY TYPES:
#   "global"  - Execute from script's own directory ($SCRIPT_DIR)
#   "caller"  - Execute from user's current working directory (where command was called)
#   "file"    - Execute from the directory containing the executed file itself
#
# Add your tool commands here to configure their working directory
# ============================================
get_tool_working_dir() {
    local tool_name="$1"
    case "$tool_name" in
        # =====================================================================
        # TOOL COMMANDS - Configure working directory for each tool
        # =====================================================================
        "dual")     echo "file" ;;
        "info")     echo "caller" ;;
        "min")     echo "caller" ;;
        "polish")     echo "caller" ;;
        "arch")     echo "caller" ;;
        "chain")     echo "caller" ;;
        "build")     echo "caller" ;;
        "bin")     echo "caller" ;;
        "emb")     echo "caller" ;;
        "testcheck")     echo "caller" ;;
        "clean")     echo "caller" ;;
        "jsclean")     echo "caller" ;;
        
        # =====================================================================
        # ADD YOUR TOOLS HERE with their working directory
        # =====================================================================
        # "compile")  echo "global" ;;
        # "process")  echo "caller" ;;
        # "analyze")  echo "file" ;;
        
        # =====================================================================
        # DEFAULT - uses "global" if not specified
        # =====================================================================
        *) echo "global" ;;
    esac
}

# Colors for output (only used when VERBOSE_DEV=true)
if [ "$VERBOSE_DEV" = "true" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

# Silent logging function for dev step
dev_log() {
    if [ "$VERBOSE_DEV" = "true" ]; then
        echo -e "$@"
    fi
}

# Error logging for dev step (only shows if VERBOSE_DEV=true)
dev_error() {
    if [ "$VERBOSE_DEV" = "true" ]; then
        echo -e "$@" >&2
    fi
}

# Function: Resolve file path based on EXECUTION_SOURCE
# This is for execution files (scripts, asm, binaries) NOT for the JS file
resolve_file_path() {
    local file_path="$1"
    file_path="${file_path#./}"
    case "$EXECUTION_SOURCE" in
        "source") echo "$SCRIPT_DIR/._/$file_path" ;;
        "dev"|*)  echo "$SCRIPT_DIR/dev/$file_path" ;;
    esac
}

# Function: Execute a file using the unified basm.sh
# Usage: execute_file <mode> <file_path> [working_dir_type] [additional_args...]
#   mode: normal, silent, log
#   file_path: path relative to dev or ._ directory
#   working_dir_type: "caller", "file", or "global" (optional, defaults to "global")
execute_file() {
    local mode="$1"
    local file_path="$2"
    shift 2
    
    # Check if next argument is a working directory type
    local working_dir_type="global"
    if [ "$1" = "caller" ] || [ "$1" = "file" ] || [ "$1" = "global" ]; then
        working_dir_type="$1"
        shift
    fi
    
    local additional_args="$@"
    
    # Override mode if FORCE_LOG_MODE is true (only affects normal JS execution)
    if [ "$FORCE_LOG_MODE" = "true" ]; then
        mode="log"
    fi
    
    # Path to the single unified basm.sh
    local basm_script="$SCRIPT_DIR/dev/basm/basm.sh"
    
    # Check if basm script exists
    if [ ! -f "$basm_script" ]; then
        echo -e "${RED}Error: basm script not found at $basm_script${NC}" >&2
        return 1
    fi
    
    # Make sure basm script is executable
    chmod +x "$basm_script" 2>/dev/null
    
    # Resolve the full path to the file
    local full_path=$(resolve_file_path "$file_path")
    
    # Check if file exists
    if [ ! -f "$full_path" ]; then
        echo -e "${RED}Error: File not found at $full_path${NC}" >&2
        return 1
    fi
    
    # Determine the working directory based on type
    local working_dir="$SCRIPT_DIR"  # Default: global (script's directory)
    case "$working_dir_type" in
        "caller")
            working_dir="$CALLER_DIR"  # Use caller's directory
            ;;
        "file")
            working_dir="$(dirname "$full_path")"  # Use file's directory
            ;;
        "global"|*)
            working_dir="$SCRIPT_DIR"  # Use script's directory
            ;;
    esac
    
    # Execute with appropriate mode and working directory
    case "$mode" in
        "silent")
            if [[ "$full_path" == *.sh ]]; then
                (cd "$working_dir" && bash "$full_path" $additional_args >/dev/null 2>&1)
            else
                (cd "$working_dir" && "$basm_script" --silent "$full_path" $additional_args)
            fi
            ;;
        "log")
            if [[ "$full_path" == *.sh ]]; then
                (cd "$working_dir" && bash "$full_path" $additional_args)
            else
                (cd "$working_dir" && "$basm_script" --log "$full_path" $additional_args)
            fi
            ;;
        "normal"|*)
            if [[ "$full_path" == *.sh ]]; then
                (cd "$working_dir" && bash "$full_path" $additional_args)
            else
                (cd "$working_dir" && "$basm_script" "$full_path" $additional_args)
            fi
            ;;
    esac
    
    return $?
}

# Function: Execute a sequence of files
# Usage: execute_sequence <mode> <file1> [file2] [file3...]
execute_sequence() {
    local mode="$1"
    shift
    local files=("$@")
    local success_count=0
    local fail_count=0
    
    # Override mode if FORCE_LOG_MODE is true (only affects normal JS execution)
    if [ "$FORCE_LOG_MODE" = "true" ]; then
        mode="log"
    fi
    
    echo -e "${BLUE}Executing sequence in ${mode} mode...${NC}"
    
    for file in "${files[@]}"; do
        echo -e "${YELLOW}Executing: $file${NC}"
        
        if execute_file "$mode" "$file"; then
            echo -e "${GREEN}✓ Successfully executed: $file${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ Failed to execute: $file${NC}"
            ((fail_count++))
        fi
        echo ""
    done
    
    echo -e "${BLUE}=== Sequence Summary ===${NC}"
    echo -e "${GREEN}Successful: $success_count${NC}"
    echo -e "${RED}Failed: $fail_count${NC}"
    
    return $fail_count
}

# ============================================
# FILE MANIPULATION FUNCTIONS
# ============================================

# Minimalistic move file
# Usage: mv_file "source" "destination"
mv_file() {
    mv "$1" "$2" 2>/dev/null
}

# Minimalistic delete file  
# Usage: rm_file "file_path"
rm_file() {
    rm -f "$1" 2>/dev/null
}

# Minimalistic delete directory
# Usage: rm_dir "directory_path"
rm_dir() {
    rm -rf "$1" 2>/dev/null
}

# Minimalistic copy file (preserves original)
# Usage: cp_file "source" "destination"
cp_file() {
    cp "$1" "$2" 2>/dev/null
}

# ============================================
# EXECUTION TIME TRACKING (for --log mode)
# ============================================
EXECUTION_START_TIME=""
EXECUTION_END_TIME=""

# Function: Format execution time beautifully
format_execution_time() {
    local duration_ms="$1"
    local hours=$((duration_ms / 3600000))
    local minutes=$(((duration_ms % 3600000) / 60000))
    local seconds=$(((duration_ms % 60000) / 1000))
    local milliseconds=$((duration_ms % 1000))
    
    # Build the formatted string
    local formatted=""
    
    if [ $hours -gt 0 ]; then
        formatted="${hours}h ${minutes}m ${seconds}s ${milliseconds}ms"
    elif [ $minutes -gt 0 ]; then
        formatted="${minutes}m ${seconds}s ${milliseconds}ms"
    elif [ $seconds -gt 0 ]; then
        if [ $milliseconds -gt 0 ]; then
            formatted="${seconds}.$(printf "%03d" $milliseconds)s"
        else
            formatted="${seconds}s"
        fi
    else
        formatted="${milliseconds}ms"
    fi
    
    echo "$formatted"
}

# Function: Start execution timer
start_timer() {
    EXECUTION_START_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo "0")
}

# Function: Stop timer and display execution time
stop_timer() {
    EXECUTION_END_TIME=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo "0")
    
    if [ "$EXECUTION_START_TIME" != "0" ] && [ "$EXECUTION_END_TIME" != "0" ]; then
        local duration=$((EXECUTION_END_TIME - EXECUTION_START_TIME))
        local formatted_time=$(format_execution_time $duration)
        
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  ⏱  Execution Time: ${YELLOW}${formatted_time}${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

# Function: Compile and link all .asm files and copy .sh files to /dev directory
# This only runs if ./dev directory does NOT exist
# COMPLETELY SILENT unless VERBOSE_DEV=true
compile_and_copy() {
    dev_log "${BLUE}Starting compilation and linking of .asm files...${NC}"
    dev_log "${BLUE}Also copying .sh files and binaries to /dev directory...${NC}"

    # Determine current architecture
    ARCH=""
    case "$(uname -m)" in
        "x86_64"|"amd64")
            ARCH="x86_64"
            FORMAT="elf64"
            ;;
        "i386"|"i486"|"i586"|"i686")
            ARCH="i386"
            FORMAT="elf32"
            ;;
        "arm"|"armv7l"|"armv8l"|"aarch64"|"arm64")
            ARCH="arm"
            FORMAT="elf32"
            ;;
        *)
            dev_error "${RED}Unsupported architecture: $(uname -m)${NC}"
            return 1
            ;;
    esac

    dev_log "${GREEN}Detected architecture: ${ARCH} (using ${FORMAT} format)${NC}"

    # Set up NASM binary path (based on script's directory)
    NASM_BINARY="$SCRIPT_DIR/._/basm/${ARCH}-linux/nasm-${ARCH}-linux"

    # Check if NASM binary exists
    if [ ! -f "$NASM_BINARY" ]; then
        dev_error "${RED}NASM binary not found at: $NASM_BINARY${NC}"
        return 1
    fi

    dev_log "${GREEN}Using NASM binary: $NASM_BINARY${NC}"

    # Make NASM binary executable
    chmod +x "$NASM_BINARY" 2>/dev/null

    # Clean up old /dev directory and create brand new (based on script's directory)
    dev_log "${BLUE}Cleaning up and creating new /dev directory...${NC}"
    rm -rf "$SCRIPT_DIR/dev" 2>/dev/null
    mkdir -p "$SCRIPT_DIR/dev" 2>/dev/null

    # Create directory structure for all directories EXCEPT nasm (we'll handle basm separately)
    dev_log "${BLUE}Creating directory structure...${NC}"
    find "$SCRIPT_DIR/._" -type d 2>/dev/null | while IFS= read -r dir; do
        # Skip the entire nasm directory - we'll handle basm files manually
        if [[ "$dir" == "$SCRIPT_DIR/._/basm"* ]]; then
            continue
        fi
        
        # Create corresponding directory in /dev
        new_dir="${dir/$SCRIPT_DIR\/\.\_/$SCRIPT_DIR\/dev}"
        mkdir -p "$new_dir" 2>/dev/null
    done

    # Special handling for basm directory - create full structure
    dev_log "${BLUE}Creating basm directory structure...${NC}"
    mkdir -p "$SCRIPT_DIR/dev/basm" 2>/dev/null
    mkdir -p "$SCRIPT_DIR/dev/basm/arm-linux" 2>/dev/null
    mkdir -p "$SCRIPT_DIR/dev/basm/i386-linux" 2>/dev/null
    mkdir -p "$SCRIPT_DIR/dev/basm/x86_64-linux" 2>/dev/null

    # Find all .asm files (excluding basm directory)
    dev_log "${BLUE}Finding .asm files...${NC}"
    ASM_FILES=$(find "$SCRIPT_DIR/._" -name "*.asm" ! -path "$SCRIPT_DIR/._/basm/*" 2>/dev/null)
    ASM_COUNT=$(echo "$ASM_FILES" | wc -l)

    # Find all .sh files (excluding basm directory - we'll handle basm scripts separately)
    dev_log "${BLUE}Finding .sh files...${NC}"
    SH_FILES=$(find "$SCRIPT_DIR/._" -name "*.sh" ! -path "$SCRIPT_DIR/._/basm/*" 2>/dev/null)
    SH_COUNT=$(echo "$SH_FILES" | wc -l)

    # Find all binary files (excluding basm directory - we'll handle basm binaries separately)
    dev_log "${BLUE}Finding binary files...${NC}"
    BINARY_FILES=$(find "$SCRIPT_DIR/._" -type f ! -name "*.asm" ! -name "*.sh" ! -path "$SCRIPT_DIR/._/basm/*" 2>/dev/null)
    BINARY_COUNT=$(echo "$BINARY_FILES" | wc -l)

    # Find all files in basm directory (scripts, binaries, everything)
    dev_log "${BLUE}Finding basm files...${NC}"
    BASM_FILES=$(find "$SCRIPT_DIR/._/basm" -type f 2>/dev/null)
    BASM_COUNT=$(echo "$BASM_FILES" | wc -l)

    TOTAL_FILES=$((ASM_COUNT + SH_COUNT + BINARY_COUNT + BASM_COUNT))
    
    if [ "$TOTAL_FILES" -eq 0 ]; then
        dev_error "${RED}No .asm, .sh, binary, or basm files found!${NC}"
        return 1
    fi

    dev_log "${YELLOW}Found $ASM_COUNT .asm files, $SH_COUNT .sh files, $BINARY_COUNT binary files, and $BASM_COUNT basm files to process${NC}"

    # Initialize counters
    total_asm_files=0
    compiled_files=0
    failed_asm_files=0
    
    total_sh_files=0
    copied_sh_files=0
    failed_sh_files=0
    
    total_binary_files=0
    copied_binary_files=0
    failed_binary_files=0
    
    total_basm_files=0
    copied_basm_files=0
    failed_basm_files=0

    # ============================================
    # PROCESS 1: Compile and link all .asm files
    # ============================================
    if [ "$ASM_COUNT" -gt 0 ]; then
        dev_log "${BLUE}\n[1/4] Compiling and linking .asm files...${NC}"
        
        while IFS= read -r asm_file; do
            ((total_asm_files++))
            
            dev_log "\n${YELLOW}[${total_asm_files}] Processing ASM: ${asm_file}${NC}"
            
            # Generate output paths
            output_file="${asm_file/$SCRIPT_DIR\/\.\_/$SCRIPT_DIR\/dev}"
            output_file="${output_file%.asm}"  # Remove .asm extension
            object_file="${output_file}.o"
            
            # Ensure output directory exists
            mkdir -p "$(dirname "$output_file")" 2>/dev/null
            
            # Step 1: Compile with NASM (completely silent)
            dev_log "  Compiling: $NASM_BINARY -f ${FORMAT} \"${asm_file}\" -o \"${object_file}\""
            "$NASM_BINARY" -f "$FORMAT" "$asm_file" -o "$object_file" 2>/dev/null
            NASM_EXIT=$?
            
            if [ $NASM_EXIT -eq 0 ]; then
                dev_log "  ${GREEN}✓ Compilation successful${NC}"
            else
                dev_error "${RED}  ✗ Compilation failed for: ${asm_file}${NC}"
                rm -f "$object_file" 2>/dev/null
                ((failed_asm_files++))
                continue
            fi
            
            # Step 2: Link with LD (completely silent)
            dev_log "  Linking: ld \"${object_file}\" -o \"${output_file}\""
            ld "$object_file" -o "$output_file" 2>/dev/null
            LD_EXIT=$?
            
            if [ $LD_EXIT -eq 0 ]; then
                dev_log "  ${GREEN}✓ Linking successful${NC}"
                chmod +x "$output_file" 2>/dev/null
                ((compiled_files++))
            else
                dev_error "${RED}  ✗ Linking failed for: ${asm_file}${NC}"
                ((failed_asm_files++))
            fi
            
            # Step 3: Clean up object file
            rm -f "$object_file" 2>/dev/null
            dev_log "  ${BLUE}✓ Cleaned up object file${NC}"
            
        done < <(echo "$ASM_FILES")
    fi

    # ============================================
    # PROCESS 2: Copy all .sh files (non-basm)
    # ============================================
    if [ "$SH_COUNT" -gt 0 ]; then
        dev_log "\n${BLUE}[2/4] Copying .sh files to /dev directory...${NC}"
        
        while IFS= read -r sh_file; do
            ((total_sh_files++))
            
            dev_log "${YELLOW}[${total_sh_files}] Copying SH: ${sh_file}${NC}"
            
            # Generate output path
            output_file="${sh_file/$SCRIPT_DIR\/\.\_/$SCRIPT_DIR\/dev}"
            
            # Ensure output directory exists
            mkdir -p "$(dirname "$output_file")" 2>/dev/null
            
            # Copy the .sh file (completely silent)
            dev_log "  Copying: cp \"${sh_file}\" \"${output_file}\""
            cp_file "$sh_file" "$output_file"
            COPY_EXIT=$?
            
            if [ $COPY_EXIT -eq 0 ]; then
                # Make it executable
                chmod +x "$output_file" 2>/dev/null
                dev_log "  ${GREEN}✓ Copy successful${NC}"
                ((copied_sh_files++))
            else
                dev_error "${RED}  ✗ Copy failed for: ${sh_file}${NC}"
                ((failed_sh_files++))
            fi
            
        done < <(echo "$SH_FILES")
    fi

    # ============================================
    # PROCESS 3: Copy all binary files (non-basm)
    # ============================================
    if [ "$BINARY_COUNT" -gt 0 ] && [ -n "$BINARY_FILES" ]; then
        dev_log "\n${BLUE}[3/4] Copying binary files to /dev directory...${NC}"
        
        while IFS= read -r binary_file; do
            # Skip empty lines
            [ -z "$binary_file" ] && continue
            
            ((total_binary_files++))
            
            dev_log "${YELLOW}[${total_binary_files}] Copying binary: ${binary_file}${NC}"
            
            # Generate output path
            output_file="${binary_file/$SCRIPT_DIR\/\.\_/$SCRIPT_DIR\/dev}"
            
            # Ensure output directory exists
            mkdir -p "$(dirname "$output_file")" 2>/dev/null
            
            # Copy the binary file (completely silent)
            dev_log "  Copying: cp \"${binary_file}\" \"${output_file}\""
            cp_file "$binary_file" "$output_file"
            COPY_EXIT=$?
            
            if [ $COPY_EXIT -eq 0 ]; then
                # Make it executable
                chmod +x "$output_file" 2>/dev/null
                dev_log "  ${GREEN}✓ Binary copy successful${NC}"
                ((copied_binary_files++))
            else
                dev_error "${RED}  ✗ Binary copy failed for: ${binary_file}${NC}"
                ((failed_binary_files++))
            fi
            
        done < <(echo "$BINARY_FILES")
    fi

    # ============================================
    # PROCESS 4: Copy all basm files (scripts and binaries)
    # ============================================
    if [ "$BASM_COUNT" -gt 0 ] && [ -n "$BASM_FILES" ]; then
        dev_log "\n${BLUE}[4/4] Copying basm files to /dev/basm directory...${NC}"
        
        while IFS= read -r basm_file; do
            # Skip empty lines
            [ -z "$basm_file" ] && continue
            
            ((total_basm_files++))
            
            dev_log "${YELLOW}[${total_basm_files}] Processing basm file: ${basm_file}${NC}"
            
            # Generate output path (preserve subdirectory structure)
            output_file="${basm_file/$SCRIPT_DIR\/\.\_/$SCRIPT_DIR\/dev}"
            
            # Ensure output directory exists
            mkdir -p "$(dirname "$output_file")" 2>/dev/null
            
            # Copy the file (completely silent)
            dev_log "  Copying: cp \"${basm_file}\" \"${output_file}\""
            cp_file "$basm_file" "$output_file"
            COPY_EXIT=$?
            
            if [ $COPY_EXIT -eq 0 ]; then
                # Make it executable if it's a binary or script
                chmod +x "$output_file" 2>/dev/null
                dev_log "  ${GREEN}✓ Copy successful${NC}"
                ((copied_basm_files++))
            else
                dev_error "${RED}  ✗ Copy failed for: ${basm_file}${NC}"
                ((failed_basm_files++))
            fi
            
        done < <(echo "$BASM_FILES")
    fi

    # ============================================
    # SUMMARY (only shown in verbose mode)
    # ============================================
    if [ "$VERBOSE_DEV" = "true" ]; then
        echo -e "\n${BLUE}=== Compilation Summary ===${NC}"
        if [ "$ASM_COUNT" -gt 0 ]; then
            echo -e "${GREEN}Successfully compiled and linked: ${compiled_files} .asm files${NC}"
            if [ $failed_asm_files -gt 0 ]; then
                echo -e "${RED}Failed: ${failed_asm_files} .asm files${NC}"
            fi
            echo -e "Total .asm files processed: ${total_asm_files}"
        fi

        if [ "$SH_COUNT" -gt 0 ]; then
            echo -e "\n${BLUE}=== Shell Script Copy Summary ===${NC}"
            echo -e "${GREEN}Successfully copied: ${copied_sh_files} .sh files${NC}"
            if [ $failed_sh_files -gt 0 ]; then
                echo -e "${RED}Failed: ${failed_sh_files} .sh files${NC}"
            fi
            echo -e "Total .sh files processed: ${total_sh_files}"
        fi

        if [ "$BINARY_COUNT" -gt 0 ]; then
            echo -e "\n${BLUE}=== Binary Copy Summary ===${NC}"
            echo -e "${GREEN}Successfully copied: ${copied_binary_files} binary files${NC}"
            if [ $failed_binary_files -gt 0 ]; then
                echo -e "${RED}Failed: ${failed_binary_files} binary files${NC}"
            fi
            echo -e "Total binary files processed: ${total_binary_files}"
        fi

        if [ "$BASM_COUNT" -gt 0 ]; then
            echo -e "\n${BLUE}=== BASM Files Copy Summary ===${NC}"
            echo -e "${GREEN}Successfully copied: ${copied_basm_files} basm files${NC}"
            if [ $failed_basm_files -gt 0 ]; then
                echo -e "${RED}Failed: ${failed_basm_files} basm files${NC}"
            fi
            echo -e "Total basm files processed: ${total_basm_files}"
            
            # List the basm directory contents specifically
            echo -e "\n${BLUE}=== /dev/basm Directory Contents ===${NC}"
            if [ -d "$SCRIPT_DIR/dev/basm" ]; then
                ls -la "$SCRIPT_DIR/dev/basm" 2>/dev/null | tail -n +2
            fi
        fi

        echo -e "\n${GREEN}Output directory: $SCRIPT_DIR/dev${NC}"

        # Display what's in /dev with tree-like structure
        echo -e "\n${BLUE}=== $SCRIPT_DIR/dev Directory Structure ===${NC}"
        echo -e "${GREEN}Executable files created:${NC}"

        # Use a simple tree display
        list_files() {
            local indent="$1"
            local dir="$2"
            
            for item in "$dir"/*; do
                if [ -d "$item" ]; then
                    echo -e "${indent}└── $(basename "$item")/"
                    list_files "    $indent" "$item"
                elif [ -f "$item" ]; then
                    if [ -x "$item" ]; then
                        echo -e "${indent}└── ${GREEN}$(basename "$item") ✓${NC}"
                    else
                        echo -e "${indent}└── $(basename "$item")"
                    fi
                fi
            done
        }

        # Start listing from $SCRIPT_DIR/dev
        for item in "$SCRIPT_DIR/dev"/*; do
            if [ -d "$item" ]; then
                echo "└── $(basename "$item")/"
                list_files "    " "$item"
            elif [ -f "$item" ]; then
                if [ -x "$item" ]; then
                    echo -e "└── ${GREEN}$(basename "$item") ✓${NC}"
                else
                    echo "└── $(basename "$item")"
                fi
            fi
        done

        # Verify all files were created
        echo -e "\n${BLUE}=== Verification ===${NC}"
        if [ "$ASM_COUNT" -gt 0 ]; then
            echo -e "Expected .asm files: $ASM_COUNT"
        fi
        if [ "$SH_COUNT" -gt 0 ]; then
            echo -e "Expected .sh files: $SH_COUNT"
        fi
        if [ "$BINARY_COUNT" -gt 0 ]; then
            echo -e "Expected binary files: $BINARY_COUNT"
        fi
        if [ "$BASM_COUNT" -gt 0 ]; then
            echo -e "Expected basm files: $BASM_COUNT"
        fi
        
        expected_total=$((ASM_COUNT + SH_COUNT + BINARY_COUNT + BASM_COUNT))
        actual_total=$(find "$SCRIPT_DIR/dev" -type f 2>/dev/null | wc -l)
        
        echo -e "Total files created: $actual_total"
        
        if [ "$expected_total" -eq "$actual_total" ]; then
            echo -e "${GREEN}✓ All files were successfully created!${NC}"
        else
            echo -e "${YELLOW}⚠ Some files might be missing (expected: $expected_total, got: $actual_total)${NC}"
        fi

        echo -e "\n${GREEN}Build completed successfully!${NC}"
        echo -e "All binaries, shell scripts, and executables are available in the $SCRIPT_DIR/dev directory"
    fi
    
    return 0
}

# ============================================
# EXECUTION STEP FUNCTIONS
# ============================================

# Display usage information (minimalistic)
show_usage() {
    echo -e "${YELLOW}Usage: bash Raw.sh [--log] [--verbose] <path/to/file.js> [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --reset${NC}"
    echo -e "${YELLOW}       bash Raw.sh --test${NC}"
    echo -e "${YELLOW}       bash Raw.sh --cli${NC}"
    echo -e "${YELLOW}       bash Raw.sh --dev${NC}"
    echo -e "${YELLOW}       bash Raw.sh --tool [command] [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --<tool> [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --tools${NC}"
    echo -e "${YELLOW}       bash Raw.sh --stools${NC}"
    echo -e "${YELLOW}       bash Raw.sh --version${NC}"
    echo -e "${YELLOW}       bash Raw.sh --asm [path/to/file.js] [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --bin [output_name] <path/to/file.js> [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --bin [options] <build_output.asm>${NC}"
}

# Process the JavaScript file - just store path and args for later use
# Usage: process_js_file <js_file_path> [js_args...]
process_js_file() {
    local js_file="$1"
    shift
    local js_args="$@"
    
    # Check if JS file exists
    if [ ! -f "$js_file" ]; then
        echo -e "${RED}Error: JS file not found: $js_file${NC}" >&2
        return 1
    fi
    
    # Get absolute path for the JS file
    local abs_js_path=$(realpath "$js_file" 2>/dev/null || echo "$(cd "$(dirname "$js_file")" && pwd)/$(basename "$js_file")")
    
    # Store in global variables for use in execution patterns
    JS_FILE_PATH="$abs_js_path"
    JS_ARGS="$js_args"
    
    return 0
}

# Function: Copy build_output.asm to caller's directory
copy_asm_to_caller() {
    local source_asm="$SCRIPT_DIR/dev/build_output.asm"
    
    # Check if build_output.asm exists
    if [ ! -f "$source_asm" ]; then
        echo -e "${RED}Error: build_output.asm not found in dev directory${NC}" >&2
        return 1
    fi
    
    # Copy to caller's directory (replacing if exists)
    cp_file "$source_asm" "$CALLER_DIR/build_output.asm"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ build_output.asm copied to: $CALLER_DIR/build_output.asm${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to copy build_output.asm to caller directory${NC}" >&2
        return 1
    fi
}

# Function: Execute binary generation using basm.sh with --bin flag
# Usage: generate_binary <asm_file_path> <output_name>
generate_binary() {
    local asm_file="$1"
    local output_name="$2"
    
    # Path to the basm script
    local basm_script="$SCRIPT_DIR/dev/basm/basm.sh"
    
    # Check if basm script exists
    if [ ! -f "$basm_script" ]; then
        echo -e "${RED}Error: basm script not found at $basm_script${NC}" >&2
        return 1
    fi
    
    # Make sure basm script is executable
    chmod +x "$basm_script" 2>/dev/null
    
    echo -e "${BLUE}Binary generation started...${NC}"
    echo -e "${YELLOW}Input ASM: $asm_file${NC}"
    
    if [ -n "$output_name" ]; then
        echo -e "${YELLOW}Output name: $output_name${NC}"
        # Execute basm with --bin and output name
        (cd "$CALLER_DIR" && "$basm_script" --log --bin "$output_name" "$asm_file")
    else
        # Execute basm with --bin without output name
        (cd "$CALLER_DIR" && "$basm_script" --log --bin "$asm_file")
    fi
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo ""
        echo -e "${GREEN}Binary generation completed successfully!${NC}"
        if [ -n "$output_name" ]; then
            echo -e "${GREEN}Output: $CALLER_DIR/$output_name${NC}"
        else
            echo -e "${GREEN}Output: $CALLER_DIR/a.out${NC}"
        fi
    else
        echo -e "${RED}Binary generation failed with exit code: $result${NC}" >&2
    fi
    
    return $result
}

# Creates an interactive CLI where each line is treated as JS code
handle_cli() {
    # Clear terminal at start
    clear
    
    echo -e "${GREEN}rawjs${NC} ${YELLOW}· exit | clear | errorgen${NC}"
    echo ""
    
    # Create temp JS file in caller directory
    local cli_js_file="$CALLER_DIR/.rawjs_cli.js"
    
    # Initialize empty JS file
    echo "" > "$cli_js_file"
    
    # Track the entire accumulated script (all lines typed, regardless of execution success)
    local full_script=""
    
    # Track previous output to extract only new output
    local previous_output=""
    
    # Track lines that caused errors (kept for potential future use, not written to final file)
    local error_lines=()
    
    # Start the interactive loop
    while true; do
        # Display prompt
        echo -ne "${GREEN}rawjs> ${NC}"
        
        # Read user input
        if ! IFS= read -r user_input; then
            # EOF (Ctrl+D)
            echo ""
            break
        fi
        
        # Check for exit commands
        if [ "$user_input" = "exit" ] || [ "$user_input" = "quit" ]; then
            clear
            break
        fi
        
        # Check for clear command
        if [ "$user_input" = "clear" ]; then
            echo "" > "$cli_js_file"
            full_script=""
            previous_output=""
            error_lines=()
            clear
            echo -e "${GREEN}rawjs${NC} ${YELLOW}· exit | clear | errorgen${NC}"
            echo ""
            continue
        fi
        
        # Skip empty lines
        if [ -z "$user_input" ]; then
            continue
        fi
        
        # NEW: Detect errorgen command
        if [[ "$user_input" == *"errorgen"* ]]; then
            echo -e "${YELLOW}errorgen detected. Writing all lines to .rawjs_cli.js and generating logs...${NC}"
            
            # Write the FULL script (all lines typed) to .rawjs_cli.js
            printf "%s\n" "$full_script" > "$cli_js_file"
            
            # Define log file paths (in caller directory)
            local log_file="$CALLER_DIR/.rawjs_cli.log.txt"
            local verbose_file="$CALLER_DIR/.rawjs_cli.verbose.txt"
            local full_file="$CALLER_DIR/.rawjs_cli.full.txt"
            
            # Run Raw.sh with --log and capture all terminal output
            echo -e "${BLUE}Running with --log...${NC}"
            (cd "$CALLER_DIR" && bash "$SCRIPT_DIR/Raw.sh" --log .rawjs_cli.js > "$log_file" 2>&1)
            local log_status=$?
            
            # Run Raw.sh with --verbose and capture all terminal output
            echo -e "${BLUE}Running with --verbose...${NC}"
            (cd "$CALLER_DIR" && bash "$SCRIPT_DIR/Raw.sh" --verbose .rawjs_cli.js > "$verbose_file" 2>&1)
            local verbose_status=$?
            
            # Run Raw.sh with --asm to generate build_output.asm
            echo -e "${BLUE}Running with --asm...${NC}"
            (cd "$CALLER_DIR" && bash "$SCRIPT_DIR/Raw.sh" --asm .rawjs_cli.js > /dev/null 2>&1)
            local asm_status=$?
            
            # Now create the full file with verbose output + JS code + ASM output
            echo -e "${BLUE}Generating full output file...${NC}"
            
            # Start with header
            {
                echo "Full Error Log - Generated by Raw.sh CLI errorgen"
                echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
                echo "Caller Directory: ${CALLER_DIR}"
                echo "========================================="
                echo ""
                echo "--- Verbose Mode Output ---"
                echo ""
                
                # Strip ANSI codes from verbose output and include it
                strip_ansi_codes "$(cat "$verbose_file")"
                echo ""
                echo "--- Complete JS Source Code ---"
                echo "File: ${cli_js_file}"
                echo ""
                
                # Include the JS source code
                cat "$cli_js_file"
                echo ""
                echo "--- ASM Output ---"
                echo "Command: bash $SCRIPT_DIR/Raw.sh --asm .rawjs_cli.js"
                echo "Exit Code: ${asm_status}"
                echo ""
            } > "$full_file"
            
            # Check if build_output.asm was generated in caller directory
            local asm_file="$CALLER_DIR/build_output.asm"
            if [ -f "$asm_file" ]; then
                # Include the ASM file content
                {
                    echo "--- Generated .asm File Content (from: ${asm_file}) ---"
                    echo ""
                    cat "$asm_file"
                    echo ""
                    echo "========================================="
                } >> "$full_file"
                
                # Remove the build_output.asm file after capturing its content
                rm_file "$asm_file"
                echo -e "${GREEN}✓ ASM file content captured and removed${NC}"
            else
                # Search for build_output.asm in other locations
                local found_asm=""
                if [ -f "$SCRIPT_DIR/dev/build_output.asm" ]; then
                    found_asm="$SCRIPT_DIR/dev/build_output.asm"
                elif [ -f "$SCRIPT_DIR/build_output.asm" ]; then
                    found_asm="$SCRIPT_DIR/build_output.asm"
                fi
                
                if [ -n "$found_asm" ] && [ -f "$found_asm" ]; then
                    {
                        echo "--- Generated .asm File Content (from: ${found_asm}) ---"
                        echo ""
                        cat "$found_asm"
                        echo ""
                        echo "========================================="
                    } >> "$full_file"
                    
                    # Remove the build_output.asm file after capturing its content
                    rm_file "$found_asm"
                    echo -e "${GREEN}✓ ASM file content captured from $found_asm and removed${NC}"
                else
                    {
                        echo "--- Warning: No build_output.asm file found ---"
                        echo "ASM generation may have failed"
                        echo "========================================="
                    } >> "$full_file"
                    echo -e "${YELLOW}⚠ No build_output.asm file found${NC}"
                fi
            fi
            
            # Report results
            echo -e "${GREEN}✓ .rawjs_cli.js written with all lines${NC}"
            echo -e "${GREEN}✓ Log file (--log): $log_file${NC}"
            echo -e "${GREEN}✓ Verbose file (--verbose): $verbose_file${NC}"
            echo -e "${GREEN}✓ Full file (verbose + JS + ASM): $full_file${NC}"
            
            return 0
        fi
        
        # Append the input to the full script (keeps ALL lines)
        if [ -n "$full_script" ]; then
            full_script="$full_script"$'\n'"$user_input"
        else
            full_script="$user_input"
        fi
        
        # Save current file content for rollback if needed
        local backup_content=$(cat "$cli_js_file" 2>/dev/null)
        
        # Append the input to the JS file (temporary – will be rolled back on failure)
        echo "$user_input" >> "$cli_js_file"
        
        # Execute the JS file through the Raw engine
        local output_js="$SCRIPT_DIR/output.js"
        local arch_output="$SCRIPT_DIR/arch_output"
        
        local compile_success=true
        local compile_error=""
        
        # Execute minification step
        if ! execute_file "silent" "./._/min/min" "$cli_js_file" >/dev/null 2>&1; then
            compile_success=false
            compile_error="minification"
        fi
        
        # Continue pipeline if minification succeeded
        if [ "$compile_success" = true ]; then
            if ! execute_file "silent" "./._/min/polish.sh" "$output_js" >/dev/null 2>&1; then
                compile_success=false
                compile_error="polishing"
            fi
        fi
        
        if [ "$compile_success" = true ]; then
            if ! execute_file "silent" "./build" >/dev/null 2>&1; then
                compile_success=false
                compile_error="build"
            fi
        fi
        
        if [ "$compile_success" = true ]; then
            mv_file "build_output.asm" "$EXECUTION_SOURCE/build_output.asm" 2>/dev/null
            
            if ! execute_file "silent" "./arch" "$output_js" >/dev/null 2>&1; then
                compile_success=false
                compile_error="arch"
            fi
        fi
        
        if [ "$compile_success" = true ]; then
            mv_file "arch_output" "$EXECUTION_SOURCE/arch_output" 2>/dev/null
            rm_file "$SCRIPT_DIR/output.js" 2>/dev/null
            
            if ! execute_file "silent" "./tree/build.sh" >/dev/null 2>&1; then
                compile_success=false
                compile_error="tree/build"
            fi
        fi
        
        # If compilation failed, rollback and show error
        if [ "$compile_success" = false ]; then
            echo "$backup_content" > "$cli_js_file"
            rm_file "$SCRIPT_DIR/output.js" 2>/dev/null
            rm_file "$SCRIPT_DIR/arch_output" 2>/dev/null
            rm_file "$SCRIPT_DIR/$EXECUTION_SOURCE/arch_output" 2>/dev/null
            rm_file "$SCRIPT_DIR/$EXECUTION_SOURCE/build_output.asm" 2>/dev/null
            
            error_lines+=("$user_input")
            
            echo -e "${RED}✗ Compilation failed!${NC}"
            echo -e "${RED}  Error in: $compile_error step${NC}"
            echo -e "${YELLOW}  Removed line: $user_input${NC}"
            echo ""
            continue
        fi
        
        # Execute the final binary and capture output
        local current_output=$(execute_file "log" "./build_output.asm" 2>&1)
        local execution_success=$?
        
        # If execution failed, also rollback
        if [ $execution_success -ne 0 ]; then
            echo "$backup_content" > "$cli_js_file"
            rm_file "$SCRIPT_DIR/output.js" 2>/dev/null
            rm_file "$SCRIPT_DIR/arch_output" 2>/dev/null
            rm_file "$SCRIPT_DIR/$EXECUTION_SOURCE/arch_output" 2>/dev/null
            rm_file "$SCRIPT_DIR/$EXECUTION_SOURCE/build_output.asm" 2>/dev/null
            
            error_lines+=("$user_input")
            
            echo -e "${RED}✗ Execution failed!${NC}"
            echo -e "${YELLOW}  Removed line: $user_input${NC}"
            echo ""
            continue
        fi
        
        # Extract only the new output
        if [ -n "$previous_output" ]; then
            local new_output=$(diff <(echo "$previous_output") <(echo "$current_output") | grep '^>' | sed 's/^> //')
            if [ -n "$new_output" ]; then
                echo "$new_output"
            fi
        else
            echo "$current_output"
        fi
        
        previous_output="$current_output"
        echo ""
    done
    
    # Clean up temp file
    rm_file "$cli_js_file"
    
    return 0
}

# ============================================
# SPECIAL MODE HANDLERS
# ============================================

# Handle --reset mode
handle_reset() {
    echo -e "${YELLOW}Resetting /dev directory...${NC}"
    
    # Remove the dev directory
    rm -rf "$SCRIPT_DIR/dev" 2>/dev/null
    
    # Run compilation
    compile_and_copy
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Reset completed successfully! /dev directory has been rebuilt.${NC}"
        
        # If asm mode is active, copy the asm file after reset
        if [ "$ASM_MODE" = "true" ]; then
            copy_asm_to_caller
        fi
        
        return 0
    else
        echo -e "${RED}Reset failed during compilation!${NC}"
        return 1
    fi
}

# Handle --test mode
handle_test() {
    local test_args="$@"
    
    echo -e "${YELLOW}Running test mode...${NC}"
    
    # First reset (delete and rebuild dev)
    echo -e "${BLUE}Step 1: Resetting /dev directory...${NC}"
    rm -rf "$SCRIPT_DIR/dev" 2>/dev/null
    compile_and_copy
    if [ $? -ne 0 ]; then
        echo -e "${RED}Test failed: Could not rebuild /dev directory!${NC}"
        return 1
    fi
    
    # Then execute the test script
    echo -e "${BLUE}Step 2: Executing test script...${NC}"
    local test_script="$SCRIPT_DIR/dev/._/._/._/runtest.sh"
    
    if [ ! -f "$test_script" ]; then
        echo -e "${RED}Error: Test script not found at $test_script${NC}"
        return 1
    fi
    
    # Make it executable
    chmod +x "$test_script" 2>/dev/null
    
    # Execute with bash, passing any additional arguments
    if [ -n "$test_args" ]; then
        echo -e "${GREEN}Running test script with arguments: $test_args${NC}"
        bash "$test_script" $test_args
    else
        echo -e "${GREEN}Running test script...${NC}"
        bash "$test_script"
    fi
    
    local test_result=$?
    
    if [ $test_result -eq 0 ]; then
        echo -e "${GREEN}Tests completed successfully!${NC}"
        
        # If asm mode is active, copy the asm file after test
        if [ "$ASM_MODE" = "true" ]; then
            copy_asm_to_caller
        fi
    else
        echo -e "${RED}Tests failed with exit code: $test_result${NC}"
    fi
    
    return $test_result
}

# ============================================
# TOOL GROUPS SYSTEM
# ============================================

# Function: Check if a tool belongs to a specific group
is_tool_in_group() {
    local tool_name="$1"
    local group_name="$2"
    
    # Get the array of tools for this group
    local group_array_name="TOOL_GROUP_${group_name}_TOOLS[@]"
    
    # Check if the tool is in this group's array
    for group_tool in "${!group_array_name}"; do
        if [ "$group_tool" = "$tool_name" ]; then
            return 0  # Found
        fi
    done
    
    return 1  # Not found
}

# Function: Get the group name for a specific tool
get_tool_group() {
    local tool_name="$1"
    
    # Check all defined groups first
    for group_name in "${TOOL_GROUPS_ORDER[@]}"; do
        if is_tool_in_group "$tool_name" "$group_name"; then
            echo "$group_name"
            return 0
        fi
    done
    
    # If not in any defined group, return "General"
    echo "General"
    return 0
}

# Function: Get color code for a group
get_group_color() {
    local group_name="$1"
    local color_variable="TOOL_GROUP_${group_name}_COLOR"
    local color="${!color_variable}"
    
    if [ -z "$color" ]; then
        # Default to white if no color defined
        echo "0;37"
    else
        echo "$color"
    fi
}

# Function: Get tool description by running the tool function
get_tool_description() {
    local tool_name="$1"
    
    # Check if tool function exists
    if ! declare -f "tool_${tool_name}" > /dev/null 2>&1; then
        echo "<no description>"
        return 0
    fi
    
    # Execute the tool function without arguments and capture first line of output
    local description=""
    description=$( (CALLER_DIR="$SCRIPT_DIR" tool_${tool_name} 2>&1 || true) | sed 's/\x1b\[[0-9;]*m//g' | head -n 1 | tr '\n' ' ' | sed 's/  */ /g' | xargs)
    
    # If no description, use a placeholder
    if [ -z "$description" ]; then
        description="<no description>"
    fi
    
    echo "$description"
}

# Function: Build a map of all tools and their groups
build_tool_group_map() {
    # Declare associative array for tool to group mapping
    declare -gA TOOL_GROUP_MAP
    
    # Get all available tool functions
    local all_tools=$(declare -F | grep -o 'tool_[a-zA-Z0-9_]*' | grep -v 'tool_mode\|tool_command\|tool_args\|tool_commands\|tool_group' | sed 's/^tool_//' | sort)
    
    # Assign each tool to its group
    while IFS= read -r tool_name; do
        if [ -n "$tool_name" ]; then
            local group=$(get_tool_group "$tool_name")
            TOOL_GROUP_MAP["$tool_name"]="$group"
        fi
    done <<< "$all_tools"
}

# Function: Get all tools for a specific group (sorted by group's defined order)
get_tools_for_group() {
    local group_name="$1"
    local group_array_name="TOOL_GROUP_${group_name}_TOOLS[@]"
    local group_tools=()
    
    # If this is a defined group with specific order
    if [ "$group_name" != "General" ] && [ ${#TOOL_GROUPS_ORDER[@]} -gt 0 ]; then
        # Use the defined order from the group array
        for tool_name in "${!group_array_name}"; do
            # Check if tool function actually exists
            if declare -f "tool_${tool_name}" > /dev/null 2>&1; then
                group_tools+=("$tool_name")
            fi
        done
    else
        # For General group, collect all tools not in any other group
        local all_tools=$(declare -F | grep -o 'tool_[a-zA-Z0-9_]*' | grep -v 'tool_mode\|tool_command\|tool_args\|tool_commands\|tool_group' | sed 's/^tool_//' | sort)
        
        while IFS= read -r tool_name; do
            if [ -n "$tool_name" ]; then
                local assigned_group=$(get_tool_group "$tool_name")
                if [ "$assigned_group" = "General" ]; then
                    # Only include if tool function exists
                    if declare -f "tool_${tool_name}" > /dev/null 2>&1; then
                        group_tools+=("$tool_name")
                    fi
                fi
            fi
        done <<< "$all_tools"
    fi
    
    # Return the array as newline-separated string
    printf '%s\n' "${group_tools[@]}"
}

# Function: Display formatted tool list with groups and colors (full version)
display_tool_list_with_groups() {
    # Build the tool-group map
    build_tool_group_map
    
    # Find the longest tool name for alignment
    local max_tool_length=0
    local all_tools=$(declare -F | grep -o 'tool_[a-zA-Z0-9_]*' | grep -v 'tool_mode\|tool_command\|tool_args\|tool_commands\|tool_group' | sed 's/^tool_//' | sort)
    
    while IFS= read -r tool_name; do
        if [ -n "$tool_name" ] && [ ${#tool_name} -gt $max_tool_length ]; then
            max_tool_length=${#tool_name}
        fi
    done <<< "$all_tools"
    
    # Create temp directory for parallel description fetching
    local temp_directory=$(mktemp -d)
    local process_ids=()
    
    # Fetch all tool descriptions in parallel
    while IFS= read -r tool_name; do
        if [ -n "$tool_name" ]; then
            (
                local description=$(get_tool_description "$tool_name")
                echo "$description" > "$temp_directory/${tool_name}.description"
            ) &
            process_ids+=($!)
        fi
    done <<< "$all_tools"
    
    # Wait for all background processes to complete
    for process_id in "${process_ids[@]}"; do
        wait $process_id 2>/dev/null
    done
    
    # Display header
    echo -e "\033[0;34mAvailable tools:\033[0m"
    echo ""
    
    # Calculate max description width based on terminal
    local terminal_width=${COLUMNS:-80}
    local separator=" | "
    local description_maximum=$((terminal_width - max_tool_length - ${#separator}))
    
    # Display tools group by group
    local has_general_tools=false
    
    # Process defined groups first (in order)
    for group_name in "${TOOL_GROUPS_ORDER[@]}"; do
        local group_tools_list=$(get_tools_for_group "$group_name")
        
        if [ -n "$group_tools_list" ]; then
            local group_color=$(get_group_color "$group_name")
            
            # Display group header with its color
            echo -e "\033[${group_color}m▸ ${group_name}:\033[0m"
            
            # Display tools in this group
            while IFS= read -r tool_name; do
                if [ -n "$tool_name" ]; then
                    local description="<no description>"
                    if [ -f "$temp_directory/${tool_name}.description" ]; then
                        description=$(cat "$temp_directory/${tool_name}.description")
                    fi
                    
                    # Truncate description if too long
                    if [ ${#description} -gt $description_maximum ]; then
                        description="${description:0:$((description_maximum - 3))}..."
                    fi
                    
                    # Get working directory for this tool
                    local working_directory=$(get_tool_working_dir "$tool_name")
                    
                    # Display tool with group color
                    printf "  \033[${group_color}m--%-${max_tool_length}s\033[0m ${separator}%s \033[0;90m[dir: %s]\033[0m\n" \
                        "$tool_name" "$description" "$working_directory"
                fi
            done <<< "$group_tools_list"
            
            echo ""
        fi
    done
    
    # Check if there are any tools in General group
    local general_tools_list=$(get_tools_for_group "General")
    if [ -n "$general_tools_list" ]; then
        has_general_tools=true
        local general_color=$(get_group_color "General")
        
        # Display General group header
        echo -e "\033[${general_color}m▸ General:\033[0m"
        
        # Display tools in General group
        while IFS= read -r tool_name; do
            if [ -n "$tool_name" ]; then
                local description="<no description>"
                if [ -f "$temp_directory/${tool_name}.description" ]; then
                    description=$(cat "$temp_directory/${tool_name}.description")
                fi
                
                # Truncate description if too long
                if [ ${#description} -gt $description_maximum ]; then
                    description="${description:0:$((description_maximum - 3))}..."
                fi
                
                # Get working directory for this tool
                local working_directory=$(get_tool_working_dir "$tool_name")
                
                # Display tool with general color
                printf "  \033[${general_color}m--%-${max_tool_length}s\033[0m ${separator}%s \033[0;90m[dir: %s]\033[0m\n" \
                    "$tool_name" "$description" "$working_directory"
            fi
        done <<< "$general_tools_list"
        
        echo ""
    fi
    
    # Cleanup temp directory
    rm -rf "$temp_directory"
    
    # Display usage information
    echo -e "\033[1;33mUsage: bash Raw.sh --<tool> [args...]\033[0m"
    echo -e "\033[1;33m   or: bash Raw.sh --tool <tool> [args...]\033[0m"
    echo ""
    echo -e "\033[0;34mWorking directory types:\033[0m"
    echo -e "  \033[0;37mglobal\033[0m  - Execute from Raw.sh directory ($SCRIPT_DIR)"
    echo -e "  \033[0;37mcaller\033[0m  - Execute from where you called the command ($CALLER_DIR)"
    echo -e "  \033[0;37mfile\033[0m    - Execute from the tool file's own directory"
}

# Function: Display compact tool list (for --stools/--stool)
# Designed to fit in extremely small terminals with color toggling for clarity
display_compact_tool_list() {
    # Build the tool-group map
    build_tool_group_map
    
    # Get all available tool functions
    local all_tools=$(declare -F | grep -o 'tool_[a-zA-Z0-9_]*' | grep -v 'tool_mode\|tool_command\|tool_args\|tool_commands\|tool_group' | sed 's/^tool_//' | sort)
    
    # Collect all tools by group
    local group_tools_map=""
    
    # Process defined groups first (in order)
    for group_name in "${TOOL_GROUPS_ORDER[@]}"; do
        local group_tools_list=$(get_tools_for_group "$group_name")
        if [ -n "$group_tools_list" ]; then
            local group_color=$(get_group_color "$group_name")
            local tools_in_group=""
            
            while IFS= read -r tool_name; do
                if [ -n "$tool_name" ]; then
                    if [ -n "$tools_in_group" ]; then
                        tools_in_group="$tools_in_group,"
                    fi
                    tools_in_group="$tools_in_group$tool_name"
                fi
            done <<< "$group_tools_list"
            
            if [ -n "$tools_in_group" ]; then
                group_tools_map="$group_tools_map"$'\n'"$group_color|$group_name|$tools_in_group"
            fi
        fi
    done
    
    # Process General group
    local general_tools_list=$(get_tools_for_group "General")
    if [ -n "$general_tools_list" ]; then
        local general_color=$(get_group_color "General")
        local tools_in_general=""
        
        while IFS= read -r tool_name; do
            if [ -n "$tool_name" ]; then
                if [ -n "$tools_in_general" ]; then
                    tools_in_general="$tools_in_general,"
                fi
                tools_in_general="$tools_in_general$tool_name"
            fi
        done <<< "$general_tools_list"
        
        if [ -n "$tools_in_general" ]; then
            group_tools_map="$group_tools_map"$'\n'"$general_color|General|$tools_in_general"
        fi
    fi
    
    # Display compact header
    echo -e "\033[0;34mTools:\033[0m"
    
    # Display groups in compact format with alternating colors for each tool
    while IFS='|' read -r group_color group_name tools_list; do
        if [ -n "$group_name" ]; then
            # Display group name with color
            printf "\033[%sm%s:\033[0m " "$group_color" "$group_name"
            
            # Display tools with alternating background colors for clarity
            local tool_index=0
            IFS=',' read -ra TOOLS_ARRAY <<< "$tools_list"
            for tool_name in "${TOOLS_ARRAY[@]}"; do
                if [ $((tool_index % 2)) -eq 0 ]; then
                    # Even index - slightly darker background
                    printf "\033[48;5;235m\033[%sm%s\033[0m " "$group_color" "$tool_name"
                else
                    # Odd index - slightly lighter background
                    printf "\033[48;5;238m\033[%sm%s\033[0m " "$group_color" "$tool_name"
                fi
                ((tool_index++))
            done
            echo ""
        fi
    done <<< "$group_tools_map"
    
    echo ""
    echo -e "\033[0;90mUse --tools for detailed view\033[0m"
    echo -e "\033[1;33mUsage: --<tool> [args]\033[0m"
}

# ============================================
# TOOL COMMAND HANDLERS
# ============================================
# Add your tool command handlers here following this pattern:
# 
# Function: Handle <command> tool command
# Usage: tool_<command>() {
#     # All arguments are passed as $@
#     # You can access individual args: $1, $2, $3, etc.
#     # Or pass all args: "$@"
#     
#     # Get working directory type from configuration
#     local working_dir=$(get_tool_working_dir "command_name")
#     
#     # Execute with automatic working directory handling
#     execute_file "normal" "path/to/your/script.sh" "$working_dir" "$@"
# }
# ============================================

# Function: Handle dual tool command
# Usage: bash Raw.sh --dual <arg1> <arg2> [arg3] [arg4...]
# This command can accept any number of arguments and passes them all
tool_dual() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "dual")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/dual.sh" "$working_dir" "$@"
    
    return 0
}

tool_testcheck() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "testcheck")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/testcheck.sh" "$working_dir" "$@"
    
    return 0
}

tool_info() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "info")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/jsinfo.sh" "$working_dir" "$@"
    
    return 0
}

tool_min() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "min")
    
    # Execute with automatic working directory handling
    execute_file "log" "./._/min/min" "$working_dir" "$@"
    
    return 0
}

tool_polish() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "polish")
    
    # Execute with automatic working directory handling
    execute_file "log" "./._/min/polish.sh" "$working_dir" "$@"
    
    return 0
}

tool_arch() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "arch")
    
    # Execute with automatic working directory handling
    execute_file "log" "./arch" "$working_dir" "$@"
    
    return 0
}

tool_chain() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "chain")
    
    # Execute with automatic working directory handling
    execute_file "log" "./._/._/._/chaincheck.sh" "$working_dir" "$@"
    
    return 0
}

tool_clean() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "clean")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/clean.sh" "$working_dir" "$@"
    
    return 0
}

tool_jsclean() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "jsclean")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/jsclean.sh" "$working_dir" "$@"
    
    return 0
}

tool_emb() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "emb")
    
    # Execute with automatic working directory handling
    execute_file "log" "../._/._/._/._/emb.sh" "$working_dir" "$@"
    
    return 0
}

# Function: Handle build tool command
# Usage: bash Raw.sh --build <path/to/arch_output>
# This command receives an arch_output file and runs the build pipeline:
# 1. Execute ./build (generates build_output.asm in caller dir)
# 2. Move build_output.asm to dev directory for tree/build.sh
# 3. Copy the input arch_output to the same dev directory level
# 4. Execute ./tree/build.sh
# 5. Move the final build_output.asm back to the caller directory (where arch_output is located)
tool_build() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "build")
    
    # Check if arch_output argument was provided
    if [ $# -eq 0 ]; then
        echo -e "\033[0;31mError: arch_output file path required\033[0m" >&2
        echo -e "\033[1;33mUsage: bash Raw.sh --build <path/to/arch_output>\033[0m" >&2
        return 1
    fi
    
    local arch_output_argument="$1"
    
    # Resolve arch_output path relative to caller's directory
    local arch_output_path=""
    if [[ "$arch_output_argument" = /* ]]; then
        # Absolute path
        arch_output_path="$arch_output_argument"
    else
        # Relative path - resolve from caller's directory
        arch_output_path="$CALLER_DIR/$arch_output_argument"
    fi
    
    # Check if arch_output file exists
    if [ ! -f "$arch_output_path" ]; then
        echo -e "\033[0;31mError: arch_output file not found: $arch_output_path\033[0m" >&2
        return 1
    fi
    
    # Get the directory containing the arch_output file
    local arch_output_directory=$(dirname "$arch_output_path")
    
    echo -e "\033[0;34mBuild process started...\033[0m"
    echo -e "\033[0;37mInput arch_output: $arch_output_path\033[0m"
    echo -e "\033[0;37mOutput directory: $arch_output_directory\033[0m"
    echo ""
    
    # Step 1: Execute ./build (generates build_output.asm in caller directory)
    echo -e "\033[1;33mStep 1/4: Generating build_output.asm...\033[0m"
    execute_file "silent" "./build" "$working_dir"
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mError: ./build execution failed\033[0m" >&2
        return 1
    fi
    echo -e "\033[0;32m✓ build_output.asm generated in caller directory\033[0m"
    
    # build_output.asm should now be in CALLER_DIR since ./build ran with "caller" working dir
    local generated_build_asm="$CALLER_DIR/build_output.asm"
    
    # Check if the file was actually generated
    if [ ! -f "$generated_build_asm" ]; then
        echo -e "\033[0;31mError: build_output.asm was not generated in $CALLER_DIR\033[0m" >&2
        return 1
    fi
    
    # Step 2: Move build_output.asm to the correct dev directory (same level as tree/build.sh expects)
    echo -e "\033[1;33mStep 2/4: Moving build_output.asm to build directory...\033[0m"
    local dev_build_asm="$SCRIPT_DIR/$EXECUTION_SOURCE/build_output.asm"
    mv_file "$generated_build_asm" "$dev_build_asm"
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mError: Failed to move build_output.asm to $dev_build_asm\033[0m" >&2
        return 1
    fi
    echo -e "\033[0;32m✓ build_output.asm moved to $dev_build_asm\033[0m"
    
    # Step 3: Copy the received arch_output to the same directory level as build_output.asm
    echo -e "\033[1;33mStep 3/4: Copying arch_output to build directory...\033[0m"
    local dev_arch_output="$SCRIPT_DIR/$EXECUTION_SOURCE/arch_output"
    cp_file "$arch_output_path" "$dev_arch_output"
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mError: Failed to copy arch_output to $dev_arch_output\033[0m" >&2
        return 1
    fi
    echo -e "\033[0;32m✓ arch_output copied to $dev_arch_output\033[0m"
    
    # Step 4: Execute ./tree/build.sh (uses both build_output.asm and arch_output from the dev directory)
    echo -e "\033[1;33mStep 4/4: Running tree/build.sh...\033[0m"
    execute_file "log" "./tree/build.sh" "$working_dir"
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mError: tree/build.sh execution failed\033[0m" >&2
        return 1
    fi
    echo -e "\033[0;32m✓ tree/build.sh completed\033[0m"
    
    # Step 5: Move the final build_output.asm back to the caller's arch_output directory
    echo -e "\033[1;33mMoving final build_output.asm to: $arch_output_directory/\033[0m"
    local final_asm="$arch_output_directory/build_output.asm"
    mv_file "$dev_build_asm" "$final_asm"
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mError: Failed to move final build_output.asm to $final_asm\033[0m" >&2
        return 1
    fi
    echo -e "\033[0;32m✓ Final build_output.asm saved to: $final_asm\033[0m"
    
    # Clean up: remove the copied arch_output from dev directory
    rm_file "$dev_arch_output"
    
    echo ""
    echo -e "\033[0;32mBuild process completed successfully!\033[0m"
    
    return 0
}

# Function: Handle bin tool command
# Usage: bash Raw.sh --bin [options] <build_output.asm>
# Options:
#   -o <output_name>    Specify the output binary name (optional)
# Examples:
#   bash Raw.sh --bin build_output.asm
#   bash Raw.sh --bin -o test build_output.asm
#   bash Raw.sh --bin -o myprogram build_output.asm
tool_bin() {
    # Get working directory from configuration
    local working_dir=$(get_tool_working_dir "bin")
    
    # Check if arguments were provided
    if [ $# -eq 0 ]; then
        echo -e "\033[0;31mError: build_output.asm file path required\033[0m" >&2
        echo -e "\033[1;33mUsage: bash Raw.sh --bin [-o <output_name>] <build_output.asm>\033[0m" >&2
        echo -e "\033[1;33mExamples:\033[0m" >&2
        echo -e "\033[1;33m  bash Raw.sh --bin build_output.asm\033[0m" >&2
        echo -e "\033[1;33m  bash Raw.sh --bin -o test build_output.asm\033[0m" >&2
        return 1
    fi
    
    # Parse arguments: look for -o flag
    local output_name=""
    local asm_file=""
    
    while [ $# -gt 0 ]; do
        if [ "$1" = "-o" ]; then
            # Next argument is the output name
            if [ $# -lt 2 ]; then
                echo -e "\033[0;31mError: -o requires an output name\033[0m" >&2
                return 1
            fi
            output_name="$2"
            shift 2
        elif [[ "$1" != -* ]]; then
            # This is the asm file
            asm_file="$1"
            shift
        else
            echo -e "\033[0;31mError: Unknown option: $1\033[0m" >&2
            return 1
        fi
    done
    
    # Check if asm file was provided
    if [ -z "$asm_file" ]; then
        echo -e "\033[0;31mError: build_output.asm file path required\033[0m" >&2
        return 1
    fi
    
    # Resolve asm file path relative to caller's directory
    local asm_file_path=""
    if [[ "$asm_file" = /* ]]; then
        # Absolute path
        asm_file_path="$asm_file"
    else
        # Relative path - resolve from caller's directory
        asm_file_path="$CALLER_DIR/$asm_file"
    fi
    
    # Check if asm file exists
    if [ ! -f "$asm_file_path" ]; then
        echo -e "\033[0;31mError: build_output.asm file not found: $asm_file_path\033[0m" >&2
        return 1
    fi
    
    echo -e "\033[0;34mBinary generation started...\033[0m"
    echo -e "\033[0;37mInput ASM: $asm_file_path\033[0m"
    
    # Use the generate_binary function
    generate_binary "$asm_file_path" "$output_name"
    
    return $?
}

# ============================================
# ADD MORE TOOL COMMANDS BELOW
# ============================================
# Example of adding a new command:
#
# Function: Handle compile tool command
# Usage: bash Raw.sh --compile <source_file> <output_file>
# tool_compile() {
#     local working_dir=$(get_tool_working_dir "compile")
#     execute_file "silent" "compiler/compile.sh" "$working_dir" "$@"
# }
#
# Example of adding a command with variable arguments:
#
# Function: Handle process tool command
# Usage: bash Raw.sh --process <file> [options...]
# tool_process() {
#     local working_dir=$(get_tool_working_dir "process")
#     execute_file "log" "processor/main.sh" "$working_dir" "$@"
# }
#
# IMPORTANT: When adding new tools:
#   1. Add their working directory config in get_tool_working_dir() function above
#   2. Add tool function handler (tool_<name>) here
#   3. Optionally add to a group in TOOL GROUPS CONFIGURATION section
# ============================================

# Function: Route tool commands to appropriate handler
handle_tool_command() {
    local command="$1"
    shift
    local args="$@"
    
    # If no command provided, show all available commands
    if [ -z "$command" ]; then
        display_tool_list_with_groups
        return 0
    fi
    
    # Check if the tool exists
    if ! declare -f "tool_${command}" > /dev/null 2>&1; then
        echo -e "${RED}Error: Unknown tool command '$command'${NC}" >&2
        echo ""
        display_tool_list_with_groups
        return 1
    fi
    
    # Execute the tool with arguments
    "tool_${command}" $args
    return $?
}

# ============================================
# SEQUENCE PATTERNS (Commented Examples)
# ============================================

# Pattern 1: Execute a single file in normal mode
# execute_file "normal" "path/to/your/file.sh"

# Pattern 2: Execute a single file in silent mode
# execute_file "silent" "path/to/your/file.asm"

# Pattern 3: Execute a single file in log mode
# execute_file "log" "path/to/your/binary"

# Pattern 4: Execute multiple files in sequence with same mode
# execute_sequence "normal" "file1.sh" "file2.asm" "file3"

# Pattern 5: Mixed mode execution (using different modes for different files)
# execute_file "silent" "setup.sh"
# execute_file "normal" "main.asm"
# execute_file "log" "processor"

# Pattern 6: Execute with additional arguments
# execute_file "normal" "script.sh" "--verbose" "--output=result.txt"

# Pattern 7: Change execution source temporarily
# EXECUTION_SOURCE="source" execute_file "normal" "script.sh"
# EXECUTION_SOURCE="dev" execute_file "normal" "script.sh"

# Pattern 8: Use JS file path as argument to an executable
# execute_file "normal" "processor" "$JS_FILE_PATH" "$JS_ARGS"

# Pattern 9: Execute with specific working directory type
# execute_file "normal" "processor.sh" "caller" "$@"
# execute_file "normal" "processor.sh" "file" "$@"
# execute_file "normal" "processor.sh" "global" "$@"

# Pattern 10: Conditional execution based on JS file processing
# if process_js_file "config.js" "some-arg"; then
#     execute_sequence "normal" "success.sh"
# else
#     execute_sequence "normal" "failure.sh"
# fi

# ============================================
# MAIN FLOW
# ============================================

main_flow() {
    # Step 1: Check for tool mode FIRST (before special modes)
    if [ "$TOOL_MODE" = "true" ]; then
        handle_tool_command "$TOOL_COMMAND" $TOOL_ARGS
        exit $?
    fi
    
    # Step 2: Check for --tools or --stools/--stool special mode
    if [ "$SPECIAL_MODE" = "--tools" ]; then
        display_tool_list_with_groups
        exit 0
    elif [ "$SPECIAL_MODE" = "--stools" ]; then
        display_compact_tool_list
        exit 0
    fi
    
    # Step 3: Check for CLI mode
    if [ "$CLI_MODE" = "true" ]; then
        # Check if dev directory exists
        if [ ! -d "$SCRIPT_DIR/dev" ]; then
            echo -e "${YELLOW}Dev directory doesn't exist. Building first...${NC}"
            compile_and_copy
            if [ $? -ne 0 ]; then
                echo -e "${RED}Build failed! Cannot start CLI mode.${NC}"
                exit 1
            fi
        fi
        
        # Start interactive CLI
        handle_cli
        exit $?
    fi
    
    # Step 4: Check for asm-only mode (--asm without JS file)
    if [ "$ASM_MODE" = "true" ] && [ "$ASM_ONLY_MODE" = "true" ]; then
        # Check if dev directory exists
        if [ ! -d "$SCRIPT_DIR/dev" ]; then
            echo -e "${YELLOW}Dev directory doesn't exist. Building first...${NC}"
            compile_and_copy
            if [ $? -ne 0 ]; then
                echo -e "${RED}Build failed! Cannot copy asm file.${NC}"
                exit 1
            fi
        fi
        
        # Copy the asm file to caller directory
        copy_asm_to_caller
        exit $?
    fi
    
    # Step 5: Check for special modes
    if [ "$SPECIAL_MODE" = "--reset" ]; then
        handle_reset
        exit $?
     elif [ "$SPECIAL_MODE" = "--test" ]; then
        handle_test "$@"
        exit $?
    fi
    
    # Step 6: Normal execution flow (only if no special mode)
    # Compile and copy only if ./dev doesn't exist (based on script's directory)
    if [ ! -d "$SCRIPT_DIR/dev" ]; then
        compile_and_copy
        if [ $? -ne 0 ]; then
            if [ "$VERBOSE_DEV" = "true" ]; then
                echo -e "${RED}Compilation failed! Exiting...${NC}"
            fi
            exit 1
        fi
    fi
    
    # Step 7: Process the JS file if provided
    if [ -n "$JS_FILE" ]; then
        process_js_file "$JS_FILE" $JS_ARGS
        if [ $? -ne 0 ]; then
            exit 1
        fi
        
        # ============================================
        # NOW EXECUTE YOUR FILES USING THE JS PATH
        # ============================================

        # Start execution timer if in log mode
        if [ "$FORCE_LOG_MODE" = "true" ]; then
            start_timer
        fi

        OUTPUT_JS="$SCRIPT_DIR/output.js" 
        ARCH_OUTPUT="$SCRIPT_DIR/arch_output" 
        
        # Execute the processing pipeline (silent steps)
        execute_file "silent" "./._/min/min" "$JS_FILE_PATH" 
        execute_file "silent" "./._/min/polish.sh" "$OUTPUT_JS"
        execute_file "silent" "./build"
        mv_file "build_output.asm" "$EXECUTION_SOURCE/build_output.asm"
        execute_file "silent" "./arch" "$OUTPUT_JS"
        mv_file "arch_output" "$EXECUTION_SOURCE/arch_output"
        rm_file "$SCRIPT_DIR/output.js"
        
        # Execute tree/build.sh with --verbose flag if verbose mode is active
        if [ "$VERBOSE_MODE" = "true" ]; then
            execute_file "silent" "./tree/build.sh" "--verbose"
        else
            execute_file "silent" "./tree/build.sh"
        fi
        
        # Check if binary output mode is active (--bin flag was used)
        if [ "$BIN_OUTPUT_MODE" = "true" ]; then
            # Get the build_output.asm path
            local asm_file="$SCRIPT_DIR/$EXECUTION_SOURCE/build_output.asm"
            
            # Generate binary using basm.sh
            generate_binary "$asm_file" "$BIN_OUTPUT_NAME"
        elif [ "$ASM_MODE" = "true" ]; then
            # ASM mode: Copy the asm file to caller directory without executing
            copy_asm_to_caller
        else
            # Normal mode: Execute the final binary
            execute_file "log" "./build_output.asm"
        fi
        
        # Display execution time if in log mode
        if [ "$FORCE_LOG_MODE" = "true" ]; then
            stop_timer
        fi
        
    else
        # NEW: Check if dev mode is enabled and no JS file provided
        if [ "$CONFIG_DEV_MODE" = "true" ]; then
            # Dev mode enabled - launch CLI instead of showing usage
            CLI_MODE="true"
            # Check if dev directory exists
            if [ ! -d "$SCRIPT_DIR/dev" ]; then
                echo -e "${YELLOW}Dev directory doesn't exist. Building first...${NC}"
                compile_and_copy
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Build failed! Cannot start CLI mode.${NC}"
                    exit 1
                fi
            fi
            handle_cli
            exit $?
        else
            show_usage
            exit 1
        fi
    fi
}

# Execute main flow with all arguments
main_flow "$@"