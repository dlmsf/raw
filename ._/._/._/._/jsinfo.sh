#!/bin/sh

# Node.js Interface Analyzer - Pure Shell Script Version
# Compatible with ash, dash, bash

set -e

# Global variables
BASE_DIR="/tmp/jsinfo"
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S-000Z)
TARGET_DIR="$BASE_DIR/$TIMESTAMP"
GENERATE_SH=0
JSON_MODE=0
SCRIPT_GENERATOR=0
PATHS=""
SCRIPT_NAME=""
TOTAL_FILES=0
PID=$$

# Native Node.js modules set
is_native_module() {
    module="$1"
    module="${module#node:}"
    
    case "$module" in
        ./*|../*|*/*|*.js|*.mjs|*.cjs|*.json)
            return 1
            ;;
    esac
    
    case "$module" in
        assert|async_hooks|buffer|child_process|cluster|\
        console|constants|crypto|dgram|diagnostics_channel|\
        dns|domain|events|fs|http|http2|https|\
        inspector|module|net|os|path|perf_hooks|\
        process|punycode|querystring|readline|repl|\
        stream|string_decoder|timers|tls|trace_events|\
        tty|url|util|v8|vm|wasi|worker_threads|\
        zlib|fs/promises|timers/promises|stream/promises|\
        stream/consumers|stream/web|dns/promises|readline/promises)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Parse all imports and extract bindings
