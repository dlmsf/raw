#!/bin/sh

# basm.sh - Universal runner for .asm, .sh, and binary files with fallback logic
# Compatible with both bash and ash
# IMPORTANT: All execution happens in the CALLER's directory, not where basm.sh is located
#
# Usage:
#   basm.sh [--silent|--log] [--bin|--o|-o] <file> [args...]
#     --silent, -s    : suppress ALL output (like old sbasm.sh)
#     --log, -l       : show only program/script output (like old logbasm.sh)
#     --bin, --o, -o  : generate binary only, don't execute (only for .asm files)
#     (no flag)       : verbose mode (original basm.sh)

# --- Parse mode flags ------------------------------------------------
MODE="normal"
OUTPUT_ONLY=false
OUTPUT_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --silent|-s)
            MODE="silent"
            shift
            ;;
        --log|-l)
            MODE="log"
            shift
            ;;
        --bin|--o|-o)
            OUTPUT_ONLY=true
            shift
            # Check if next argument could be an output filename
            if [ $# -gt 0 ]; then
                # Don't consume the next argument if it's a flag or looks like an input file
                case "$1" in
                    --*|-*)
                        # It's another flag, don't consume it
                        ;;
                    *.asm)
                        # It's an assembly file, don't consume it as output name
                        ;;
                    *)
                        # Check if it's an existing .asm file (case insensitive extension check)
                        if [ -f "$1" ]; then
                            case "$1" in
                                *.asm|*.ASM)
                                    # It's an existing .asm file, don't consume it
                                    ;;
                                *)
                                    # It's some other existing file, treat as output name
                                    OUTPUT_NAME="$1"
                                    shift
                                    ;;
                            esac
                        else
                            # File doesn't exist, could be output name
                            # But check if it ends with .asm (likely input file that doesn't exist yet)
                            case "$1" in
                                *.asm|*.ASM)
                                    # Likely an input file, don't consume
                                    ;;
                                *)
                                    # Treat as output name
                                    OUTPUT_NAME="$1"
                                    shift
                                    ;;
                            esac
                        fi
                        ;;
                esac
            fi
            ;;
        *)
            break
            ;;
    esac
done

# --- Color setup (unchanged) ---------------------------------------
if [ -n "$BASH_VERSION" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; NC=''
fi

# print_color: normal mode prints to stdout; errors (red) go to stderr if not silent
# In log mode, only red errors and program output separators are shown
print_color() {
    local color="$1"
    local message="$2"

    if [ "$color" = "red" ]; then
        if [ "$MODE" != "silent" ]; then
            if [ -n "$BASH_VERSION" ]; then
                echo -e "${RED}${message}${NC}" >&2
            else
                printf "\033[0;31m%s\033[0m\n" "$message" >&2
            fi
        fi
    else
        if [ "$MODE" = "normal" ]; then
            if [ -n "$BASH_VERSION" ]; then
                case "$color" in
                    green) echo -e "${GREEN}${message}${NC}" ;;
                    yellow) echo -e "${YELLOW}${message}${NC}" ;;
                    blue) echo -e "${BLUE}${message}${NC}" ;;
                    cyan) echo -e "${CYAN}${message}${NC}" ;;
                    magenta) echo -e "${MAGENTA}${message}${NC}" ;;
                    *) echo "$message" ;;
                esac
            else
                case "$color" in
                    green) printf "\033[0;32m%s\033[0m\n" "$message" ;;
                    yellow) printf "\033[1;33m%s\033[0m\n" "$message" ;;
                    blue) printf "\033[0;34m%s\033[0m\n" "$message" ;;
                    cyan) printf "\033[0;36m%s\033[0m\n" "$message" ;;
                    magenta) printf "\033[0;35m%s\033[0m\n" "$message" ;;
                    *) printf "%s\n" "$message" ;;
                esac
            fi
        fi
    fi
}

