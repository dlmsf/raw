#!/bin/bash

# Raw.sh - Main build script with conditional compilation (silent mode)

# ============================================
# SAVE CALLER'S DIRECTORY AND RESOLVE JS FILE FIRST
# ============================================
CALLER_DIR="$(pwd)"  # Save where the script was called from

# Check for special flags FIRST before processing JS file
SPECIAL_MODE=""
FORCE_LOG_MODE="false"  # New flag for --log (only for normal JS execution)
TOOL_MODE="false"       # New flag for --tool
TOOL_COMMAND=""         # Store the tool command
TOOL_ARGS=""           # Store tool arguments

if [ $# -gt 0 ]; then
    if [ "$1" = "--test" ] || [ "$1" = "--reset" ]; then
        SPECIAL_MODE="$1"
        shift  # Remove the flag from arguments
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
    fi
fi

# Only check for --log if we're NOT in a special mode or tool mode
if [ -z "$SPECIAL_MODE" ] && [ "$TOOL_MODE" = "false" ] && [ $# -gt 0 ]; then
    if [ "$1" = "--log" ]; then
        FORCE_LOG_MODE="true"
        shift  # Remove the flag from arguments
    fi
fi

# Process JS file argument BEFORE changing directories (only if not in tool mode)
JS_FILE=""
JS_ARGS=""
if [ "$TOOL_MODE" = "false" ] && [ $# -gt 0 ] && [ -z "$SPECIAL_MODE" ]; then
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

# ============================================
# GET SCRIPT'S OWN DIRECTORY (not caller's directory)
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"  # Change to script's directory to ensure consistent paths

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

# Function: Get the appropriate basm script path
get_basm_script() {
    local mode="$1"  # normal, silent, log
    
    # Base path for basm scripts (based on script's directory)
    local basm_base="$SCRIPT_DIR/dev/basm"
    
    case "$mode" in
        "silent")
            echo "$basm_base/sbasm.sh"
            ;;
        "log")
            echo "$basm_base/logbasm.sh"
            ;;
        "normal"|*)
            echo "$basm_base/basm.sh"
            ;;
    esac
}

# Function: Resolve file path based on EXECUTION_SOURCE
# This is for execution files (scripts, asm, binaries) NOT for the JS file
resolve_file_path() {
    local file_path="$1"
    
    # Remove leading ./ if present
    file_path="${file_path#./}"
    
    case "$EXECUTION_SOURCE" in
        "source")
            # Use ._ directory (based on script's directory)
            echo "$SCRIPT_DIR/._/$file_path"
            ;;
        "dev"|*)
            # Use dev directory (based on script's directory)
            echo "$SCRIPT_DIR/dev/$file_path"
            ;;
    esac
}

# Function: Execute a file using basm
# Usage: execute_file <mode> <file_path> [additional_args...]
#   mode: normal, silent, log
#   file_path: path relative to dev or ._ directory
execute_file() {
    local mode="$1"
    local file_path="$2"
    shift 2
    local additional_args="$@"
    
    # Override mode if FORCE_LOG_MODE is true (only affects normal JS execution)
    if [ "$FORCE_LOG_MODE" = "true" ]; then
        mode="log"
    fi
    
    # Get the basm script
    local basm_script=$(get_basm_script "$mode")
    
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
    
    # Execute with appropriate verbosity
    case "$mode" in
        "silent")
            # Silent mode: suppress all output from basm
            if [[ "$full_path" == *.sh ]]; then
                bash "$full_path" $additional_args >/dev/null 2>&1
            else
                "$basm_script" "$full_path" $additional_args >/dev/null 2>&1
            fi
            ;;
        "log")
            # Log mode: show execution output but not compilation logs
            if [[ "$full_path" == *.sh ]]; then
                bash "$full_path" $additional_args
            else
                "$basm_script" "$full_path" $additional_args
            fi
            ;;
        "normal"|*)
            # Normal mode: show all output
            if [[ "$full_path" == *.sh ]]; then
                bash "$full_path" $additional_args
            else
                "$basm_script" "$full_path" $additional_args
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
# Function: Compile and link all .asm files, copy .sh files and binaries to /dev directory
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
            cp "$sh_file" "$output_file" 2>/dev/null
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
            cp "$binary_file" "$output_file" 2>/dev/null
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
            cp "$basm_file" "$output_file" 2>/dev/null
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
    echo -e "${YELLOW}Usage: bash Raw.sh [--log] <path/to/file.js> [args...]${NC}"
    echo -e "${YELLOW}       bash Raw.sh --reset${NC}"
    echo -e "${YELLOW}       bash Raw.sh --test${NC}"
    echo -e "${YELLOW}       bash Raw.sh --tool [command] [args...]${NC}"
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
        return 0
    else
        echo -e "${RED}Reset failed during compilation!${NC}"
        return 1
    fi
}

# Handle --test mode
handle_test() {
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
    local test_script="$SCRIPT_DIR/dev/._/._/runtest.sh"
    
    if [ ! -f "$test_script" ]; then
        echo -e "${RED}Error: Test script not found at $test_script${NC}"
        return 1
    fi
    
    # Make it executable
    chmod +x "$test_script" 2>/dev/null
    
    # Execute with bash
    echo -e "${GREEN}Running test script...${NC}"
    bash "$test_script"
    local test_result=$?
    
    if [ $test_result -eq 0 ]; then
        echo -e "${GREEN}Tests completed successfully!${NC}"
    else
        echo -e "${RED}Tests failed with exit code: $test_result${NC}"
    fi
    
    return $test_result
}

