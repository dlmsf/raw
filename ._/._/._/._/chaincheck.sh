#!/bin/bash

# Usage: ./chaincheck.sh [--log] <filename>
# Default: Silent mode (one line summary)
# --log: Verbose mode (detailed report)

VERBOSE=false
FILE=""

# Parse arguments
for arg in "$@"; do
    if [ "$arg" = "--log" ] || [ "$arg" = "-l" ]; then
        VERBOSE=true
    elif [ "$arg" = "--silent" ] || [ "$arg" = "-s" ]; then
        VERBOSE=false
    else
        FILE="$arg"
    fi
done

if [ -z "$FILE" ]; then
    echo "Usage: $0 [--log] <filename>"
    echo "  Default: Silent mode - one line status"
    echo "  --log:   Verbose mode - detailed report"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "❌ Error: File '$FILE' not found"
    exit 1
fi

# Function to print verbose messages
log_msg() {
    if [ "$VERBOSE" = true ]; then
        echo "$@"
    fi
}

log_msg "╔════════════════════════════════════════════╗"
log_msg "║   Chain & JavaScript Structure Validator   ║"
log_msg "╚════════════════════════════════════════════╝"
log_msg ""
log_msg "📄 File: $FILE"
log_msg ""

# Phase 1: Chain validation
log_msg "═══ Phase 1: Chain Structure Validation ═══"
log_msg "Checking <chain-start>/<chain-end> tag pairs..."
log_msg ""

chain_stack=()
chain_line_stack=()
chain_errors=0
total_starts=0
total_ends=0
line_number=0