# print_important: shows message in normal AND log mode (but not silent)
print_important() {
    local color="$1"
    local message="$2"
    
    if [ "$MODE" != "silent" ]; then
        if [ "$color" = "red" ]; then
            if [ -n "$BASH_VERSION" ]; then
                echo -e "${RED}${message}${NC}" >&2
            else
                printf "\033[0;31m%s\033[0m\n" "$message" >&2
            fi
        else
            if [ -n "$BASH_VERSION" ]; then
                case "$color" in
                    green) echo -e "${GREEN}${message}${NC}" ;;
                    yellow) echo -e "${YELLOW}${message}${NC}" ;;
                    blue) echo -e "${BLUE}${message}${NC}" ;;
                    cyan) echo -e "${CYAN}${message}${NC}" ;;
                    magenta) echo -e "${MAGENTA}${message}${NC}" ;;
                    *) echo "$message" ;;
                esac
            else
                case "$color" in
                    green) printf "\033[0;32m%s\033[0m\n" "$message" ;;
                    yellow) printf "\033[1;33m%s\033[0m\n" "$message" ;;
                    blue) printf "\033[0;34m%s\033[0m\n" "$message" ;;
                    cyan) printf "\033[0;36m%s\033[0m\n" "$message" ;;
                    magenta) printf "\033[0;35m%s\033[0m\n" "$message" ;;
                    *) printf "%s\n" "$message" ;;
                esac
            fi
        fi
    fi
}

# print_timing: ONLY shows timing in default (normal) mode
print_timing() {
    if [ "$MODE" = "normal" ]; then
        print_color "cyan" "Total execution time: $1"
    fi
}

# --- Timing helper functions ---------------------------------------
# Get precise timestamp in nanoseconds (or microseconds as fallback)
get_time_ns() {
    if date +%s%N >/dev/null 2>&1; then
        date +%s%N
    elif [ -f /proc/uptime ]; then
        # Fallback: use /proc/uptime for centisecond precision
        awk '{printf "%d%02d0000000", $1, $2}' /proc/uptime 2>/dev/null
    else
        # Last resort: seconds only
        date +%s000000000
    fi
}

# Calculate and format elapsed time
format_elapsed() {
    local start_ns="$1"
    local end_ns="$2"
    local elapsed_ns=$((end_ns - start_ns))
    
    # Convert to human-readable format with milliseconds
    local seconds=$((elapsed_ns / 1000000000))
    local milliseconds=$(((elapsed_ns % 1000000000) / 1000000))
    local microseconds=$(((elapsed_ns % 1000000) / 1000))
    local nanoseconds=$((elapsed_ns % 1000))
    
    if [ $seconds -gt 0 ]; then
        printf "%d.%03d%03d%03d seconds" $seconds $milliseconds $microseconds $nanoseconds
    elif [ $milliseconds -gt 0 ]; then
        printf "%d.%03d%03d ms" $milliseconds $microseconds $nanoseconds
    elif [ $microseconds -gt 0 ]; then
        printf "%d.%03d µs" $microseconds $nanoseconds
    else
        printf "%d ns" $nanoseconds
    fi
}

# --- Banner (only in normal mode) ----------------------------------
if [ "$MODE" = "normal" ]; then
    print_color "cyan" "basm - Universal Assembly/Bash/Binary Runner"
    print_color "yellow" "Run .asm, .sh, or binary files with intelligent fallback"
    if [ "$OUTPUT_ONLY" = true ]; then
        print_color "magenta" "Mode: Binary generation only (no execution)"
    fi
    print_color "blue" "Note: Execution happens in CALLER's directory: $(pwd)"
    echo ""
fi

