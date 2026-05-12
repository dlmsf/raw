#!/bin/sh

# Node.js Interface Analyzer - Pure Shell Script Version
# Compatible with ash, dash, bash

set -e

# Global variables
BASE_DIR="/tmp/jsinfo"
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S-000Z)
TARGET_DIR="$BASE_DIR/$TIMESTAMP"
JSON_MODE=0
FILE_MODE=0
CLEAR_MODE=0
PATHS=""
TOTAL_FILES=0
PID=$$

# Get the actual working directory from where the command was called
# Walk up the process tree to find the user's shell
get_caller_cwd() {
    local current_pid=$PPID
    local max_depth=10
    local depth=0
    
    while [ $depth -lt $max_depth ]; do
        if [ -r "/proc/${current_pid}/cwd" ]; then
            local cwd=$(readlink -f "/proc/${current_pid}/cwd" 2>/dev/null || echo "")
            
            # Skip system directories and runtime paths
            case "$cwd" in
                /usr/local/etc/*|/etc/*|/proc/*|/sys/*|/snap/*)
                    # Skip these, they're system paths
                    ;;
                *)
                    # Check if this process is a shell or the raw CLI
                    if [ -r "/proc/${current_pid}/comm" ]; then
                        local comm=$(cat "/proc/${current_pid}/comm" 2>/dev/null || echo "")
                        case "$comm" in
                            bash|sh|dash|ash|zsh|fish|node|raw)
                                echo "$cwd"
                                return 0
                                ;;
                        esac
                    fi
                    ;;
            esac
        fi
        
        # Get parent PID
        if [ -r "/proc/${current_pid}/stat" ]; then
            local parent_pid=$(cat "/proc/${current_pid}/stat" 2>/dev/null | cut -d' ' -f4 || echo "")
            if [ -z "$parent_pid" ] || [ "$parent_pid" = "0" ] || [ "$parent_pid" = "$current_pid" ]; then
                break
            fi
            current_pid=$parent_pid
        else
            break
        fi
        
        depth=$((depth + 1))
    done
    
    # Fallback: use the first non-system CWD we can find
    current_pid=$PPID
    depth=0
    while [ $depth -lt $max_depth ]; do
        if [ -r "/proc/${current_pid}/cwd" ]; then
            local cwd=$(readlink -f "/proc/${current_pid}/cwd" 2>/dev/null || echo "")
            case "$cwd" in
                /usr/local/etc/*|/etc/*|/proc/*|/sys/*|/snap/*|/usr/*|/var/*|/tmp/*)
                    ;;
                *)
                    if [ -d "$cwd" ]; then
                        echo "$cwd"
                        return 0
                    fi
                    ;;
            esac
        fi
        
        if [ -r "/proc/${current_pid}/stat" ]; then
            local parent_pid=$(cat "/proc/${current_pid}/stat" 2>/dev/null | cut -d' ' -f4 || echo "")
            if [ -z "$parent_pid" ] || [ "$parent_pid" = "0" ] || [ "$parent_pid" = "$current_pid" ]; then
                break
            fi
            current_pid=$parent_pid
        else
            break
        fi
        
        depth=$((depth + 1))
    done
    
    # Last resort
    echo "$(pwd)"
}

CALL_DIR=$(get_caller_cwd)

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

# Print results per file (minimalistic)
print_file_results() {
    final_file="$1"
    
    if [ ! -s "$final_file" ]; then
        return
    fi
    
    # Get unique modules
    modules=$(cut -d'|' -f2 "$final_file" | sort -u)
    
    for module in $modules; do
        echo "  ${module}"
        
        # List interfaces/functions used
        grep "^USED_INTERFACE|${module}|" "$final_file" 2>/dev/null | sort -u | while IFS='|' read -r _ _ original alias type methods properties; do
            display_name="$original"
            if [ "$original" != "$alias" ]; then
                display_name="${original}→${alias}"
            fi
            
            if [ "$type" = "interface" ]; then
                if [ -n "$methods" ]; then
                    echo "$methods" | tr ',' '\n' | sort -u | while read -r method; do
                        if [ -n "$method" ]; then
                            echo "    ${display_name}.${method}()"
                        fi
                    done
                fi
                
                if [ -n "$properties" ]; then
                    echo "$properties" | tr ',' '\n' | sort -u | while read -r prop; do
                        if [ -n "$prop" ]; then
                            echo "    ${display_name}.${prop}"
                        fi
                    done
                fi
            elif [ "$type" = "function" ]; then
                echo "    ${display_name}()"
            else
                echo "    ${display_name}"
            fi
        done
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
        return 1
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
    
    return 0
}

# Save results as directory structure with .method files
save_as_files() {
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
            --json)
                JSON_MODE=1
                ;;
            --file)
                FILE_MODE=1
                ;;
            --clear)
                CLEAR_MODE=1
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
    
    # Handle clear mode (can work standalone or with other args)
    if [ "$CLEAR_MODE" = "1" ]; then
        if [ -d "$BASE_DIR" ]; then
            rm -rf "$BASE_DIR"
            echo "🧹 Cleared $BASE_DIR"
        else
            echo "🧹 Nothing to clear (${BASE_DIR} does not exist)"
        fi
        
        # If only --clear was provided, exit after clearing
        if [ -z "$PATHS" ]; then
            exit 0
        fi
    fi
    
    # If no paths provided and not in clear-only mode, show error
    if [ -z "$PATHS" ]; then
        echo "❌ Please provide at least one .js file or directory"
        echo "Usage: $0 [--json] [--file] [--clear] <file1.js> <file2.js> <dir1> ..."
        echo "  --json   Save analysis as JSON in /tmp/jsinfo"
        echo "  --file   Save analysis with .method files in /tmp/jsinfo"
        echo "  --clear  Clear /tmp/jsinfo (can be used alone or before saving)"
        exit 1
    fi
    
    # Create temp directory for this run
    TEMP_DIR="/tmp/jsinfo_${PID}"
    mkdir -p "$TEMP_DIR"
    
    # Print detected call directory for debugging
    echo "📍 Working directory: ${CALL_DIR}" >&2
    
    # Collect all JS files - use CALL_DIR for relative paths
    ALL_FILES_FILE="${TEMP_DIR}/all_files.txt"
    > "$ALL_FILES_FILE"
    
    for path in $PATHS; do
        # If path is relative, prepend CALL_DIR
        case "$path" in
            /*)
                # Absolute path - use as is
                resolved_path="$path"
                ;;
            *)
                # Relative path - resolve against CALL_DIR
                resolved_path="${CALL_DIR}/${path}"
                ;;
        esac
        
        if [ -f "$resolved_path" ]; then
            # It's a file - check if it's a JS file
            case "$resolved_path" in
                *.js|*.mjs|*.cjs)
                    echo "$resolved_path" >> "$ALL_FILES_FILE"
                    ;;
            esac
        elif [ -d "$resolved_path" ]; then
            # It's a directory - find all JS files in it
            find "$resolved_path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) 2>/dev/null >> "$ALL_FILES_FILE" || true
        else
            # Also try the original path without prepending
            if [ -f "$path" ]; then
                case "$path" in
                    *.js|*.mjs|*.cjs)
                        echo "$path" >> "$ALL_FILES_FILE"
                        ;;
                esac
            elif [ -d "$path" ]; then
                find "$path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) 2>/dev/null >> "$ALL_FILES_FILE" || true
            fi
        fi
    done
    
    # Remove duplicates and empty lines
    if [ -s "$ALL_FILES_FILE" ]; then
        sort -u "$ALL_FILES_FILE" | grep -v '^$' > "${ALL_FILES_FILE}.tmp"
        mv "${ALL_FILES_FILE}.tmp" "$ALL_FILES_FILE"
    fi
    
    # Check if we found any files
    if [ ! -s "$ALL_FILES_FILE" ]; then
        echo "❌ No .js files found in: $PATHS"
        echo "   Call directory: ${CALL_DIR}"
        echo "   Resolved path: ${resolved_path}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Count files
    TOTAL_FILES=$(wc -l < "$ALL_FILES_FILE" 2>/dev/null || echo 0)
    
    # Process each file
    file_index=0
    while IFS= read -r file; do
        if [ -z "$file" ]; then
            continue
        fi
        
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
        
        file_index=$((file_index + 1))
    done < "$ALL_FILES_FILE"
    
    # Combine all results
    output_dir="$TARGET_DIR"
    mkdir -p "$output_dir"
    
    if combine_all_results "$output_dir" "$TEMP_DIR"; then
        # Determine output mode
        if [ "$JSON_MODE" = "1" ] || [ "$FILE_MODE" = "1" ]; then
            if [ "$JSON_MODE" = "1" ]; then
                save_as_json "${output_dir}/module_summary.txt" "$output_dir"
            fi
            if [ "$FILE_MODE" = "1" ]; then
                save_as_files "${output_dir}/module_summary.txt" "$output_dir"
            fi
            echo ""
            echo "📍 Results saved to: $output_dir"
        else
            # Default: just show minimalistic output
            echo ""
            # Show combined results
            for i in $(seq 0 $((file_index - 1))); do
                final_file="${TEMP_DIR}/final_${i}"
                if [ -f "$final_file" ] && [ -s "$final_file" ]; then
                    print_file_results "$final_file"
                fi
            done
            
            # Cleanup output dir if not saving
            rm -rf "$output_dir"
        fi
    else
        if [ "$JSON_MODE" != "1" ] && [ "$FILE_MODE" != "1" ]; then
            echo "No native Node.js modules detected."
            rm -rf "$output_dir"
        fi
    fi
    
    # Cleanup temp files
    rm -rf "$TEMP_DIR"
}

# Run main function
main "$@"