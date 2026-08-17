#!/usr/bin/env bash

# testcheck.sh - Advanced JS similarity analysis with multiple structural dimensions
# Usage:
#   bash testcheck.sh file.js [--threshold N] [--show-all] [--weights "w1 w2 ... w7"]
# Default weights: 0.2 0.2 0.2 0.15 0.15 0.05 0.05

set -e

# Default weights for 7 dimensions (component, nested, control_flow, data_structures, function_patterns, variable_patterns, error_handling)
DEFAULT_WEIGHTS=(0.2 0.2 0.2 0.15 0.15 0.05 0.05)
WEIGHTS=("${DEFAULT_WEIGHTS[@]}")
THRESHOLD=50
SHOW_ALL=false
TARGET_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --threshold=*)
            THRESHOLD="${1#*=}"
            shift
            ;;
        --show-all)
            SHOW_ALL=true
            shift
            ;;
        --weights)
            IFS=' ' read -r -a WEIGHTS <<< "$2"
            shift 2
            ;;
        --weights=*)
            IFS=' ' read -r -a WEIGHTS <<< "${1#*=}"
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 file.js [--threshold N] [--show-all] [--weights "w1 w2 ... w7"]

Options:
  --threshold N      Set combined similarity threshold (default: 50)
  --show-all         Show all results regardless of threshold
  --weights "w1 w2 w3 w4 w5 w6 w7"
                     Set weights for the 7 dimensions (sum will be normalized)
                     Default: 0.2 0.2 0.2 0.15 0.15 0.05 0.05
  --help, -h         Show this help

Dimensions:
  1. Top-level components
  2. Nested depth structure
  3. Control flow
  4. Data structures & methods
  5. Function patterns
  6. Variable patterns
  7. Error handling
EOF
            exit 0
            ;;
        *)
            if [[ -z "$TARGET_FILE" ]]; then
                TARGET_FILE="$1"
            else
                echo -e "\033[0;31m\033[1mError:\033[0m Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate
if [[ -z "$TARGET_FILE" ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m No input file specified"
    exit 1
fi
if [[ ! -f "$TARGET_FILE" ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m File not found: $TARGET_FILE"
    exit 1
fi
if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 0 ]] || [[ "$THRESHOLD" -gt 100 ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m Threshold must be 0-100"
    exit 1
fi
if [[ ${#WEIGHTS[@]} -ne 7 ]]; then
    echo -e "\033[0;31m\033[1mError:\033[0m --weights must provide exactly 7 numbers"
    exit 1
fi

# Normalize weights
sum=0
for w in "${WEIGHTS[@]}"; do
    if ! [[ "$w" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo -e "\033[0;31m\033[1mError:\033[0m Invalid weight: $w"
        exit 1
    fi
    sum=$(echo "$sum + $w" | bc -l)
done
if (( $(echo "$sum == 0" | bc -l) )); then
    echo -e "\033[0;31m\033[1mError:\033[0m Sum of weights cannot be zero"
    exit 1
fi
for i in "${!WEIGHTS[@]}"; do
    WEIGHTS[$i]=$(echo "scale=6; ${WEIGHTS[$i]} / $sum" | bc)
done

# Colors
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'
BG_RED='\033[41m'; BG_GREEN='\033[42m'; BG_BLUE='\033[44m'; BG_MAGENTA='\033[45m'; BG_CYAN='\033[46m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/tests"
[[ -d "$TESTS_DIR" ]] || { echo -e "${RED}${BOLD}Error:${RESET} tests directory not found"; exit 1; }

# ----------------------------------------------------------------------
# Extraction functions (each writes tokens to a temp file, one per line)
# ----------------------------------------------------------------------

strip_comments_and_strings() {
    # Simple removal of line comments and string literals (best effort)
    sed -E 's/\/\/.*//; s/\/\*.*\*\///g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g' "$1"
}

# 1. Top-level components (presence only, sorted unique)
extract_top_components() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(async\s+)?function\s+\w+|^\s*(const|let|var)\s+\w+\s*=\s*(async\s*)?\([^)]*\)\s*=>|^\s*class\s+\w+|^\s+(async\s+)?[a-zA-Z_$][\w$]*\s*\(' | \
    sed 's/^\s*//; s/[({].*//' >> "$out"
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(if|else if|else|for|while|do|switch|case|default|try|catch|finally|return)\b' | \
    sed 's/^\s*//' >> "$out"
    strip_comments_and_strings "$js_file" | \
    grep -oP '\.(map|filter|reduce|forEach|find|some|every|sort|slice|splice|concat|join|push|pop|shift|unshift|split|replace|match|search|toUpperCase|toLowerCase|trim|charAt|includes|startsWith|endsWith)\(|Math\.(floor|ceil|round|abs|max|min|pow|sqrt|random|trunc|sign)\(|console\.(log|error|warn|info|debug|table|time|timeEnd)\(' | \
    sed 's/[.(].*//' >> "$out"
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(const|let|var)\s+\w+\s*=|`.*`|=>\s*\{|\?\s*[^:]+:|\.\.\.' | \
    sed 's/^\s*//; s/=.*//' >> "$out"
    sort -u "$out" -o "$out"
    echo "$out"
}

# 2. Nested depth structure (frequency matters, keep duplicates)
extract_nested_features() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | awk '
    BEGIN { depth = 0 }
    {
        line = $0
        opens = gsub(/{/, "{", line)
        closes = gsub(/}/, "}", line)
        if (line ~ /function/) print "function_depth" depth
        if (line ~ /if[ (]/) print "if_depth" depth
        if (line ~ /for[ (]/) print "for_depth" depth
        if (line ~ /while[ (]/) print "while_depth" depth
        if (line ~ /switch[ (]/) print "switch_depth" depth
        if (line ~ /try[ {]/) print "try_depth" depth
        if (line ~ /catch[ (]/) print "catch_depth" depth
        if (line ~ /class[ ]/) print "class_depth" depth
        if (line ~ /=>/) print "arrow_depth" depth
        if (line ~ /\breturn\b/) print "return_depth" depth
        if (line ~ /\[/) print "array_depth" depth
        if (line ~ /{/) print "object_depth" depth
        if (line ~ /\)\s*\./) print "chained_call_depth" depth
        if (line ~ /\.(map|filter|reduce|forEach|find|some|every)\(/) print "array_method_depth" depth
        if (line ~ /\.(split|replace|match|toUpperCase|toLowerCase|trim)\(/) print "string_method_depth" depth
        if (line ~ /Math\.(floor|ceil|round|abs|max|min)\(/) print "math_method_depth" depth
        depth += opens - closes
        if (depth < 0) depth = 0
    }' | sort > "$out"
    echo "$out"
}

# 3. Control flow
extract_control_flow() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(if|else if|else|for|while|do|switch|case|default|try|catch|finally)\b' | \
    sed 's/^\s*//' | sort -u > "$out"
    echo "$out"
}

# 4. Data structures & methods
extract_data_structures() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '\[|\]|\{|\}|\.(map|filter|reduce|forEach|find|some|every|sort|slice|splice|concat|join|push|pop|shift|unshift|split|replace|match|search|toUpperCase|toLowerCase|trim|charAt|includes|startsWith|endsWith)\(|Math\.(floor|ceil|round|abs|max|min|pow|sqrt|random|trunc|sign)\(|\.\.\.' | \
    sed 's/[.(].*//' | sort -u > "$out"
    echo "$out"
}

# 5. Function patterns
extract_function_patterns() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(async\s+)?function\s+\w+|^\s*(const|let|var)\s+\w+\s*=\s*(async\s*)?\([^)]*\)\s*=>|=>\s*\{|\breturn\b|\.(map|filter|reduce|forEach|find|some|every)\(' | \
    sed 's/^\s*//; s/[({].*//' | sort -u > "$out"
    echo "$out"
}

# 6. Variable patterns
extract_variable_patterns() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(const|let|var)\s+\w+\s*=|^\s*(const|let|var)\s*\{\s*[^}]+\}\s*=|^\s*(const|let|var)\s*\[\s*[^\]]+\]\s*=|`.*`|\.\.\.' | \
    sed 's/^\s*//; s/=.*//; s/`.*`/template_literal/' | sort -u > "$out"
    echo "$out"
}

# 7. Error handling
extract_error_handling() {
    local js_file="$1"
    local out=$(mktemp)
    strip_comments_and_strings "$js_file" | \
    grep -oP '^\s*(try|catch|finally|throw)\b' | sed 's/^\s*//' | sort -u > "$out"
    echo "$out"
}

# ----------------------------------------------------------------------
# Similarity computation (multiset Jaccard with frequency)
# ----------------------------------------------------------------------
compute_similarity() {
    local file1="$1"
    local file2="$2"
    local -A count1 count2
    while IFS= read -r token; do
        ((count1["$token"]++))
    done < "$file1"
    while IFS= read -r token; do
        ((count2["$token"]++))
    done < "$file2"

    local intersection=0 union=0
    # All unique tokens from both files
    local -A all
    for t in "${!count1[@]}"; do all["$t"]=1; done
    for t in "${!count2[@]}"; do all["$t"]=1; done

    for token in "${!all[@]}"; do
        c1=${count1[$token]:-0}
        c2=${count2[$token]:-0}
        intersection=$((intersection + (c1 < c2 ? c1 : c2)))
        union=$((union + (c1 > c2 ? c1 : c2)))
    done
    if [[ $union -eq 0 ]]; then
        echo "0"
    else
        echo $(( (intersection * 100) / union ))
    fi
}

# ----------------------------------------------------------------------
# Test generation
# ----------------------------------------------------------------------
process_test_directory() {
    local dir_path="$1"
    cd "$dir_path"
    local sh_files=$(ls -1v *.sh 2>/dev/null | grep -E '^[0-9]+\.sh$' || true)
    [[ -n "$sh_files" ]] && for f in $sh_files; do bash "$f" > /dev/null 2>&1 || true; done
    local subdirs=$(find "$dir_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    [[ -n "$subdirs" ]] && for sub in $subdirs; do process_test_directory "$sub"; done
    cd "$SCRIPT_DIR"
}
find_all_js_files() { find "$TESTS_DIR" -name '*.js' -type f 2>/dev/null | sort; }

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
echo -e "${BG_CYAN}${WHITE}${BOLD} JavaScript Multidimensional Similarity Analysis ${RESET}"
echo -e "${DIM}Target: ${TARGET_FILE}${RESET}"
echo -e "${DIM}Threshold: ${THRESHOLD}%${RESET}"
echo ""

# Extract target features
echo -e "${CYAN}${BOLD}Step 1:${RESET} Extracting features..."
target_comp=$(extract_top_components "$TARGET_FILE")
target_nested=$(extract_nested_features "$TARGET_FILE")
target_ctrl=$(extract_control_flow "$TARGET_FILE")
target_data=$(extract_data_structures "$TARGET_FILE")
target_func=$(extract_function_patterns "$TARGET_FILE")
target_var=$(extract_variable_patterns "$TARGET_FILE")
target_err=$(extract_error_handling "$TARGET_FILE")

# Display counts
echo -e "${GREEN}✓ Component: $(wc -l < "$target_comp") | Nested: $(wc -l < "$target_nested") | Control: $(wc -l < "$target_ctrl")${RESET}"
echo -e "${GREEN}✓ Data: $(wc -l < "$target_data") | Function: $(wc -l < "$target_func") | Variable: $(wc -l < "$target_var") | Error: $(wc -l < "$target_err")${RESET}"
echo ""

# Generate tests
echo -e "${CYAN}${BOLD}Step 2:${RESET} Generating test JS files..."
process_test_directory "$TESTS_DIR"
total_js=$(find_all_js_files | wc -l)
echo -e "${GREEN}✓ Generated ${total_js} test files${RESET}"
echo ""

# Analyze
echo -e "${CYAN}${BOLD}Step 3:${RESET} Computing similarities..."
results=$(mktemp)

while IFS= read -r js_file; do
    rel_path="${js_file#$TESTS_DIR}"
    rel_path="${rel_path#/}"

    test_comp=$(extract_top_components "$js_file")
    test_nested=$(extract_nested_features "$js_file")
    test_ctrl=$(extract_control_flow "$js_file")
    test_data=$(extract_data_structures "$js_file")
    test_func=$(extract_function_patterns "$js_file")
    test_var=$(extract_variable_patterns "$js_file")
    test_err=$(extract_error_handling "$js_file")

    sim_comp=$(compute_similarity "$target_comp" "$test_comp")
    sim_nested=$(compute_similarity "$target_nested" "$test_nested")
    sim_ctrl=$(compute_similarity "$target_ctrl" "$test_ctrl")
    sim_data=$(compute_similarity "$target_data" "$test_data")
    sim_func=$(compute_similarity "$target_func" "$test_func")
    sim_var=$(compute_similarity "$target_var" "$test_var")
    sim_err=$(compute_similarity "$target_err" "$test_err")

    # Weighted overall
    overall=$(echo "scale=2; ($sim_comp * ${WEIGHTS[0]} + $sim_nested * ${WEIGHTS[1]} + $sim_ctrl * ${WEIGHTS[2]} + $sim_data * ${WEIGHTS[3]} + $sim_func * ${WEIGHTS[4]} + $sim_var * ${WEIGHTS[5]} + $sim_err * ${WEIGHTS[6]})" | bc)
    overall_int=$(printf "%.0f" "$overall")

    echo "${overall_int}|${sim_comp}|${sim_nested}|${sim_ctrl}|${sim_data}|${sim_func}|${sim_var}|${sim_err}|${rel_path}" >> "$results"

    rm -f "$test_comp" "$test_nested" "$test_ctrl" "$test_data" "$test_func" "$test_var" "$test_err"
done < <(find_all_js_files)

sort -t'|' -k1 -rn "$results" > "${results}.sorted"
mv "${results}.sorted" "$results"

# Display results
echo -e "${BG_MAGENTA}${WHITE}${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BG_MAGENTA}${WHITE}${BOLD}║             SIMILARITY ANALYSIS RESULTS (7 Dimensions)           ║${RESET}"
echo -e "${BG_MAGENTA}${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

found=false
match_count=0

while IFS='|' read -r overall comp nested ctrl data func var err rel_path; do
    if [[ "$overall" -ge "$THRESHOLD" ]] || [[ "$SHOW_ALL" == true ]]; then
        if [[ "$overall" -ge "$THRESHOLD" ]]; then found=true; match_count=$((match_count+1)); fi

        # Color
        if [[ "$overall" -ge 80 ]]; then label="${BG_GREEN}${WHITE}${BOLD} VERY HIGH ${RESET}"
        elif [[ "$overall" -ge 60 ]]; then label="${GREEN}${BOLD} HIGH ${RESET}"
        elif [[ "$overall" -ge 40 ]]; then label="${YELLOW}${BOLD} MODERATE ${RESET}"
        else label="${DIM} LOW ${RESET}"; fi

        echo -e "${BOLD}┏━ ${rel_path} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET}"
        echo -e "  ${BOLD}Overall Similarity:${RESET} ${label} ${BOLD}${overall}%${RESET}"
        echo -e "    ${DIM}Dimensions:${RESET}"
        echo -e "      ${GREEN}Component: ${comp}%${RESET}  ${CYAN}Nested: ${nested}%${RESET}  ${MAGENTA}Control: ${ctrl}%${RESET}"
        echo -e "      ${BLUE}Data: ${data}%${RESET}  ${YELLOW}Function: ${func}%${RESET}  ${RED}Variable: ${var}%${RESET}  ${WHITE}Error: ${err}%${RESET}"
        echo ""
    fi
done < "$results"

# Summary
echo -e "${MAGENTA}${BOLD}┏━━━ Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET}"
echo -e "${BOLD}Target file:${RESET} ${TARGET_FILE}"
echo -e "${BOLD}Test files analyzed:${RESET} ${total_js}"
if [[ "$found" == true ]]; then
    echo -e "${GREEN}${BOLD}Matches (overall ≥${THRESHOLD}%):${RESET} ${match_count}"
    echo ""
    echo -e "${CYAN}${BOLD}Top 5 recommendations:${RESET}"
    head -5 "$results" | while IFS='|' read -r overall rest; do
        rel_path=$(echo "$rest" | cut -d'|' -f9-)
        echo -e "  ${BOLD}${rel_path}${RESET} - Overall: ${overall}%"
    done
else
    echo -e "${YELLOW}${BOLD}No matches found${RESET} with overall ≥${THRESHOLD}%"
    echo -e "${DIM}Try lowering threshold or use --show-all${RESET}"
fi

# Cleanup
rm -f "$target_comp" "$target_nested" "$target_ctrl" "$target_data" "$target_func" "$target_var" "$target_err" "$results"

echo ""
echo -e "${BG_CYAN}${WHITE}${BOLD} Analysis complete ${RESET}"
exit 0