CALLER_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Input check ---------------------------------------------------
if [ $# -lt 1 ]; then
    if [ "$MODE" != "silent" ]; then
        print_color "red" "Usage: $0 [--silent|--log] [--bin [output_name]] <file> [args...]"
        if [ "$MODE" = "normal" ]; then
            print_color "yellow" "Supported file types: .asm, .sh, or any executable binary"
            print_color "yellow" "Examples:"
            echo "  $0 hello.asm"
            echo "  $0 script.sh arg1 arg2"
            echo "  $0 myprogram arg1 arg2"
            echo "  $0 file.asm arg1 arg2  # Will fallback to file.sh if .asm not found"
            echo "  $0 program arg1 arg2   # Will fallback to program.asm, then program.sh"
            echo "  $0 --bin hello.asm     # Compile only, output to a.out"
            echo "  $0 -o hello.asm        # Compile only, output to a.out"
            echo "  $0 --bin myprog hello.asm  # Compile to myprog"
            echo "  $0 -o myprog hello.asm     # Compile to myprog"
            echo "  $0 --silent --bin hello.asm # Silent binary generation"
            echo "  $0 --log -o hello.asm      # Log mode binary generation"
        fi
    fi
    exit 1
fi

INPUT_FILE="$1"
shift
PROGRAM_ARGS="$@"

# --- Validate OUTPUT_ONLY mode ---
if [ "$OUTPUT_ONLY" = true ]; then
    # Check if input is .asm file
    case "$INPUT_FILE" in
        *.asm|*.ASM)
            if [ "$MODE" = "normal" ]; then
                print_color "magenta" "Binary generation mode activated for: $INPUT_FILE"
                if [ -n "$OUTPUT_NAME" ]; then
                    print_color "magenta" "Output will be saved as: $OUTPUT_NAME"
                else
                    print_color "magenta" "Output will be saved as: a.out"
                fi
            fi
            ;;
        *)
            if [ "$MODE" != "silent" ]; then
                print_color "red" "Error: --bin/-o flag only works with .asm files"
                print_color "yellow" "Got file: $INPUT_FILE"
            fi
            exit 1
            ;;
    esac
fi

# --- Shell selection -----------------------------------------------
if [ -n "$BASH_VERSION" ]; then
    RUNNER_SHELL="bash"
    RUNNER_SHELL_PATH="$(command -v bash 2>/dev/null || echo "/bin/bash")"
else
    RUNNER_SHELL="sh"
    RUNNER_SHELL_PATH="$(command -v sh 2>/dev/null || echo "/bin/sh")"
fi

if [ "$MODE" = "normal" ]; then
    print_color "blue" "Using $RUNNER_SHELL for .sh file execution"
    print_color "blue" "Caller directory: $CALLER_DIR"
    print_color "blue" "Script directory: $SCRIPT_DIR"
fi

# --- File detection ------------------------------------------------
detect_file_type() {
    local filename="$1"
    if [ -f "$CALLER_DIR/$filename" ]; then
        local full_path="$CALLER_DIR/$filename"
    elif [ -f "$filename" ] && [ "$(dirname "$(realpath "$filename" 2>/dev/null || echo "$filename")")" != "$SCRIPT_DIR" ]; then
        local full_path="$filename"
    elif [ -f "$filename" ]; then
        local full_path="$filename"
    else
        echo "not_found"
        return
    fi

    case "$full_path" in
        *.asm|*.ASM) echo "asm:$full_path" ;;
        *.sh|*.SH) echo "sh:$full_path" ;;
        *)
            if [ -x "$full_path" ]; then
                echo "binary:$full_path"
            elif head -n 1 "$full_path" 2>/dev/null | grep -q "^#!"; then
                echo "script:$full_path"
            elif command -v file >/dev/null 2>&1; then
                if file "$full_path" 2>/dev/null | grep -q -e "ELF" -e "executable" -e "Mach-O" -e "shared object"; then
                    echo "binary:$full_path"
                else
                    echo "unknown:$full_path"
                fi
            else
                echo "unknown:$full_path"
            fi
            ;;
    esac
}