# ============================================
# TOOL COMMANDS SYSTEM
# ============================================

# Function: Display all available tool commands
show_tool_commands() {
    echo -e "${BLUE}=== Available Tool Commands ===${NC}"
    echo ""
    echo -e "${GREEN}Usage: bash Raw.sh --tool <command> [args...]${NC}"
    echo ""
    echo -e "${YELLOW}Available commands:${NC}"
    echo ""
    
    # List all registered commands
    echo -e "  ${GREEN}dual${NC}         - Example command that processes two arguments"
    echo -e "                    Usage: bash Raw.sh --tool dual <arg1> <arg2>"
    echo ""
    
    # Instructions for adding new commands
    echo -e "${BLUE}=== Adding New Commands ===${NC}"
    echo -e "To add a new command, create a function named: tool_<command_name>"
    echo -e "The function will receive all arguments after the command name"
    echo ""
    echo -e "${YELLOW}Example template:${NC}"
    echo -e "# Function: Handle <command> tool command"
    echo -e "# Usage: tool_<command>() {"
    echo -e "#     local arg1=\"\$1\""
    echo -e "#     local arg2=\"\$2\""
    echo -e "#     "
    echo -e "#     # Your execution logic here"
    echo -e "#     execute_file \"normal\" \"path/to/script.sh\" \"\$arg1\" \"\$arg2\""
    echo -e "# }"
    echo ""
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
#     # Your execution logic here
#     # Use execute_file with all arguments
#     execute_file "normal" "path/to/your/script.sh" "$@"
# }
# ============================================

# Function: Handle dual tool command
# Usage: bash Raw.sh --tool dual <arg1> <arg2> [arg3] [arg4...]
# This command can accept any number of arguments and passes them all
tool_dual() {
    
    # Count and display all arguments
    local arg_count=$#
   
     execute_file "log" "../._/._/._/dual.sh" "$@"
    
    return 0
}

# ============================================
# ADD MORE TOOL COMMANDS BELOW
# ============================================
# Example of adding a new command:
#
# Function: Handle compile tool command
# Usage: bash Raw.sh --tool compile <source_file> <output_file>
# tool_compile() {
#     local source_file="$1"
#     local output_file="$2"
#     
#     if [ -z "$source_file" ] || [ -z "$output_file" ]; then
#         echo -e "${RED}Error: compile command requires source and output files${NC}" >&2
#         return 1
#     fi
#     
#     execute_file "silent" "compiler/compile.sh" "$source_file" "$output_file"
# }
#
# Example of adding a command with variable arguments:
#
# Function: Handle process tool command
# Usage: bash Raw.sh --tool process <file> [options...]
# tool_process() {
#     local file="$1"
#     shift
#     local options="$@"
#     
#     if [ -z "$file" ]; then
#         echo -e "${RED}Error: process command requires a file${NC}" >&2
#         return 1
#     fi
#     
#     execute_file "log" "processor/main.sh" "$file" $options
# }
# ============================================

# Function: Route tool commands to appropriate handler
handle_tool_command() {
    local command="$1"
    shift
    local args="$@"
    
    # If no command provided, show all available commands
    if [ -z "$command" ]; then
        show_tool_commands
        return 0
    fi
    
    # Route to appropriate command handler
    case "$command" in
        "dual")
            tool_dual $args
            return $?
            ;;
        # Add more command cases here following this pattern:
        # "your_command")
        #     tool_your_command $args
        #     return $?
        #     ;;
        *)
            echo -e "${RED}Error: Unknown tool command '$command'${NC}" >&2
            echo ""
            show_tool_commands
            return 1
            ;;
    esac
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

# Pattern 9: Conditional execution based on JS file processing
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
    
    # Step 2: Check for special modes
    if [ "$SPECIAL_MODE" = "--reset" ]; then
        handle_reset
        exit $?
    elif [ "$SPECIAL_MODE" = "--test" ]; then
        handle_test
        exit $?
    fi
    
    # Step 3: Normal execution flow (only if no special mode)
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
    
    # Step 4: Process the JS file if provided
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
        
        # Example: Execute a processor with the JS file as argument
        #execute_file "normal" "path/to/processor" "$JS_FILE_PATH" "$JS_ARGS"
        execute_file "silent" "./._/min/min" "$JS_FILE_PATH" 
        execute_file "silent" "./._/min/polish/functions.sh" "$OUTPUT_JS"
        execute_file "silent" "./._/min/polish/const.sh" "$OUTPUT_JS"
        execute_file "silent" "./._/min/polish/let.sh" "$OUTPUT_JS"
        execute_file "silent" "./build"
        mv_file "build_output.asm" "$EXECUTION_SOURCE/build_output.asm"
        execute_file "silent" "./arch" "$OUTPUT_JS"
        mv_file "arch_output" "$EXECUTION_SOURCE/arch_output"
        rm_file "$SCRIPT_DIR/output.js"
        execute_file "silent" "./tree/build.sh"
        execute_file "log" "./build_output.asm"
        
        # Display execution time if in log mode
        if [ "$FORCE_LOG_MODE" = "true" ]; then
            stop_timer
        fi
    else
        show_usage
        exit 1
    fi
}

# Execute main flow with all arguments
main_flow "$@"
