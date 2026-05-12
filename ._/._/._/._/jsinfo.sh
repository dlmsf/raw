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

# Color codes
COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_CYAN="\033[36m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_MAGENTA="\033[35m"

# Get the actual working directory from where the command was called
get_caller_cwd() {
    local current_pid=$PPID
    local max_depth=10
    local depth=0
    
    while [ $depth -lt $max_depth ]; do
        if [ -r "/proc/${current_pid}/cwd" ]; then
            local cwd=$(readlink -f "/proc/${current_pid}/cwd" 2>/dev/null || echo "")
            
            case "$cwd" in
                /usr/local/etc/*|/etc/*|/proc/*|/sys/*|/snap/*)
                    ;;
                *)
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
    
    # Fallback
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
    
    echo "$(pwd)"
}

CALL_DIR=$(get_caller_cwd)

# Check if a module is a native Node.js module
is_native_module() {
    local module="$1"
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
    local file="$1"
    local tmp_output="$2"
    
    > "$tmp_output"
    
    # Pattern 1: import defaultImport from 'module'
    grep -n "import [a-zA-Z_$][a-zA-Z0-9_$]* from ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        local import_name=$(echo "$line" | sed -E "s/.*import ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\1/")
        local module_name=$(echo "$line" | sed -E "s/.*import ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\2/")
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "BINDING|${import_name}|${clean_module}|default|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 2: import { named1, named2 } from 'module'
    grep -n "import {[^}]*} from ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        local bindings_part=$(echo "$line" | sed -E 's/.*import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"].*/\1/')
        local module_name=$(echo "$line" | sed -E 's/.*import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"].*/\2/')
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            
            echo "$bindings_part" | tr ',' '\n' | while read -r binding; do
                binding=$(echo "$binding" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
                
                if echo "$binding" | grep -q " as "; then
                    local original=$(echo "$binding" | sed -E 's/^([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]+as[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)$/\1/')
                    local alias=$(echo "$binding" | sed -E 's/^([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]+as[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)$/\2/')
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
        local import_name=$(echo "$line" | sed -E "s/.*import \* as ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\1/")
        local module_name=$(echo "$line" | sed -E "s/.*import \* as ([a-zA-Z_\$][a-zA-Z0-9_\$]*) from ['\"]([^'\"]+)['\"].*/\2/")
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "BINDING|${import_name}|${clean_module}|namespace|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 4: import 'module' (side effect)
    grep -n "^import ['\"][^'\"]*['\"]" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        local module_name=$(echo "$line" | sed -E "s/import ['\"]([^'\"]+)['\"];?/\1/")
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|side_effect|${linenum}" >> "$tmp_output"
        fi
    done
    
    # Pattern 5: const/let/var x = require('module')
    grep -n "require(['\"][^'\"]*['\"])" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        local module_name=$(echo "$line" | sed -E "s/.*require\(['\"]([^'\"]+)['\"]\).*/\1/")
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            
            local varname=$(echo "$line" | sed -E 's/.*(const|let|var)[[:space:]]+([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]*=.*/\2/')
            if [ -n "$varname" ] && [ "$varname" != "$line" ]; then
                echo "BINDING|${varname}|${clean_module}|require|${linenum}" >> "$tmp_output"
            else
                echo "IMPORT|${clean_module}|require_side_effect|${linenum}" >> "$tmp_output"
            fi
        fi
    done
    
    # Pattern 6: dynamic import()
    grep -n "import(['\"][^'\"]*['\"])" "$file" 2>/dev/null | while IFS=: read -r linenum line; do
        local module_name=$(echo "$line" | sed -E "s/.*import\(['\"]([^'\"]+)['\"]\).*/\1/")
        
        if is_native_module "$module_name"; then
            local clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|dynamic|${linenum}" >> "$tmp_output"
        fi
    done
}

# Track usage of imported bindings
track_usage() {
    local file="$1"
    local bindings_file="$2"
    local tmp_output="$3"
    
    > "$tmp_output"
    
    grep "^BINDING|" "$bindings_file" 2>/dev/null | while IFS='|' read -r type binding_name module import_type linenum; do
        if [ -z "$binding_name" ]; then
            continue
        fi
        
        local import_line=$linenum
        
        # Pattern: binding.method()
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*[[:space:]]*(" 2>/dev/null | while IFS=: read -r uline ucode; do
            local method=$(echo "$ucode" | sed -E "s/.*${binding_name}\.([a-zA-Z_\$][a-zA-Z0-9_\$]*)[[:space:]]*\(.*/\1/")
            echo "METHOD|${module}|${binding_name}|${method}" >> "$tmp_output"
        done
        
        # Pattern: binding.property
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*" 2>/dev/null | grep -v "${binding_name}\.[a-zA-Z_\$][a-zA-Z0-9_\$]*[[:space:]]*(" | while IFS=: read -r uline ucode; do
            local prop=$(echo "$ucode" | sed -E "s/.*${binding_name}\.([a-zA-Z_\$][a-zA-Z0-9_\$]*).*/\1/")
            echo "PROPERTY|${module}|${binding_name}|${prop}" >> "$tmp_output"
        done
        
        # Pattern: binding() used as function
        tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "[^.]${binding_name}[[:space:]]*(" 2>/dev/null | while IFS=: read -r uline ucode; do
            echo "FUNCTION_CALL|${module}|${binding_name}|function" >> "$tmp_output"
        done
        
        # Pattern: binding used generally
        local used_line=$(tail -n +$((import_line + 1)) "$file" 2>/dev/null | grep -n "[^.]${binding_name}[^a-zA-Z0-9_\$.]" 2>/dev/null | grep -v "${binding_name}\." | grep -v "${binding_name}(" | head -1)
        if [ -n "$used_line" ]; then
            echo "USED|${module}|${binding_name}|general" >> "$tmp_output"
        fi
    done
}

# Classify a binding as interface or function
classify_interface() {
    local binding_name="$1"
    local module="$2"
    local usage_file="$3"
    
    local method_count=$(grep "^METHOD|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    local prop_count=$(grep "^PROPERTY|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    local func_call=$(grep "^FUNCTION_CALL|${module}|${binding_name}|" "$usage_file" 2>/dev/null | wc -l)
    
    if [ "$method_count" -gt 0 ] || [ "$prop_count" -gt 0 ]; then
        echo "interface"
    elif [ "$func_call" -gt 0 ]; then
        echo "function"
    else
        echo "variable"
    fi
}

# Extract final results per file
extract_final_results() {
    local bindings_file="$1"
    local usage_file="$2"
    local tmp_final="$3"
    local file_index="$4"
    
    > "$tmp_final"
    
    local used_modules_file="/tmp/jsinfo_used_modules_${PID}_${file_index}"
    
    if [ -s "$usage_file" ]; then
        cut -d'|' -f2 "$usage_file" | sort -u > "$used_modules_file"
    else
        > "$used_modules_file"
    fi
    
    while read -r module; do
        if [ -z "$module" ]; then
            continue
        fi
        
        local bindings=$(grep "^BINDING|[^|]*|${module}|" "$bindings_file" 2>/dev/null | cut -d'|' -f2 | sort -u)
        
        for binding in $bindings; do
            if [ -z "$binding" ]; then
                continue
            fi
            
            # Fixed: use grep -q and check exit status instead of -c
            if grep -q "^[A-Z_]*|${module}|${binding}|" "$usage_file" 2>/dev/null; then
                local original=$(grep "^BINDING_ORIGINAL|${binding}|" "$bindings_file" 2>/dev/null | cut -d'|' -f3 | head -1)
                if [ -z "$original" ]; then
                    original="$binding"
                fi
                
                local type=$(classify_interface "$binding" "$module" "$usage_file")
                
                local methods=$(grep "^METHOD|${module}|${binding}|" "$usage_file" 2>/dev/null | cut -d'|' -f4 | sort -u | tr '\n' ',' | sed 's/,$//')
                local properties=$(grep "^PROPERTY|${module}|${binding}|" "$usage_file" 2>/dev/null | cut -d'|' -f4 | sort -u | tr '\n' ',' | sed 's/,$//')
                
                echo "USED_INTERFACE|${module}|${original}|${binding}|${type}|${methods}|${properties}" >> "$tmp_final"
            fi
        done
        
        if grep -q "^IMPORT|${module}|" "$bindings_file" 2>/dev/null; then
            echo "MODULE_IMPORT|${module}|side_effect" >> "$tmp_final"
        fi
        
    done < "$used_modules_file"
    
    rm -f "$used_modules_file"
}

# Get combined results
get_combined_results() {
    local file_index=$1
    local temp_dir=$2
    
    local combined="${temp_dir}/combined_final"
    > "$combined"
    
    for i in $(seq 0 $((file_index - 1))); do
        local final_file="${temp_dir}/final_${i}"
        if [ -f "$final_file" ] && [ -s "$final_file" ]; then
            cat "$final_file" >> "$combined"
        fi
    done
    
    echo "$combined"
}

# Count totals
count_totals() {
    local combined="$1"
    
    local total_modules=0
    local total_interfaces=0
    local total_functions=0
    local total_variables=0
    local total_methods=0
    
    if [ -s "$combined" ]; then
        total_modules=$(cut -d'|' -f2 "$combined" | sort -u | wc -l)
        total_interfaces=$(grep "^USED_INTERFACE|" "$combined" | grep "|interface|" | cut -d'|' -f2,3 | sort -u | wc -l)
        total_functions=$(grep "^USED_INTERFACE|" "$combined" | grep "|function|" | cut -d'|' -f2,3 | sort -u | wc -l)
        total_variables=$(grep "^USED_INTERFACE|" "$combined" | grep "|variable|" | cut -d'|' -f2,3 | sort -u | wc -l)
        total_methods=$(grep "^USED_INTERFACE|" "$combined" | cut -d'|' -f6 | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
    fi
    
    echo "${total_modules}|${total_interfaces}|${total_functions}|${total_variables}|${total_methods}"
}

# Print one-line totals with color
print_one_line_totals() {
    local totals="$1"
    
    local total_modules=$(echo "$totals" | cut -d'|' -f1)
    local total_interfaces=$(echo "$totals" | cut -d'|' -f2)
    local total_functions=$(echo "$totals" | cut -d'|' -f3)
    local total_variables=$(echo "$totals" | cut -d'|' -f4)
    local total_methods=$(echo "$totals" | cut -d'|' -f5)
    
    printf "${COLOR_BOLD}${COLOR_CYAN}modules${COLOR_RESET}: ${COLOR_GREEN}%s${COLOR_RESET}  " "$total_modules"
    printf "${COLOR_BOLD}${COLOR_YELLOW}interfaces${COLOR_RESET}: ${COLOR_GREEN}%s${COLOR_RESET}  " "$total_interfaces"
    printf "${COLOR_BOLD}${COLOR_BLUE}functions${COLOR_RESET}: ${COLOR_GREEN}%s${COLOR_RESET}  " "$total_functions"
    printf "${COLOR_BOLD}${COLOR_MAGENTA}variables${COLOR_RESET}: ${COLOR_GREEN}%s${COLOR_RESET}  " "$total_variables"
    printf "${COLOR_BOLD}${COLOR_CYAN}methods${COLOR_RESET}: ${COLOR_GREEN}%s${COLOR_RESET}\n" "$total_methods"
}

# Print module tree
print_module_tree() {
    local combined="$1"
    
    if [ ! -s "$combined" ]; then
        return
    fi
    
    echo ""
    printf "${COLOR_BOLD}${COLOR_GREEN}▸ NODE.JS INTERFACE TREE${COLOR_RESET}\n"
    echo ""
    
    # Get unique modules
    local modules=$(cut -d'|' -f2 "$combined" | sort -u)
    
    for module in $modules; do
        if [ -z "$module" ]; then
            continue
        fi
        
        printf "${COLOR_BOLD}${COLOR_CYAN}▶ ${module}${COLOR_RESET}\n"
        
        # Get all used interfaces/functions/variables for this module
        grep "^USED_INTERFACE|${module}|" "$combined" 2>/dev/null | sort -t'|' -k3,3 -u | while IFS='|' read -r _ _ original alias type methods properties; do
            if [ "$original" != "$alias" ]; then
                local display_name="${original} → ${alias}"
            else
                local display_name="${original}"
            fi
            
            case "$type" in
                interface)
                    printf "  ${COLOR_BOLD}${COLOR_YELLOW}○ ${display_name}${COLOR_RESET} ${COLOR_GREEN}(interface)${COLOR_RESET}\n"
                    
                    if [ -n "$methods" ] && [ "$methods" != "" ]; then
                        echo "$methods" | tr ',' '\n' | sort -u | while read -r method; do
                            if [ -n "$method" ]; then
                                printf "    ${COLOR_CYAN}▹ ${method}()${COLOR_RESET}\n"
                            fi
                        done
                    fi
                    
                    if [ -n "$properties" ] && [ "$properties" != "" ]; then
                        echo "$properties" | tr ',' '\n' | sort -u | while read -r prop; do
                            if [ -n "$prop" ]; then
                                printf "    ${COLOR_BLUE}▹ ${prop}${COLOR_RESET}\n"
                            fi
                        done
                    fi
                    ;;
                function)
                    printf "  ${COLOR_BOLD}${COLOR_BLUE}ƒ ${display_name}${COLOR_RESET} ${COLOR_GREEN}(function)${COLOR_RESET}\n"
                    ;;
                variable)
                    printf "  ${COLOR_BOLD}${COLOR_MAGENTA}• ${display_name}${COLOR_RESET} ${COLOR_GREEN}(variable)${COLOR_RESET}\n"
                    ;;
            esac
        done
        
        # Check for side-effect imports
        if grep -q "^MODULE_IMPORT|${module}|" "$combined" 2>/dev/null; then
            printf "  ${COLOR_GREEN}↳ side-effect import${COLOR_RESET}\n"
        fi
        
        echo ""
    done
}

# Combine all results for saving
combine_all_results() {
    local output_dir="$1"
    local combined="$2"
    
    if [ ! -s "$combined" ]; then
        return 1
    fi
    
    sort -u "$combined" > "${output_dir}/all_results.txt"
    
    > "${output_dir}/module_summary.txt"
    
    local modules=$(cut -d'|' -f2 "$combined" | sort -u)
    
    for module in $modules; do
        if [ -z "$module" ]; then
            continue
        fi
        
        local interfaces=$(grep "^USED_INTERFACE|${module}|" "$combined" 2>/dev/null | cut -d'|' -f3,5 | sort -u)
        
        echo "MODULE|${module}" >> "${output_dir}/module_summary.txt"
        
        echo "$interfaces" | while IFS='|' read -r name type; do
            if [ -z "$name" ]; then
                continue
            fi
            
            local all_methods=$(grep "^USED_INTERFACE|${module}|${name}|" "$combined" 2>/dev/null | cut -d'|' -f6 | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
            local all_props=$(grep "^USED_INTERFACE|${module}|${name}|" "$combined" 2>/dev/null | cut -d'|' -f7 | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
            
            echo "INTERFACE|${name}|${type}|${all_methods}|${all_props}" >> "${output_dir}/module_summary.txt"
        done
    done
    
    return 0
}

# Save results as directory structure with .method files
save_as_files() {
    local summary_file="$1"
    local output_dir="$2"
    
    mkdir -p "$output_dir"
    
    local current_module=""
    
    cat "$summary_file" | while IFS='|' read -r type data1 data2 data3 data4; do
        case "$type" in
            MODULE)
                current_module="$data1"
                local safe_module=$(echo "$current_module" | tr '/' '_')
                local module_dir="${output_dir}/${safe_module}"
                mkdir -p "$module_dir"
                
                cat > "${module_dir}/README.md" << EOF
# Module: ${current_module}

## Interfaces & Functions

EOF
                ;;
            INTERFACE)
                local name="$data1"
                local itype="$data2"
                local methods="$data3"
                local props="$data4"
                
                if [ -z "$current_module" ]; then
                    continue
                fi
                
                local safe_module=$(echo "$current_module" | tr '/' '_')
                local module_dir="${output_dir}/${safe_module}"
                
                if [ "$itype" = "interface" ]; then
                    echo "### Interface: ${name}" >> "${module_dir}/README.md"
                    
                    if [ -n "$methods" ] && [ "$methods" != "" ]; then
                        echo "" >> "${module_dir}/README.md"
                        echo "**Methods:**" >> "${module_dir}/README.md"
                        echo "$methods" | tr ',' '\n' | sort -u | while read -r method; do
                            if [ -n "$method" ]; then
                                echo "- \`${method}()\`" >> "${module_dir}/README.md"
                                local safe_method=$(echo "$method" | sed 's/[^a-zA-Z0-9_]/_/g')
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
                    echo "### Function: ${name}()" >> "${module_dir}/README.md"
                    echo "" >> "${module_dir}/README.md"
                    local safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9_]/_/g')
                    echo "# Function: ${name}()" > "${module_dir}/${safe_name}.function"
                else
                    echo "### Variable: ${name}" >> "${module_dir}/README.md"
                    echo "" >> "${module_dir}/README.md"
                    local safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9_]/_/g')
                    echo "# Variable: ${name}" > "${module_dir}/${safe_name}.variable"
                fi
                ;;
        esac
    done
    
    local total_modules=$(grep "^MODULE|" "$summary_file" 2>/dev/null | wc -l)
    
    cat > "${output_dir}/README.md" << EOF
# Node.js Interface Analysis

**Generated:** $(date)
**Files analyzed:** ${TOTAL_FILES}
**Total modules used:** ${total_modules}

## Modules

EOF
    
    grep "^MODULE|" "$summary_file" 2>/dev/null | while IFS='|' read -r _ module; do
        local safe_module=$(echo "$module" | tr '/' '_')
        local iface_count=$(grep "INTERFACE|" "$summary_file" 2>/dev/null | grep "|interface|" | wc -l)
        local func_count=$(grep "INTERFACE|" "$summary_file" 2>/dev/null | grep "|function|" | wc -l)
        local var_count=$(grep "INTERFACE|" "$summary_file" 2>/dev/null | grep "|variable|" | wc -l)
        echo "- ${module} (${iface_count} interfaces, ${func_count} functions, ${var_count} variables)" >> "${output_dir}/README.md"
    done
    
    echo "" >> "${output_dir}/README.md"
    echo "---" >> "${output_dir}/README.md"
    echo "*Generated by Node.js Interface Analyzer*" >> "${output_dir}/README.md"
}

# Save as JSON
save_as_json() {
    local summary_file="$1"
    local output_dir="$2"
    
    mkdir -p "$output_dir"
    
    local json_file="${output_dir}/analysis.json"
    
    local total_modules=$(grep "^MODULE|" "$summary_file" 2>/dev/null | wc -l)
    
    cat > "$json_file" << EOF
{
  "metadata": {
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
    "files_analyzed": ${TOTAL_FILES},
    "total_modules": ${total_modules}
  },
  "modules": {
EOF
    
    local first_module=1
    grep "^MODULE|" "$summary_file" 2>/dev/null | while IFS='|' read -r _ module; do
        if [ -z "$module" ]; then
            continue
        fi
        
        local module_interfaces=$(grep "^INTERFACE|[^|]*|[^|]*|" "$summary_file" 2>/dev/null || true)
        
        if [ $first_module -eq 1 ]; then
            first_module=0
        else
            echo "    }," >> "$json_file"
        fi
        
        echo "    \"${module}\": {" >> "$json_file"
        echo "      \"interfaces\": [" >> "$json_file"
        
        local first_iface=1
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
            
            if [ -n "$methods" ]; then
                echo "          \"methods\": [" >> "$json_file"
                echo "$methods" | tr ',' '\n' | grep -v '^$' | sort -u | while read -r method; do
                    echo "            \"${method}\"," >> "$json_file"
                done
                sed -i '$ s/,$//' "$json_file"
                echo "          ]," >> "$json_file"
            else
                echo "          \"methods\": []," >> "$json_file"
            fi
            
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
    
    echo "    }" >> "$json_file"
    echo "  }" >> "$json_file"
    echo "}" >> "$json_file"
    
    echo "JSON saved to: $json_file"
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
    
    # Handle clear mode
    if [ "$CLEAR_MODE" = "1" ]; then
        if [ -d "$BASE_DIR" ]; then
            rm -rf "$BASE_DIR"
            echo "Cleared ${BASE_DIR}"
        else
            echo "Nothing to clear (${BASE_DIR} does not exist)"
        fi
        
        if [ -z "$PATHS" ]; then
            exit 0
        fi
    fi
    
    # If no paths provided
    if [ -z "$PATHS" ]; then
        echo "Please provide at least one .js file or directory"
        echo "Usage: $0 [--json] [--file] [--clear] <file1.js> <file2.js> <dir1> ..."
        echo "  --json   Save analysis as JSON in /tmp/jsinfo"
        echo "  --file   Save analysis with .method files in /tmp/jsinfo"
        echo "  --clear  Clear /tmp/jsinfo (can be used alone or before saving)"
        exit 1
    fi
    
    # Create temp directory
    local TEMP_DIR="/tmp/jsinfo_${PID}"
    mkdir -p "$TEMP_DIR"
    
    # Collect all JS files
    local ALL_FILES_FILE="${TEMP_DIR}/all_files.txt"
    > "$ALL_FILES_FILE"
    
    for path in $PATHS; do
        local resolved_path
        case "$path" in
            /*)
                resolved_path="$path"
                ;;
            *)
                resolved_path="${CALL_DIR}/${path}"
                ;;
        esac
        
        if [ -f "$resolved_path" ]; then
            case "$resolved_path" in
                *.js|*.mjs|*.cjs)
                    echo "$resolved_path" >> "$ALL_FILES_FILE"
                    ;;
            esac
        elif [ -d "$resolved_path" ]; then
            find "$resolved_path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) 2>/dev/null >> "$ALL_FILES_FILE" || true
        else
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
    
    if [ -s "$ALL_FILES_FILE" ]; then
        sort -u "$ALL_FILES_FILE" | grep -v '^$' > "${ALL_FILES_FILE}.tmp"
        mv "${ALL_FILES_FILE}.tmp" "$ALL_FILES_FILE"
    fi
    
    if [ ! -s "$ALL_FILES_FILE" ]; then
        echo "No .js files found in: $PATHS"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    TOTAL_FILES=$(wc -l < "$ALL_FILES_FILE" 2>/dev/null || echo 0)
    
    # Process each file
    local file_index=0
    while IFS= read -r file; do
        if [ -z "$file" ]; then
            continue
        fi
        
        local bindings_file="${TEMP_DIR}/bindings_${file_index}"
        local usage_file="${TEMP_DIR}/usage_${file_index}"
        local final_file="${TEMP_DIR}/final_${file_index}"
        
        parse_imports "$file" "$bindings_file"
        track_usage "$file" "$bindings_file" "$usage_file"
        extract_final_results "$bindings_file" "$usage_file" "$final_file" "$file_index"
        
        file_index=$((file_index + 1))
    done < "$ALL_FILES_FILE"
    
    # Get combined results
    local combined=$(get_combined_results "$file_index" "$TEMP_DIR")
    
    # Get totals
    local totals=$(count_totals "$combined")
    
    # Check if we need to save
    if [ "$JSON_MODE" = "1" ] || [ "$FILE_MODE" = "1" ]; then
        local output_dir="$TARGET_DIR"
        mkdir -p "$output_dir"
        
        if combine_all_results "$output_dir" "$combined"; then
            if [ "$JSON_MODE" = "1" ]; then
                save_as_json "${output_dir}/module_summary.txt" "$output_dir"
            fi
            if [ "$FILE_MODE" = "1" ]; then
                save_as_files "${output_dir}/module_summary.txt" "$output_dir"
            fi
            echo ""
            echo "Results saved to: $output_dir"
            
            # Also print the tree when saving
            print_one_line_totals "$totals"
            print_module_tree "$combined"
        else
            echo "No native Node.js modules detected."
            rm -rf "$output_dir"
        fi
    else
        # Default mode: print one-line totals + tree
        print_one_line_totals "$totals"
        print_module_tree "$combined"
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
}

# Run main function
main "$@"