find_alternative() {
    local original="$1"
    local current_type="$2"
    local basename="${original%.*}"
    local extension=""
    if [ "$basename" != "$original" ]; then
        extension="${original##*.}"
    fi

    check_file() {
        local file="$1"
        if [ -f "$CALLER_DIR/$file" ]; then
            echo "$CALLER_DIR/$file"; return 0
        elif [ -f "$file" ]; then
            echo "$file"; return 0
        elif [ -f "$SCRIPT_DIR/$file" ]; then
            echo "$SCRIPT_DIR/$file"; return 0
        else
            return 1
        fi
    }

    case "$current_type" in
        asm|asm:*)
            local alt_file=""
            alt_file=$(check_file "${basename}.sh") || alt_file=$(check_file "$basename") || alt_file=""
            echo "$alt_file" ;;
        sh|sh:*)
            local alt_file=""
            alt_file=$(check_file "${basename}.asm") || alt_file=$(check_file "$basename") || alt_file=""
            echo "$alt_file" ;;
        binary|binary:*|unknown|unknown:*)
            local alt_file=""
            alt_file=$(check_file "${basename}.asm") || alt_file=$(check_file "${basename}.sh") || alt_file=""
            echo "$alt_file" ;;
        not_found)
            if [ -n "$extension" ]; then
                local alt_file=""
                alt_file=$(check_file "${basename}.asm") || alt_file=$(check_file "${basename}.sh") || alt_file=$(check_file "$basename") || alt_file=""
                echo "$alt_file"
            else
                local alt_file=""
                alt_file=$(check_file "${original}.asm") || alt_file=$(check_file "${original}.sh") || alt_file=$(check_file "$original") || alt_file=""
                echo "$alt_file"
            fi ;;
        *) echo "" ;;
    esac
}