while IFS= read -r line || [ -n "$line" ]; do
    ((line_number++))
    
    if echo "$line" | grep -q '<chain-start>'; then
        ((total_starts++))
        chain_stack+=("$line_number")
        chain_line_stack+=("$line_number")
    fi
    
    if echo "$line" | grep -q '<chain-end>'; then
        ((total_ends++))
        if [ ${#chain_stack[@]} -eq 0 ]; then
            log_msg "❌ ERROR: Extra <chain-end> at line $line_number"
            log_msg "   Reason: Found closing tag without matching opening tag"
            log_msg "   Fix: Remove this <chain-end> or add missing <chain-start> before it"
            log_msg ""
            ((chain_errors++))
        else
            unset 'chain_stack[${#chain_stack[@]}-1]'
            unset 'chain_line_stack[${#chain_line_stack[@]}-1]'
        fi
    fi
done < "$FILE"

# Check for unclosed chains
if [ ${#chain_stack[@]} -gt 0 ]; then
    log_msg "❌ ERROR: Found ${#chain_stack[@]} unclosed chain(s):"
    for ((i=${#chain_line_stack[@]}-1; i>=0; i--)); do
        line_content=$(sed -n ${chain_line_stack[$i]}p "$FILE" | sed 's/^[[:space:]]*//' | cut -c1-80)
        log_msg "   Line ${chain_line_stack[$i]}: <chain-start> without matching <chain-end>"
        log_msg "   └─ Content: $line_content"
        log_msg "   └─ Fix: Add <chain-end> after the code block that should be inside this chain"
    done
    log_msg ""
    ((chain_errors += ${#chain_stack[@]}))
fi

if [ $chain_errors -eq 0 ]; then
    log_msg "✅ Chain structure: PASSED (all $total_starts chains properly closed)"
else
    log_msg "❌ Chain structure: FAILED ($chain_errors error(s) found)"
fi
log_msg ""

# Phase 2: JavaScript validation
log_msg "═══ Phase 2: JavaScript Syntax Validation ═══"
log_msg "Checking each <js-start>...<js-end> block for completeness..."
log_msg ""

js_blocks_with_errors=0
total_js_issues=0
line_number=0
block_count=0

while IFS= read -r line || [ -n "$line" ]; do
    ((line_number++))
    
    # Extract code between <js-start> and <js-end>
    if echo "$line" | grep -q '<js-start>' && echo "$line" | grep -q '<js-end>'; then
        ((block_count++))
        
        # Extract the JavaScript code between tags
        js_code=$(echo "$line" | sed 's/.*<js-start>\(.*\)<js-end>.*/\1/')
        
        block_errors=0
        error_details=()
        
        # Remove strings content for bracket checking
        code_no_strings=$(echo "$js_code" | sed "s/'[^']*'/'/g" | sed 's/\"[^\"]*\"/\"/g' | sed 's/`[^`]*`/`/g')
        
        # Count different bracket types
        paren_open=$(echo "$code_no_strings" | grep -o '(' | wc -l)
        paren_close=$(echo "$code_no_strings" | grep -o ')' | wc -l)
        brace_open=$(echo "$code_no_strings" | grep -o '{' | wc -l)
        brace_close=$(echo "$code_no_strings" | grep -o '}' | wc -l)
        bracket_open=$(echo "$code_no_strings" | grep -o '\[' | wc -l)
        bracket_close=$(echo "$code_no_strings" | grep -o ']' | wc -l)
        
        # Check parentheses
        if [ "$paren_open" -ne "$paren_close" ]; then
            diff=$((paren_open - paren_close))
            if [ $diff -gt 0 ]; then
                error_details+=("Missing $diff closing parenthesis ')' - have $paren_open '(' but only $paren_close ')'")
            else
                diff=$((diff * -1))
                error_details+=("Missing $diff opening parenthesis '(' - have $paren_close ')' but only $paren_open '('")
            fi
            ((block_errors++))
        fi
        
        # Check curly braces
        if [ "$brace_open" -ne "$brace_close" ]; then
            diff=$((brace_open - brace_close))
            if [ $diff -gt 0 ]; then
                error_details+=("Missing $diff closing curly brace '}' - have $brace_open '{' but only $brace_close '}'")
            else
                diff=$((diff * -1))
                error_details+=("Missing $diff opening curly brace '{' - have $brace_close '}' but only $brace_open '{'")
            fi
            ((block_errors++))
        fi
        
        # Check square brackets
        if [ "$bracket_open" -ne "$bracket_close" ]; then
            diff=$((bracket_open - bracket_close))
            if [ $diff -gt 0 ]; then
                error_details+=("Missing $diff closing square bracket ']' - have $bracket_open '[' but only $bracket_close ']'")
            else
                diff=$((diff * -1))
                error_details+=("Missing $diff opening square bracket '[' - have $bracket_close ']' but only $bracket_open '['")
            fi
            ((block_errors++))
        fi
        
        # Check quotes (must be even)
        single_quotes=$(echo "$js_code" | grep -o "'" | wc -l)
        double_quotes=$(echo "$js_code" | grep -o '"' | wc -l)
        backticks=$(echo "$js_code" | grep -o '`' | wc -l)
        
        if [ $((single_quotes % 2)) -ne 0 ]; then
            error_details+=("Unclosed single quote string - found $single_quotes single quotes (odd number, should be even)")
            ((block_errors++))
        fi
        
        if [ $((double_quotes % 2)) -ne 0 ]; then
            error_details+=("Unclosed double quote string - found $double_quotes double quotes (odd number, should be even)")
            ((block_errors++))
        fi
        
        if [ $((backticks % 2)) -ne 0 ]; then
            error_details+=("Unclosed template literal - found $backticks backticks (odd number, should be even)")
            ((block_errors++))
        fi
        
        # Display results for this block
        if [ $block_errors -gt 0 ]; then
            log_msg "❌ Block #$block_count at Line $line_number: FAILED"
            log_msg "   Code: $(echo "$js_code" | sed 's/^[[:space:]]*//' | cut -c1-70)"
            log_msg "   ├─ Issues found: $block_errors"
            for detail in "${error_details[@]}"; do
                log_msg "   │  • $detail"
            done
            log_msg "   └─ Fix: Close all unclosed brackets, parentheses, braces, or quotes"
            log_msg ""
            ((js_blocks_with_errors++))
            ((total_js_issues += block_errors))
        fi
    fi
done < "$FILE"

if [ $js_blocks_with_errors -eq 0 ]; then
    log_msg "✅ JavaScript syntax: PASSED (all $block_count blocks properly formed)"
else
    log_msg "❌ JavaScript syntax: FAILED"
    log_msg "   └─ $js_blocks_with_errors block(s) with $total_js_issues total syntax issue(s)"
fi
log_msg ""

# Final summary
log_msg "═══════════════════════════════════════"
log_msg "           FINAL REPORT                "
log_msg "═══════════════════════════════════════"
log_msg ""

log_msg "📌 Chain Structure:"
log_msg "   • <chain-start> tags: $total_starts"
log_msg "   • <chain-end> tags:   $total_ends"
if [ $chain_errors -eq 0 ]; then
    log_msg "   • Status: ✅ All chains properly paired"
else
    log_msg "   • Status: ❌ $chain_errors chain pairing error(s)"
fi
log_msg ""

log_msg "📌 JavaScript Blocks:"
log_msg "   • Total blocks:       $block_count"
log_msg "   • Clean blocks:       $((block_count - js_blocks_with_errors))"
log_msg "   • Blocks with errors: $js_blocks_with_errors"
log_msg "   • Total issues:       $total_js_issues"
if [ $js_blocks_with_errors -eq 0 ]; then
    log_msg "   • Status: ✅ All blocks properly formed"
else
    log_msg "   • Status: ❌ $js_blocks_with_errors block(s) need fixing"
fi
log_msg ""

total_errors=$((chain_errors + js_blocks_with_errors))

# Silent mode output (default) - one line
if [ "$VERBOSE" = false ]; then
    if [ $total_errors -eq 0 ]; then
        echo "✅ $FILE: PASSED - $total_starts chains OK, $block_count JS blocks OK"
    else
        parts=()
        [ $chain_errors -gt 0 ] && parts+=("$chain_errors chain error(s)")
        [ $js_blocks_with_errors -gt 0 ] && parts+=("$js_blocks_with_errors JS block(s) with $total_js_issues issue(s)")
        echo "❌ $FILE: FAILED - ${parts[*]}"
    fi
else
    # Verbose mode output
    if [ $total_errors -eq 0 ]; then
        log_msg "╔═══════════════════════════════════════╗"
        log_msg "║  ✅  ALL CHECKS PASSED!              ║"
        log_msg "║  All chains are properly paired      ║"
        log_msg "║  All JavaScript is properly formed   ║"
        log_msg "╚═══════════════════════════════════════╝"
    else
        log_msg "╔═══════════════════════════════════════╗"
        log_msg "║  ❌  VALIDATION FAILED               ║"
        log_msg "╚═══════════════════════════════════════╝"
        log_msg ""
        log_msg "Summary of fixes needed:"
        if [ $chain_errors -gt 0 ]; then
            log_msg "  🔧 Chain issues ($chain_errors):"
            log_msg "     Add or remove <chain-start>/<chain-end> tags as indicated above"
        fi
        if [ $js_blocks_with_errors -gt 0 ]; then
            log_msg "  🔧 JavaScript issues ($total_js_issues in $js_blocks_with_errors blocks):"
            log_msg "     Close all unclosed brackets, parentheses, braces, or quotes"
        fi
    fi
fi

exit $total_errors