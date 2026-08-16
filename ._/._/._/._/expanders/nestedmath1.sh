#!/bin/bash

# ------------------------------------------------------------
# Toolchain: convert / expand arithmetic expression scripts
# Supports .c, .py, .js files with the pattern:
#   C:  double r5 = ( ... ); printf("%.15f\n", r5);
#   PY: r5 = ( ... ) \n print(r5)
#   JS: const r5 = ( ... ); \n console.log(r5);
# ------------------------------------------------------------

# Default values
DEFAULT_SIZE_MB=10
DEFAULT_MIN_NUM=1
DEFAULT_MAX_NUM=100
DEFAULT_TARGET_LANG="same"

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  convert   Convert between .c, .py, .js files
  expand    Expand a file to a target size (MB) by adding random terms

Convert options:
  -i <input_file>    Input file (.c, .py, or .js) [REQUIRED]
  -o <output_file>   Output file [DEFAULT: converted_<input>]
  -t <target_lang>   Target language: c, py, or js [DEFAULT: py]

Expand options:
  -i <input_file>    Input file (.c, .py, or .js) [REQUIRED]
  -o <output_file>   Output file [DEFAULT: expanded_<input>]
  -s <size_mb>       Target size in MB [DEFAULT: ${DEFAULT_SIZE_MB}]
  -t <target_lang>   Output language: c, py, js [DEFAULT: same as input]
  -m <min_num>       Min number for generated terms [DEFAULT: ${DEFAULT_MIN_NUM}]
  -M <max_num>       Max number for generated terms [DEFAULT: ${DEFAULT_MAX_NUM}]

Examples:
  $0 expand file.js                    # Expand file.js to 10MB, same language
  $0 expand file.c -s 5 -t py          # Expand file.c to 5MB, output as Python
  $0 expand file.py -s 20 -o big.py    # Expand file.py to 20MB, custom output
  $0 convert file.c -t js              # Convert file.c to JavaScript
  $0 convert file.py -o output.c       # Convert to C with custom name
  $0 convert file.js                   # Convert to Python (default)
EOF
}

# Detect language from file extension
detect_lang() {
    case "$1" in
        *.c)  echo "c" ;;
        *.py) echo "py" ;;
        *.js) echo "js" ;;
        *)    echo "unknown" ;;
    esac
}

# Extract the core expression (everything between the variable assignment and the closing parenthesis)
extract_expression() {
    local file=$1 lang=$2
    case $lang in
        c)
            awk '/double r5 = \(/ {flag=1; next} /\);/ && flag {flag=0} flag' "$file"
            ;;
        py)
            awk '/r5 = \(/ {flag=1; next} /^\)$/ && flag {flag=0} flag' "$file"
            ;;
        js)
            awk '/const r5 = \(/ {flag=1; next} /\);/ && flag {flag=0} flag' "$file"
            ;;
    esac
}

# Generate a random arithmetic term in the style of the original
# e.g., ((a * b) / (c + d)) or (a - b)
generate_random_term() {
    local min=$1 max=$2
    local a=$((min + RANDOM % (max - min + 1)))
    local b=$((min + RANDOM % (max - min + 1)))
    local c=$((min + RANDOM % (max - min + 1)))
    local d=$((min + RANDOM % (max - min + 1)))

    local ops_mul=('*' '/')
    local ops_add=('+' '-')
    local op1=${ops_mul[$((RANDOM % 2))]}
    local op2=${ops_add[$((RANDOM % 2))]}
    local op3=${ops_mul[$((RANDOM % 2))]}

    if [ $((RANDOM % 2)) -eq 0 ]; then
        # complex term: ((a op1 b) op2 (c op3 d))
        echo "(( $a $op1 $b ) $op2 ( $c $op3 $d ))"
    else
        # simple term: (a op2 b)
        echo "( $a $op2 $b )"
    fi
}

# Expand the expression to reach the target size (in MB)
expand_expression() {
    local input_expr="$1" target_size_mb=$2 min_num=$3 max_num=$4
    local current_expr="$input_expr"
    local current_size=${#current_expr}
    local target_size=$((target_size_mb * 1024 * 1024))
    local term_count=0

    # Progress messages go to stderr so they don't pollute stdout
    printf "Starting expansion to %d MB (%d bytes)\n" "$target_size_mb" "$target_size" >&2
    printf "Initial expression size: %d bytes\n" "$current_size" >&2

    while [ $current_size -lt $target_size ]; do
        term=$(generate_random_term "$min_num" "$max_num")
        current_expr="${current_expr} + ${term}"
        current_size=${#current_expr}
        term_count=$((term_count + 1))

        # Real-time progress: overwrite the same line on stderr
        pct=$((current_size * 100 / target_size))
        printf "\rProgress: %3d%% (size: %d bytes, terms: %d)" "$pct" "$current_size" "$term_count" >&2

        # Safety: avoid infinite loop if something goes wrong
        if [ $term_count -gt 100000 ]; then
            printf "\nToo many terms, stopping.\n" >&2
            break
        fi
    done

    # Finish the progress line
    printf "\nExpansion complete. Final size: %d bytes, terms added: %d\n" "$current_size" "$term_count" >&2

    # Only the final expression goes to stdout (for command substitution)
    printf "%s\n" "$current_expr"
}

# Write the final file in the specified language
write_output_file() {
    local expr="$1" output_file="$2" lang="$3"
    
    case $lang in
        c)
            {
                echo "#include <stdio.h>"
                echo ""
                echo "int main() {"
                echo "    double r5 = ("
                echo "$expr"
                echo "    );"
                echo '    printf("%.15f\n", r5);'
                echo "    return 0;"
                echo "}"
            } > "$output_file"
            ;;
        py)
            {
                echo "r5 = ("
                echo "$expr"
                echo ")"
                echo "print(r5)"
            } > "$output_file"
            ;;
        js)
            {
                echo "const r5 = ("
                echo "$expr"
                echo ");"
                echo "console.log(r5);"
            } > "$output_file"
            ;;
    esac
}