# --- Runners -------------------------------------------------------
run_asm() {
    local asm_file="$1"
    local args="$2"

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Running Assembly file: $asm_file"
        print_color "blue" "Execution directory: $CALLER_DIR"
    fi

    ARCH=""; FORMAT=""
    case "$(uname -m)" in
        x86_64|amd64) ARCH="x86_64"; FORMAT="elf64" ;;
        i386|i486|i586|i686) ARCH="i386"; FORMAT="elf32" ;;
        arm|armv7l|armv8l) ARCH="arm"; FORMAT="elf32" ;;
        aarch64|arm64) ARCH="arm"; FORMAT="elf64" ;;
        *) print_color "red" "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    if [ "$MODE" = "normal" ]; then
        print_color "green" "Detected architecture: $ARCH (using $FORMAT format)"
    fi

    NASM_BINARY="${SCRIPT_DIR}/${ARCH}-linux/nasm-${ARCH}-linux"
    if [ ! -f "$NASM_BINARY" ]; then
        print_color "red" "NASM binary not found at: $NASM_BINARY"
        if [ "$MODE" = "normal" ]; then
            print_color "yellow" "Expected path: $NASM_BINARY"
            print_color "yellow" "Available architectures:"
            for dir in "${SCRIPT_DIR}"/*-linux; do
                [ -d "$dir" ] && echo "  - $(basename "$dir")"
            done
        fi
        return 1
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "green" "Using NASM binary: $NASM_BINARY"
    fi
    chmod +x "$NASM_BINARY" 2>/dev/null

    BASENAME="$(basename "$asm_file" .asm)"
    BASENAME="$(basename "$BASENAME" .ASM)"
    OUTPUT_DIR="$CALLER_DIR/.basm_tmp_$$"
    OBJECT_FILE="$OUTPUT_DIR/${BASENAME}.o"
    
    # Determine binary output location
    if [ "$OUTPUT_ONLY" = true ]; then
        if [ -n "$OUTPUT_NAME" ]; then
            BINARY_FILE="$CALLER_DIR/$OUTPUT_NAME"
        else
            BINARY_FILE="$CALLER_DIR/a.out"
        fi
    else
        BINARY_FILE="$OUTPUT_DIR/${BASENAME}"
    fi

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

        # Compile (with optional warning suppression)
    NASM_FLAGS="-f $FORMAT"
    # Uncomment next line to suppress the implicit ABS deprecation warning
    # NASM_FLAGS="$NASM_FLAGS -w-imp-abs-deprecated"
    
    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Step 1: Compiling $asm_file..."
        "$NASM_BINARY" $NASM_FLAGS "$asm_file" -o "$OBJECT_FILE"
        NASM_EXIT=$?
    else
        "$NASM_BINARY" $NASM_FLAGS "$asm_file" -o "$OBJECT_FILE" > /dev/null 2>&1
        NASM_EXIT=$?
    fi

    if [ $NASM_EXIT -ne 0 ]; then
        print_color "red" "✗ Compilation failed!"
        if [ "$MODE" = "normal" ]; then
            print_color "yellow" "Exit code: $NASM_EXIT"
        fi
        rm -rf "$OUTPUT_DIR"
        return 1
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "green" "✓ Compilation successful"
    fi

    # Link
    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Step 2: Linking object file..."
        LD_OUTPUT="$(ld "$OBJECT_FILE" -o "$BINARY_FILE" 2>&1)"
        LD_EXIT=$?
    else
        ld "$OBJECT_FILE" -o "$BINARY_FILE" > /dev/null 2>&1
        LD_EXIT=$?
    fi

    if [ $LD_EXIT -ne 0 ]; then
        print_color "red" "✗ Linking failed!"
        if [ "$MODE" = "normal" ]; then
            print_color "yellow" "Exit code: $LD_EXIT"
            print_color "yellow" "Linking output:"
            echo "$LD_OUTPUT"
        fi
        rm -rf "$OUTPUT_DIR"
        # Clean up binary if it was partially created
        [ -f "$BINARY_FILE" ] && rm -f "$BINARY_FILE"
        return 1
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "green" "✓ Linking successful"
    fi

    chmod +x "$BINARY_FILE" 2>/dev/null
    rm -f "$OBJECT_FILE"

    # If output only mode, stop here
    if [ "$OUTPUT_ONLY" = true ]; then
        rm -rf "$OUTPUT_DIR"
        if [ "$MODE" = "normal" ]; then
            print_color "green" "✓ Binary generated successfully: $BINARY_FILE"
            print_color "yellow" "Binary location: $BINARY_FILE"
        elif [ "$MODE" = "log" ]; then
            print_important "green" "✓ Binary generated: $BINARY_FILE"
        fi
        # In silent mode, just print the path to stdout (useful for scripting)
        if [ "$MODE" = "silent" ]; then
            echo "$BINARY_FILE"
        fi
        return 0
    fi

    # Execute with timing (only in normal mode)
    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Step 3: Running $BASENAME..."
        if [ -n "$args" ]; then
            print_color "yellow" "Arguments: $args"
        fi
        print_color "blue" "========== PROGRAM OUTPUT =========="
    fi

    # Measure execution time only in normal mode
    if [ "$MODE" = "normal" ]; then
        local start_time=$(get_time_ns)
    fi
    
    if [ "$MODE" = "silent" ]; then
        (cd "$CALLER_DIR" && "$BINARY_FILE" $args) > /dev/null 2>&1
    else
        (cd "$CALLER_DIR" && "$BINARY_FILE" $args)
    fi
    PROGRAM_EXIT=$?
    
    if [ "$MODE" = "normal" ]; then
        local end_time=$(get_time_ns)
        local elapsed=$(format_elapsed "$start_time" "$end_time")
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "===================================="
        print_color "yellow" "Program exited with code: $PROGRAM_EXIT"
        print_timing "$elapsed"
    fi

    rm -rf "$OUTPUT_DIR"

    if [ "$MODE" = "normal" ]; then
        print_color "green" "✓ Cleanup complete"
    fi

    return $PROGRAM_EXIT
}

run_sh() {
    local sh_file="$1"
    local args="$2"

    # Can't use --bin with .sh files, but this check is done earlier
    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Running shell script: $sh_file"
        print_color "yellow" "Using shell: $RUNNER_SHELL"
        print_color "blue" "Execution directory: $CALLER_DIR"
        if [ -n "$args" ]; then print_color "yellow" "Arguments: $args"; fi
        print_color "blue" "========== SCRIPT OUTPUT =========="
    fi

    # Measure execution time only in normal mode
    if [ "$MODE" = "normal" ]; then
        local start_time=$(get_time_ns)
    fi
    
    if [ "$MODE" = "silent" ]; then
        (cd "$CALLER_DIR" && "$RUNNER_SHELL_PATH" "$sh_file" $args) > /dev/null 2>&1
    else
        (cd "$CALLER_DIR" && "$RUNNER_SHELL_PATH" "$sh_file" $args)
    fi
    SCRIPT_EXIT=$?
    
    if [ "$MODE" = "normal" ]; then
        local end_time=$(get_time_ns)
        local elapsed=$(format_elapsed "$start_time" "$end_time")
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "==================================="
        print_color "yellow" "Script exited with code: $SCRIPT_EXIT"
        print_timing "$elapsed"
    fi

    return $SCRIPT_EXIT
}

run_binary() {
    local binary_file="$1"
    local args="$2"

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Running binary: $binary_file"
        print_color "blue" "Execution directory: $CALLER_DIR"
        if [ -n "$args" ]; then print_color "yellow" "Arguments: $args"; fi
        print_color "blue" "========== PROGRAM OUTPUT =========="
    fi

    # Measure execution time only in normal mode
    if [ "$MODE" = "normal" ]; then
        local start_time=$(get_time_ns)
    fi
    
    if [ "$MODE" = "silent" ]; then
        (cd "$CALLER_DIR" && "$binary_file" $args) > /dev/null 2>&1
    else
        (cd "$CALLER_DIR" && "$binary_file" $args)
    fi
    BINARY_EXIT=$?
    
    if [ "$MODE" = "normal" ]; then
        local end_time=$(get_time_ns)
        local elapsed=$(format_elapsed "$start_time" "$end_time")
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "===================================="
        print_color "yellow" "Program exited with code: $BINARY_EXIT"
        print_timing "$elapsed"
    fi

    return $BINARY_EXIT
}

run_script() {
    local script_file="$1"
    local args="$2"

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "Running script: $script_file"
        print_color "blue" "Execution directory: $CALLER_DIR"
        if [ -n "$args" ]; then print_color "yellow" "Arguments: $args"; fi
        print_color "blue" "========== SCRIPT OUTPUT =========="
    fi

    # Measure execution time only in normal mode
    if [ "$MODE" = "normal" ]; then
        local start_time=$(get_time_ns)
    fi
    
    if [ "$MODE" = "silent" ]; then
        (cd "$CALLER_DIR" && "$script_file" $args) > /dev/null 2>&1
    else
        (cd "$CALLER_DIR" && "$script_file" $args)
    fi
    SCRIPT_EXIT=$?
    
    if [ "$MODE" = "normal" ]; then
        local end_time=$(get_time_ns)
        local elapsed=$(format_elapsed "$start_time" "$end_time")
    fi

    if [ "$MODE" = "normal" ]; then
        print_color "blue" "==================================="
        print_color "yellow" "Script exited with code: $SCRIPT_EXIT"
        print_timing "$elapsed"
    fi

    return $SCRIPT_EXIT
}

# --- Main logic ----------------------------------------------------
main() {
    local original_file="$INPUT_FILE"
    local current_file="$original_file"
    local file_type_info=""
    local fallback_count=0

    while true; do
        file_type_info=$(detect_file_type "$current_file")
        file_type="${file_type_info%%:*}"
        full_path="${file_type_info#*:}"

        case "$file_type" in
            asm)
                if [ "$MODE" = "normal" ]; then
                    print_color "green" "Found Assembly file: $full_path"
                    if [ "$OUTPUT_ONLY" = true ]; then
                        print_color "magenta" "Binary generation mode: will compile and link only"
                    fi
                fi
                run_asm "$full_path" "$PROGRAM_ARGS"; return $? ;;
            sh)
                if [ "$OUTPUT_ONLY" = true ]; then
                    print_color "red" "Error: --bin/-o flag is only for .asm files, not .sh files"
                    exit 1
                fi
                if [ "$MODE" = "normal" ]; then
                    print_color "green" "Found shell script: $full_path"
                fi
                run_sh "$full_path" "$PROGRAM_ARGS"; return $? ;;
            binary)
                if [ "$OUTPUT_ONLY" = true ]; then
                    print_color "red" "Error: --bin/-o flag is only for .asm files, not binaries"
                    exit 1
                fi
                if [ "$MODE" = "normal" ]; then
                    print_color "green" "Found binary file: $full_path"
                fi
                run_binary "$full_path" "$PROGRAM_ARGS"; return $? ;;
            script)
                if [ "$OUTPUT_ONLY" = true ]; then
                    print_color "red" "Error: --bin/-o flag is only for .asm files, not scripts"
                    exit 1
                fi
                if [ "$MODE" = "normal" ]; then
                    print_color "green" "Found script file: $full_path"
                fi
                run_script "$full_path" "$PROGRAM_ARGS"; return $? ;;
            not_found)
                if [ $fallback_count -eq 0 ]; then
                    if [ "$MODE" = "normal" ]; then
                        print_color "yellow" "File '$current_file' not found, attempting fallback..."
                    fi
                    fallback_count=1
                fi
                local alternative_file
                if [ "$current_file" = "$original_file" ]; then
                    alternative_file=$(find_alternative "$current_file" "not_found")
                else
                    alternative_file=$(find_alternative "$current_file" "$file_type")
                fi
                if [ -n "$alternative_file" ] && [ "$alternative_file" != "$current_file" ]; then
                    if [ "$MODE" = "normal" ]; then
                        print_color "yellow" "Fallback to: $alternative_file"
                    fi
                    current_file="$alternative_file"; continue
                else
                    print_color "red" "Error: File '$original_file' not found and no fallback available!"
                    if [ "$MODE" = "normal" ]; then
                        print_color "yellow" "Searched in:"
                        print_color "yellow" "  1. Caller directory: $CALLER_DIR"
                        print_color "yellow" "  2. Script directory: $SCRIPT_DIR"
                        print_color "yellow" "  3. Current directory"
                        print_color "yellow" "Tried file paths:"
                        print_color "yellow" "  1. $original_file"
                        [ -n "$alternative_file" ] && [ "$alternative_file" != "$original_file" ] && print_color "yellow" "  2. $alternative_file"
                    fi
                    exit 1
                fi ;;
            unknown)
                if [ "$OUTPUT_ONLY" = true ]; then
                    print_color "red" "Error: --bin/-o flag is only for .asm files"
                    exit 1
                fi
                if [ "$MODE" = "normal" ]; then
                    print_color "yellow" "Unknown file type for: $full_path"
                    print_color "yellow" "Attempting to execute anyway..."
                    echo "========== OUTPUT =========="
                fi

                # Measure execution time only in normal mode
                if [ "$MODE" = "normal" ]; then
                    local start_time=$(get_time_ns)
                fi
                
                if [ "$MODE" = "silent" ]; then
                    (cd "$CALLER_DIR" && "$full_path" $PROGRAM_ARGS 2>/dev/null) > /dev/null 2>&1
                else
                    (cd "$CALLER_DIR" && "$full_path" $PROGRAM_ARGS 2>/dev/null)
                fi
                EXIT_CODE=$?
                
                if [ "$MODE" = "normal" ]; then
                    local end_time=$(get_time_ns)
                    local elapsed=$(format_elapsed "$start_time" "$end_time")
                fi

                if [ $EXIT_CODE -eq 126 ] || [ $EXIT_CODE -eq 127 ]; then
                    print_color "red" "Execution failed (exit code: $EXIT_CODE)"
                    if [ "$MODE" = "normal" ]; then
                        print_color "yellow" "Trying fallback..."
                    fi
                    local alternative_file=$(find_alternative "$current_file" "unknown")
                    if [ -n "$alternative_file" ] && [ "$alternative_file" != "$current_file" ]; then
                        if [ "$MODE" = "normal" ]; then
                            print_color "yellow" "Fallback to: $alternative_file"
                        fi
                        current_file="$alternative_file"; continue
                    else
                        print_color "red" "No fallback available. Cannot execute: $full_path"
                        exit 1
                    fi
                else
                    if [ "$MODE" = "normal" ]; then
                        echo "==================================="
                        print_color "yellow" "Program exited with code: $EXIT_CODE"
                        print_timing "$elapsed"
                    fi
                    return $EXIT_CODE
                fi ;;
        esac
    done
}

main