parse_imports() {
    file="$1"
    tmp_output="$2"
    
    > "$tmp_output"
    
    # Pattern 1: import defaultImport from 'module'
    grep -n "import [a-zA-Z_$][a-zA-Z0-9_$]* from ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        import_name=$(echo "$line" | sed -E "s/.*import ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\1/")
        module_name=$(echo "$line" | sed -E "s/.*import ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\2/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "BINDING|${import_name}|${clean_module}|default|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 2: import { named1, named2 } from 'module'
    grep -n "import {[^}]*} from ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        bindings_part=$(echo "$line" | sed -E 's/.*import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"].*/\1/')
        module_name=$(echo "$line" | sed -E 's/.*import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"].*/\2/')
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            
            # Split on commas, handle aliases (import { orig as alias })
            echo "$bindings_part" | tr ',' '\n' | while read -r binding; do
                binding=$(echo "$binding" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
                
                if echo "$binding" | grep -q " as "; then
                    # Handle aliased import: original as alias
                    original=$(echo "$binding" | sed -E 's/^([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]+as[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)$/\1/')
                    alias=$(echo "$binding" | sed -E 's/^([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]+as[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)$/\2/')
                    echo "BINDING|${alias}|${clean_module}|named|${linenum}" >> "$tmp_output"
                    echo "BINDING_ORIGINAL|${alias}|${original}|${clean_module}" >> "$tmp_output"
                else
                    echo "BINDING|${binding}|${clean_module}|named|${linenum}" >> "$tmp_output"
                    echo "BINDING_ORIGINAL|${binding}|${binding}|${clean_module}" >> "$tmp_output"
                fi
            done
        fi
    done
    
    # Pattern 3: import * as namespace from 'module'
    grep -n "import \* as [a-zA-Z_\$][a-zA-Z0-9_\$]* from ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        import_name=$(echo "$line" | sed -E "s/.*import \* as ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\1/")
        module_name=$(echo "$line" | sed -E "s/.*import \* as ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\2/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "BINDING|${import_name}|${clean_module}|namespace|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 4: import 'module' (side effect)
    grep -n "^import ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        module_name=$(echo "$line" | sed -E "s/import ['\"]([^'\"]+)['\"];?/\1/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|side_effect|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 5: const/let/var x = require('module')
    grep -n "require(['\"][^'\"]*['\"])" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        module_name=$(echo "$line" | sed -E "s/.*require\(['\"]([^'\"]+)['\"]\).*/\1/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            
            # Try to extract variable name
            varname=$(echo "$line" | sed -E 's/.*(const|let|var)[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]*=.*/\2/')
            if [ -n "$varname" ] && [ "$varname" != "$line" ]; then
                echo "BINDING|${varname}|${clean_module}|require|${linenum}" >> "$tmp_output"
            else
                echo "IMPORT|${clean_module}|require_side_effect|${linenum}" >> "$tmp_output"
            fi
        fi
    done
    
    # Pattern 6: dynamic import()
    grep -n "import(['\"][^'\"]*['\"])" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        module_name=$(echo "$line" | sed -E "s/.*import\(['\"]([^'\"]+)['\"]\).*/\1/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|dynamic|${linenum}" >> "$tmp_output"
        fi
    done
}

# Track usage of imported bindings - find method calls and property access
track_usage() {
    file="$1"
    bindings_file="$2"
    tmp_output="$3"
    
    > "$tmp_output"
    
    # For each binding, search for its usage in the file
    grep "^BINDING|" "$bindings_file" 2>/dev/null | while IFS='|' read -r type binding_name module import_type linenum; do
        if [ -z "$binding_name" ]; then
            continue
        fi
        
        # Skip the import line itself
        import_line=$linenum
        
        # Look for usage patterns after the import
        # Pattern: binding.method() or binding.method(args)
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*[[:space:]]*(" 2>/dev/null | while IFS=: read -r uline ucode; do
            method=$(echo "$ucode" | sed -E "s/.*${binding_name}\.([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]*\(.*/\1/")
            echo "METHOD|${module}|${binding_name}|${method}" >> "$tmp_output"
        done
        
        # Pattern: binding.property (without method call)
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*" 2>/dev/null | grep -v "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*[[:space:]]*(" | while IFS=: read -r uline ucode; do
            prop=$(echo "$ucode" | sed -E "s/.*${binding_name}\.([a-zA-Z_\$][a-zA-Z0-9_\$]*).*/\1/")
            echo "PROPERTY|${module}|${binding_name}|${prop}" >> "$tmp_output"
        done
        
        # Check if binding is used as a function call
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "[^.]${binding_name}[[:space:]]*(" 2>/dev/null | while IFS=: read -r uline ucode; do
            echo "FUNCTION_CALL|${module}|${binding_name}|function" >> "$tmp_output"
        done
        
        # Check if binding is used without . or () (assigned, compared, etc.)
        used_line=$(tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "[^.]${binding_name}[^a-zA-Z0-9_\$.]" 2>/dev/null | grep -v "${binding_name}\." | grep -v "${binding_name}(" | head -1)
        if [ -n "$used_line" ]; then
            echo "USED|${module}|${binding_name}|general" >> "$tmp_output"
        fi
    done
}

# Determine if a binding represents a class/interface or a function
classify_interface() {
    binding_name="$1"
    module="$2"
    usage_file="$3"
    
    # Check if methods were called on this binding
    method_count=$(grep "^METHOD|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    prop_count=$(grep "^PROPERTY|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    func_call=$(grep "^FUNCTION_CALL|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    
    if [ "$method_count" -gt 0 ] || [ "$prop_count" -gt 0 ]; then
        echo "interface"
    elif [ "$func_call" -gt 0 ]; then
        echo "function"
    else
        echo "unknown"
    fi
}

# Extract final results per file
extract_final_results() {
    bindings_file="$1"
    usage_file="$2"
    tmp_final="$3"
    file_index="$4"
    
    > "$tmp_final"
    
    # Create unique temp file for used modules
    used_modules_file="/tmp/jsinfo_used_modules_${PID}_${file_index}"
    
    # Get all unique modules that have been used
    if [ -s "$usage_file" ]; then
        cut -d'|' -f2 "$usage_file" | sort -u > "$used_modules_file"
    else
        > "$used_modules_file"
    fi
    
    while read -r module; do
        if [ -z "$module" ]; then
            continue
        fi
        
        # Get bindings for this module that are actually used
        bindings=$(grep "^BINDING|[^|]*|${module}|" "$bindings_file" 2>/dev/null | cut -d'|' -f2 | sort -u)
        
        for binding in $bindings; do
            if [ -z "$binding" ]; then
                continue
            fi
            
            # Check if binding is used
            is_used=$(grep -c "^[A-Z_]*|${module}|${binding}|" "$usage_file" 2>/dev/null || echo 0)
            
            if [ "$is_used" -gt 0 ]; then
                # Get original name
                original=$(grep "^BINDING_ORIGINAL|${binding}|" "$bindings_file" 2>/dev/null | cut -d'|' -f3 | head -1)
                if [ -z "$original" ]; then
                    original="$binding"
                fi
                
                # Classify
                type=$(classify_interface "$binding" "$module" "$usage_file")
                
                # Get methods
                methods=$(grep "^METHOD|${module}|${binding}|" "$usage_file" 2>/dev/null | cut -d'|' -f4 | sort -u | tr '\n' ',' | sed 's/,$//')
                properties=$(grep "^PROPERTY|${module}|${binding}|" "$usage_file" 2>/dev/null | cut -d'|' -f4 | sort -u | tr '\n' ',' | sed 's/,$//')
                
                echo "USED_INTERFACE|${module}|${original}|${binding}|${type}|${methods}|${properties}" >> "$tmp_final"
            fi
        done
        
        # Check for side-effect imports or general module usage
        if grep -q "^IMPORT|${module}|" "$bindings_file" 2>/dev/null; then
            echo "MODULE_IMPORT|${module}|side_effect" >> "$tmp_final"
        fi
        
    done < "$used_modules_file"
    
    # Cleanup
    rm -f "$used_modules_file"
}

# Print results per file
print_file_results() {
    final_file="$1"
    
    if [ ! -s "$final_file" ]; then
        echo "   No native Node.js module usage found."
        return
    fi
    
    # Get unique modules
    modules=$(cut -d'|' -f2 "$final_file" | sort -u)
    
    for module in $modules; do
        echo "   📦 ${module}"
        
        # List interfaces/functions used
        grep "^USED_INTERFACE|${module}|" "$final_file" 2>/dev/null | sort -u | while IFS='|' read -r _ _ original alias type methods properties; do
            display_name="$original"
            if [ "$original" != "$alias" ]; then
                display_name="${original} (as ${alias})"
            fi
            
            if [ "$type" = "interface" ]; then
                echo "      🔹 Interface: ${display_name}"
                
                if [ -n "$methods" ]; then
                    echo "         Methods:"
                    echo "$methods" | tr ',' '\n' | sort -u | while read -r method; do
                        if [ -n "$method" ]; then
                            echo "            - ${method}()"
                        fi
                    done
                fi
                
                if [ -n "$properties" ]; then
                    echo "         Properties:"
                    echo "$properties" | tr ',' '\n' | sort -u | while read -r prop; do
                        if [ -n "$prop" ]; then
                            echo "            - ${prop}"
                        fi
                    done
                fi
            elif [ "$type" = "function" ]; then
                echo "      🔸 Function: ${display_name}()"
            else
                echo "      ❓ Used: ${display_name}"
            fi
        done
        
        # Module-level imports
        grep "^MODULE_IMPORT|${module}|" "$final_file" 2>/dev/null | sort -u | while IFS='|' read -r _ _ type; do
            echo "      📎 Module import (${type})"
        done
        
        echo ""
    done
}

# Combine all results for final output
combine_all_results() {
    output_dir="$1"
    temp_dir="$2"
    
    tmp_combined="${temp_dir}/combined_final"
    > "$tmp_combined"
    
    # Collect all final files
    for i in $(seq 0 999); do
        result_file="${temp_dir}/final_${i}"
        if [ -f "$result_file" ]; then
            cat "$result_file" >> "$tmp_combined" 2>/dev/null
        else
            break
        fi
    done
    
    if [ ! -s "$tmp_combined" ]; then
        echo "No results to combine."
        return
    fi
    
    # Get unique interfaces per module with their methods
    sort -u "$tmp_combined" > "${output_dir}/all_results.txt"
    
    # Build summary per module
    > "${output_dir}/module_summary.txt"
    
    modules=$(cut -d'|' -f2 "$tmp_combined" | sort -u)
    
    for module in $modules; do
        if [ -z "$module" ]; then
            continue
        fi
        
        # Get unique interfaces for this module
        interfaces=$(grep "^USED_INTERFACE|${module}|" "$tmp_combined" 2>/dev/null | cut -d'|' -f3,5 | sort -u)
        
        echo "MODULE|${module}" >> "${output_dir}/module_summary.txt"
        
        echo "$interfaces" | while IFS='|' read -r name type; do
            if [ -z "$name" ]; then
                continue
            fi
            
            # Collect ALL methods for this interface across all files
            all_methods=$(grep "^USED_INTERFACE|${module}|${name}|" "$tmp_combined" 2>/dev/null | cut -d'|' -f6 | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
            all_props=$(grep "^USED_INTERFACE|${module}|${name}|" "$tmp_combined" 2>/dev/null | cut -d'|' -f7 | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
            
            echo "INTERFACE|${name}|${type}|${all_methods}|${all_props}" >> "${output_dir}/module_summary.txt"
        done
    done
}

# Save results as directory structure
save_as_structure() {
    summary_file="$1"
    output_dir="$2"
    
    mkdir -p "$output_dir"
    
    current_module=""
    
    cat "$summary_file" | while IFS='|' read -r type data1 data2 data3 data4; do
        case "$type" in
            MODULE)
                current_module="$data1"
                safe_module=$(echo "$current_module" | tr '/' '_')
                module_dir="${output_dir}/${safe_module}"
                mkdir -p "$module_dir"
                
                # Initialize module README
                cat > "${module_dir}/README.md" << EOF
# Module: ${current_module}

## Interfaces & Functions

EOF
                ;;
            INTERFACE)
                name="$data1"
                itype="$data2"
                methods="$data3"
                props="$data4"
                
                if [ -z "$current_module" ]; then
                    continue
                fi
                
                safe_module=$(echo "$current_module" | tr '/' '_')
                module_dir="${output_dir}/${safe_module}"
                
                if [ "$itype" = "interface" ]; then
                    echo "### 🔹 ${name} (Interface)" >> "${module_dir}/README.md"
                    
                    if [ -n "$methods" ] && [ "$methods" != "" ]; then
                        echo "" >> "${module_dir}/README.md"
                        echo "**Methods:**" >> "${module_dir}/README.md"
                        echo "$methods" | tr ',' '\n' | sort -u | while read -r method; do
                            if [ -n "$method" ]; then
                                echo "- \`${method}()\`" >> "${module_dir}/README.md"
                                # Create method file
                                safe_method=$(echo "$method" | sed 's/[^a-zA-Z0-9_]/_/g')
                                echo "# ${name}.${method}()" > "${module_dir}/${safe_method}.method"
                            fi
                        done
                    fi
                    
                    if [ -n "$props" ] && [ "$props" != "" ]; then
                        echo "" >> "${module_dir}/README.md"
                        echo "**Properties:**" >> "${module_dir}/README.md"
                        echo "$props" | tr ',' '\n' | sort -u | while read -r prop; do
                            if [ -n "$prop" ]; then
                                echo "- \`${prop}\`" >> "${module_dir}/README.md"
                            fi
                        done
                    fi
                    
                    echo "" >> "${module_dir}/README.md"
                    
                elif [ "$itype" = "function" ]; then
                    echo "### 🔸 ${name}() (Function)" >> "${module_dir}/README.md"
                    echo "" >> "${module_dir}/README.md"
                    safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9_]/_/g')
                    echo "# Function: ${name}()" > "${module_dir}/${safe_name}.function"
                fi
                ;;
        esac
    done
    
    # Create root README
    total_modules=$(grep "^MODULE|" "$summary_file" 2>/dev/null | wc -l)
    
    cat > "${output_dir}/README.md" << EOF
# Node.js Interface Analysis

**Generated:** $(date)
**Files analyzed:** ${TOTAL_FILES}
**Total modules used:** ${total_modules}

## Modules

EOF
    
    grep "^MODULE|" "$summary_file" 2>/dev/null | while IFS='|' read -r _ module; do
        safe_module=$(echo "$module" | tr '/' '_')
        iface_count=$(grep "INTERFACE|" "$summary_file" 2>/dev/null | grep "|interface|" | wc -l)
        func_count=$(grep "INTERFACE|" "$summary_file" 2>/dev/null | grep "|function|" | wc -l)
        echo "- 📦 **${module}** (${iface_count} interfaces, ${func_count} functions)" >> "${output_dir}/README.md"
    done
    
    echo "" >> "${output_dir}/README.md"
    echo "---" >> "${output_dir}/README.md"
    echo "*Generated by Node.js Interface Analyzer*" >> "${output_dir}/README.md"
}

# Save as JSON
save_as_json() {
    summary_file="$1"
    output_dir="$2"
    
    mkdir -p "$output_dir"
    
    json_file="${output_dir}/analysis.json"
    
    total_modules=$(grep "^MODULE|" "$summary_file" 2>/dev/null | wc -l)
    
    # Start JSON
    cat > "$json_file" << EOF
{
  "metadata": {
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
    "files_analyzed": ${TOTAL_FILES},
    "total_modules": ${total_modules}
  },
  "modules": {
EOF
    
    first_module=1
    grep "^MODULE|" "$summary_file" 2>/dev/null | while IFS='|' read -r _ module; do
        if [ -z "$module" ]; then
            continue
        fi
        
        # Get interfaces for this module from summary
        module_interfaces=$(grep "^INTERFACE|[^|]*|[^|]*|" "$summary_file" 2>/dev/null || true)
        
        # Build module entry
        if [ $first_module -eq 1 ]; then
            first_module=0
        else
            echo "    }," >> "$json_file"
        fi
        
        echo "    \"${module}\": {" >> "$json_file"
        echo "      \"interfaces\": [" >> "$json_file"
        
        first_iface=1
        echo "$module_interfaces" | while IFS='|' read -r _ name type methods props; do
            if [ -z "$name" ]; then
                continue
            fi
            
            if [ $first_iface -eq 1 ]; then
                first_iface=0
            else
                echo "        }," >> "$json_file"
            fi
            
            echo "        {" >> "$json_file"
            echo "          \"name\": \"${name}\"," >> "$json_file"
            echo "          \"type\": \"${type}\"," >> "$json_file"
            
            # Methods array
            if [ -n "$methods" ]; then
                echo "          \"methods\": [" >> "$json_file"
                echo "$methods" | tr ',' '\n' | grep -v '^$' | sort -u | while read -r method; do
                    echo "            \"${method}\"," >> "$json_file"
                done
                # Remove trailing comma from last method
                sed -i '$ s/,$//' "$json_file"
                echo "          ]," >> "$json_file"
            else
                echo "          \"methods\": []," >> "$json_file"
            fi
            
            # Properties array
            if [ -n "$props" ]; then
                echo "          \"properties\": [" >> "$json_file"
                echo "$props" | tr ',' '\n' | grep -v '^$' | sort -u | while read -r prop; do
                    echo "            \"${prop}\"," >> "$json_file"
                done
                sed -i '$ s/,$//' "$json_file"
                echo "          ]" >> "$json_file"
            else
                echo "          \"properties\": []" >> "$json_file"
            fi
        done
        
        echo "        }" >> "$json_file"
        echo "      ]" >> "$json_file"
    done
    
    # Close last module and JSON
    echo "    }" >> "$json_file"
    echo "  }" >> "$json_file"
    echo "}" >> "$json_file"
    
    echo "✅ JSON saved to: $json_file"
}

# Main execution
main() {
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --sh)
                GENERATE_SH=1
                ;;
            --json)
                JSON_MODE=1
                ;;
            --script-generator)
                SCRIPT_GENERATOR=1
                ;;
            *)
                if [ -z "$PATHS" ]; then
                    PATHS="$arg"
                else
                    PATHS="$PATHS $arg"
                fi
                ;;
        esac
    done
    
    if [ -z "$PATHS" ]; then
        echo "❌ Please provide at least one .js file or directory"
        echo "Usage: $0 [--sh] [--json] [--script-generator] <file1.js> <file2.js> <dir1> ..."
        echo "  --sh                  Generate directory structure with .method files"
        echo "  --json                Generate JSON output"
        echo "  --script-generator    Generate .sh script instead of saving directly"
        exit 1
    fi
    
    # Collect all JS files into a variable (avoid subshell)
    ALL_FILES=""
    for path in $PATHS; do
        if [ -f "$path" ]; then
            case "$path" in
                *.js|*.mjs|*.cjs)
                    ALL_FILES="${ALL_FILES}${path}
"
                    ;;
            esac
        elif [ -d "$path" ]; then
            found=$(find "$path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) 2>/dev/null)
            if [ -n "$found" ]; then
                ALL_FILES="${ALL_FILES}${found}
"
            fi
        fi
    done
    
    if [ -z "$ALL_FILES" ]; then
        echo "❌ No .js files found"
        exit 1
    fi
    
    # Count files
    TOTAL_FILES=$(echo "$ALL_FILES" | grep -c '.' 2>/dev/null || echo 0)
    echo "📁 Analyzing ${TOTAL_FILES} JavaScript file(s):"
    echo "$ALL_FILES" | while read -r file; do
        if [ -n "$file" ]; then
            echo "   - ${file}"
        fi
    done
    echo ""
    
    # Create temp directory for this run
    TEMP_DIR="/tmp/jsinfo_${PID}"
    mkdir -p "$TEMP_DIR"
    
    # Process each file - use a counter and process sequentially
    file_index=0
    IFS_OLD="$IFS"
    IFS='
'
    for file in $ALL_FILES; do
        if [ -z "$file" ]; then
            continue
        fi
        
        echo "📄 Analyzing: $(basename "$file")"
        
        # Temp files for this file
        bindings_file="${TEMP_DIR}/bindings_${file_index}"
        usage_file="${TEMP_DIR}/usage_${file_index}"
        final_file="${TEMP_DIR}/final_${file_index}"
        
        # Parse imports
        parse_imports "$file" "$bindings_file"
        
        # Track usage
        track_usage "$file" "$bindings_file" "$usage_file"
        
        # Extract final results
        extract_final_results "$bindings_file" "$usage_file" "$final_file" "$file_index"
        
        # Print results
        print_file_results "$final_file"
        
        file_index=$((file_index + 1))
    done
    IFS="$IFS_OLD"
    
    # Combine all results
    output_dir="$TARGET_DIR"
    mkdir -p "$output_dir"
    combine_all_results "$output_dir" "$TEMP_DIR"
    
    # Save based on mode
    if [ "$JSON_MODE" = "1" ]; then
        save_as_json "${output_dir}/module_summary.txt" "$output_dir"
    else
        save_as_structure "${output_dir}/module_summary.txt" "$output_dir"
    fi
    
    echo ""
    echo "✅ Analysis complete!"
    echo "📍 Results saved to: $output_dir"
    echo "📄 Summary: $output_dir/README.md"
    
    # Cleanup temp files
    rm -rf "$TEMP_DIR"
}

# Run main function
main "$@"