# ------------------------------------------------------------
# Main script
# ------------------------------------------------------------
[ $# -lt 1 ] && { usage; exit 1; }
command=$1
shift

case $command in
    convert)
        # Set defaults
        input_file=""
        output_file=""
        target_lang="py"  # Default target: Python
        
        # Parse arguments - accept both -i flag and positional argument
        while [ $# -gt 0 ]; do
            case $1 in
                -i) input_file="$2"; shift 2 ;;
                -o) output_file="$2"; shift 2 ;;
                -t) target_lang="$2"; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *)
                    # If no input_file set yet, treat as input
                    if [ -z "$input_file" ]; then
                        input_file="$1"
                    elif [ -z "$output_file" ]; then
                        output_file="$1"
                    fi
                    shift
                    ;;
            esac
        done
        
        # Validate input file
        if [ -z "$input_file" ]; then
            echo "Error: input file is required"
            usage
            exit 1
        fi
        
        [ ! -f "$input_file" ] && { echo "Error: file $input_file not found"; exit 1; }
        
        input_lang=$(detect_lang "$input_file")
        [ "$input_lang" == "unknown" ] && { echo "Error: unknown input language for $input_file"; exit 1; }
        
        # Set default output file if not specified
        if [ -z "$output_file" ]; then
            base_name="${input_file%.*}"
            output_file="converted_${base_name}.${target_lang}"
        fi
        
        # Extract expression
        expr=$(extract_expression "$input_file" "$input_lang")
        [ -z "$expr" ] && { echo "Error: could not extract expression from $input_file"; exit 1; }
        
        # Write output
        write_output_file "$expr" "$output_file" "$target_lang"
        
        echo "✅ Converted $input_file to $output_file ($target_lang)"
        ;;

    expand)
        # Set defaults
        input_file=""
        output_file=""
        size_mb=$DEFAULT_SIZE_MB
        target_lang="same"
        min_num=$DEFAULT_MIN_NUM
        max_num=$DEFAULT_MAX_NUM
        
        # Parse arguments - accept flags and positional arguments
        while [ $# -gt 0 ]; do
            case $1 in
                -i) input_file="$2"; shift 2 ;;
                -o) output_file="$2"; shift 2 ;;
                -s) size_mb="$2"; shift 2 ;;
                -t) target_lang="$2"; shift 2 ;;
                -m) min_num="$2"; shift 2 ;;
                -M) max_num="$2"; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *)
                    # If no input_file set yet, treat as input
                    if [ -z "$input_file" ]; then
                        input_file="$1"
                    fi
                    shift
                    ;;
            esac
        done
        
        # Validate input file
        if [ -z "$input_file" ]; then
            echo "Error: input file is required"
            usage
            exit 1
        fi
        
        [ ! -f "$input_file" ] && { echo "Error: file $input_file not found"; exit 1; }
        
        input_lang=$(detect_lang "$input_file")
        [ "$input_lang" == "unknown" ] && { echo "Error: unknown input language for $input_file"; exit 1; }
        
        # Set default target language if not specified
        if [ "$target_lang" == "same" ]; then
            target_lang=$input_lang
        fi
        
        # Set default output file if not specified
        if [ -z "$output_file" ]; then
            base_name="${input_file%.*}"
            output_file="expanded_${base_name}.${target_lang}"
        fi
        
        # Extract expression
        expr=$(extract_expression "$input_file" "$input_lang")
        [ -z "$expr" ] && { echo "Error: could not extract expression from $input_file"; exit 1; }
        
        echo "📂 Input: $input_file ($input_lang)"
        echo "📄 Output: $output_file ($target_lang)"
        echo "📏 Target size: ${size_mb} MB"
        echo "🔢 Number range: ${min_num}-${max_num}"
        echo ""
        
        # Expand expression
        # NOTE: expand_expression now only outputs the expression to stdout;
        # all progress messages go to stderr and appear in real time.
        expanded_expr=$(expand_expression "$expr" "$size_mb" "$min_num" "$max_num")
        
        # Write output
        write_output_file "$expanded_expr" "$output_file" "$target_lang"
        
        echo ""
        echo "✅ Expanded $input_file to $output_file ($target_lang) with target size ${size_mb} MB"
        ;;

    -h|--help|help)
        usage
        exit 0
        ;;
        
    *)
        echo "Unknown command: $command"
        usage
        exit 1
        ;;
esac
