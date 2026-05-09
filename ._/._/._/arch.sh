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

# Native Node.js modules set (simulated with case statements)
is_native_module() {
    module="$1"
    # Remove node: prefix if present
    module="${module#node:}"
    
    # Check if it's a file import (contains . or / or starts with .)
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

# Count native module imports in a file
count_native_imports() {
    file="$1"
    tmp_output="$2"
    
    > "$tmp_output"
    
    # Process import default from 'module'
    grep -oE "import [a-zA-Z_][a-zA-Z0-9_]* from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        import_name=$(echo "$line" | sed -E "s/import ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\1/")
        module_name=$(echo "$line" | sed -E "s/import ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\2/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|import ${import_name}" >> "$tmp_output"
        fi
    done
    
    # Process import { named } from 'module'
    grep -oE "import \{[^}]+\} from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        bindings=$(echo "$line" | sed -E 's/import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"]/\1/')
        module_name=$(echo "$line" | sed -E 's/import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"]/\2/')
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|import { ${bindings} }" >> "$tmp_output"
        fi
    done
    
    # Process import * as name from 'module'
    grep -oE "import \* as [a-zA-Z_][a-zA-Z0-9_]* from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        import_name=$(echo "$line" | sed -E "s/import \* as ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\1/")
        module_name=$(echo "$line" | sed -E "s/import \* as ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\2/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|import * as ${import_name}" >> "$tmp_output"
        fi
    done
    
    # Process import 'module' (side effect)
    grep -oE "import ['\"][^'\"]+['\"]" "$file" | grep -v "from" | while read -r line; do
        module_name=$(echo "$line" | sed -E "s/import ['\"]([^'\"]+)['\"]/\1/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|import (side effect)" >> "$tmp_output"
        fi
    done
    
    # Process dynamic import()
    grep -oE "import\(['\"][^'\"]+['\"]\)" "$file" | while read -r line; do
        module_name=$(echo "$line" | sed -E "s/import\(['\"]([^'\"]+)['\"]\)/\1/")
        
        if is_native_module "$module_name"; then
            clean_module=$(echo "$module_name" | sed 's/^node://')
            echo "IMPORT|${clean_module}|import() (dynamic)" >> "$tmp_output"
        fi
    done
}

# Extract interfaces and methods
extract_interfaces() {
    file="$1"
    tmp_output="$2"
    
    > "$tmp_output"
    
    # First, extract import bindings
    tmp_bindings="/tmp/jsinfo_bindings_$$"
    > "$tmp_bindings"
    
    # Extract default imports
    grep -oE "import [a-zA-Z_][a-zA-Z0-9_]* from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        import_name=$(echo "$line" | sed -E "s/import ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\1/")
        module_name=$(echo "$line" | sed -E "s/import ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\2/" | sed 's/^node://')
        
        if is_native_module "$module_name"; then
            echo "BINDING|${import_name}|${module_name}" >> "$tmp_bindings"
        fi
    done
    
    # Extract namespace imports
    grep -oE "import \* as [a-zA-Z_][a-zA-Z0-9_]* from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        import_name=$(echo "$line" | sed -E "s/import \* as ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\1/")
        module_name=$(echo "$line" | sed -E "s/import \* as ([a-zA-Z_][a-zA-Z0-9_]*) from ['\"]([^'\"]+)['\"]/\2/" | sed 's/^node://')
        
        if is_native_module "$module_name"; then
            echo "BINDING|${import_name}|${module_name}" >> "$tmp_bindings"
        fi
    done
    
    # Extract named imports
    grep -oE "import \{[^}]+\} from ['\"][^'\"]+['\"]" "$file" | while read -r line; do
        bindings=$(echo "$line" | sed -E 's/import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"]/\1/')
        module_name=$(echo "$line" | sed -E 's/import \{([^}]+)\} from ['"'"'"]([^'"'"'"]+)['"'"'"]/\2/' | sed 's/^node://')
        
        if is_native_module "$module_name"; then
            # Split bindings and process each
            echo "$bindings" | tr ',' '\n' | while read -r binding; do
                binding=$(echo "$binding" | sed -E 's/.* as ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/;t; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*$/\1/')
                echo "BINDING|${binding}|${module_name}" >> "$tmp_bindings"
            done
        fi
    done
    
    # Find method calls on imported objects: obj.method()
    grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$file" | while read -r line; do
        object_name=$(echo "$line" | sed -E 's/([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/\1/')
        method_name=$(echo "$line" | sed -E 's/([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/\2/')
        
        module=$(grep "^BINDING|${object_name}|" "$tmp_bindings" 2>/dev/null | head -1 | cut -d'|' -f3)
        if [ -n "$module" ]; then
            echo "INTERFACE|${module}|${method_name}" >> "$tmp_output"
        fi
    done
    
    # Find property access on imported objects
    grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*' "$file" | grep -v '\.prototype' | while read -r line; do
        object_name=$(echo "$line" | sed -E 's/([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)/\1/')
        prop_name=$(echo "$line" | sed -E 's/([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)/\2/')
        
        module=$(grep "^BINDING|${object_name}|" "$tmp_bindings" 2>/dev/null | head -1 | cut -d'|' -f3)
        if [ -n "$module" ]; then
            echo "INTERFACE|${module}|${prop_name}" >> "$tmp_output"
        fi
    done
    
    rm -f "$tmp_bindings"
}

# Get unique variations per module with cleaned import statements
get_unique_variations() {
    input_file="$1"
    sort -u "$input_file" | awk -F'|' '
    {
        module = $2
        variation = $3
        if (!(module in variations)) {
            variations[module] = ""
        }
        if (variations[module] !~ variation) {
            if (variations[module] == "") {
                variations[module] = variation
            } else {
                variations[module] = variations[module] "|" variation
            }
        }
    }
    END {
        for (module in variations) {
            # Clean up variations to show only the import pattern
            gsub(/import [a-zA-Z_][a-zA-Z0-9_]* from /, "import ", variations[module])
            gsub(/import \* as [a-zA-Z_][a-zA-Z0-9_]* from /, "import * as namespace from ", variations[module])
            print module ":" variations[module]
        }
    }'
}

# Get unique interfaces per module (deduplicated methods)
get_unique_interfaces() {
    input_file="$1"
    sort -u "$input_file" | awk -F'|' '
    {
        module = $2
        method = $3
        if (!(module in methods)) {
            methods[module] = ""
        }
        if (methods[module] !~ method) {
            if (methods[module] == "") {
                methods[module] = method
            } else {
                methods[module] = methods[module] "," method
            }
        }
    }
    END {
        for (module in methods) {
            # Sort methods alphabetically
            split(methods[module], arr, ",")
            asort(arr)
            sorted = ""
            for (i in arr) {
                if (sorted == "") sorted = arr[i]
                else sorted = sorted "," arr[i]
            }
            print module ":" sorted
        }
    }'
}

# Print results to console
print_results() {
    import_file="$1"
    interface_file="$2"
    
    if [ ! -s "$import_file" ]; then
        echo "   No native Node.js module imports found."
        return
    fi
    
    # Get unique variations
    variations=$(get_unique_variations "$import_file")
    total_unique=0
    
    echo "$variations" | while IFS=':' read -r module vars; do
        if [ -n "$module" ]; then
            # Count unique variations
            count=$(echo "$vars" | tr '|' '\n' | wc -l)
            total_unique=$((total_unique + count))
            
            echo "   📦 ${module}:"
            echo "      Unique variations: ${count}"
            echo "      Variations:"
            echo "$vars" | tr '|' '\n' | while read -r var; do
                echo "        • ${var}"
            done
            
            # Show interfaces for this module
            if [ -s "$interface_file" ]; then
                methods=$(grep "^INTERFACE|${module}|" "$interface_file" | cut -d'|' -f3 | sort -u)
                if [ -n "$methods" ]; then
                    method_count=$(echo "$methods" | wc -l)
                    echo "      Methods/Interfaces (${method_count}):"
                    echo "$methods" | while read -r method; do
                        echo "        - ${method}"
                    done
                fi
            fi
        fi
    done
}

# Direct save to /tmp (default mode with directories)
direct_save() {
    TARGET_DIR="$BASE_DIR/$TIMESTAMP"
    mkdir -p "$TARGET_DIR"
    
    tmp_combined_imports="/tmp/jsinfo_combined_imports_$$"
    tmp_combined_interfaces="/tmp/jsinfo_combined_interfaces_$$"
    
    > "$tmp_combined_imports"
    > "$tmp_combined_interfaces"
    
    # Combine all results
    for result_dir in /tmp/jsinfo_results_$$_*; do
        if [ -f "${result_dir}/imports" ]; then
            cat "${result_dir}/imports" >> "$tmp_combined_imports"
        fi
        if [ -f "${result_dir}/interfaces" ]; then
            cat "${result_dir}/interfaces" >> "$tmp_combined_interfaces"
        fi
    done
    
    # Get unique data
    get_unique_interfaces "$tmp_combined_interfaces" > "/tmp/jsinfo_interfaces_$$"
    total_unique_methods=$(cut -d':' -f2 "/tmp/jsinfo_interfaces_$$" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
    
    echo "💾 Saving directly to: $TARGET_DIR"
    
    # Process each module
    get_unique_variations "$tmp_combined_imports" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            safe_module=$(echo "$module" | tr '/' '_')
            module_dir="$TARGET_DIR/${safe_module}"
            mkdir -p "$module_dir"
            
            # Create README for module
            cat > "$module_dir/README.md" << MODULE_EOF
# Module: ${module}

## Import Variations
$(echo "$variations" | tr '|' '\n' | sort -u | sed 's/^/- `/; s/$/`/')

## Methods
$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | sort -u | sed 's/^/- /')

MODULE_EOF
            
            # Create individual method files
            grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | sort -u | while read -r method; do
                if [ -n "$method" ]; then
                    safe_method=$(echo "$method" | sed 's/[^a-zA-Z0-9_]/_/g')
                    echo "# Method: ${method}()" > "$module_dir/${safe_method}.method"
                fi
            done
        fi
    done
    
    # Create root README
    cat > "$TARGET_DIR/README.md" << ROOT_EOF
# Node.js Interface Analysis

**Generated:** $(date)
**Files analyzed:** ${TOTAL_FILES}
**Unique methods:** ${total_unique_methods}

## Modules Overview

$(get_unique_variations "$tmp_combined_imports" | while IFS=':' read -r module variations; do
    if [ -n "$module" ]; then
        method_count=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | grep -v '^$' | wc -l)
        echo "- 📦 **${module}** (${method_count} methods)"
    fi
done)

---
*Generated by Node.js Interface Analyzer*
ROOT_EOF
    
    echo "✅ Data saved directly to: $TARGET_DIR"
    echo "📄 Root README: $TARGET_DIR/README.md"
    
    # Cleanup
    rm -f "$tmp_combined_imports" "$tmp_combined_interfaces" /tmp/jsinfo_interfaces_$$
}

# Direct JSON save to /tmp
direct_json_save() {
    TARGET_DIR="$BASE_DIR/json/$TIMESTAMP"
    mkdir -p "$TARGET_DIR/modules"
    
    tmp_combined_imports="/tmp/jsinfo_combined_imports_$$"
    tmp_combined_interfaces="/tmp/jsinfo_combined_interfaces_$$"
    
    > "$tmp_combined_imports"
    > "$tmp_combined_interfaces"
    
    # Combine all results
    for result_dir in /tmp/jsinfo_results_$$_*; do
        if [ -f "${result_dir}/imports" ]; then
            cat "${result_dir}/imports" >> "$tmp_combined_imports"
        fi
        if [ -f "${result_dir}/interfaces" ]; then
            cat "${result_dir}/interfaces" >> "$tmp_combined_interfaces"
        fi
    done
    
    # Get unique data
    get_unique_variations "$tmp_combined_imports" > "/tmp/jsinfo_vars_$$"
    get_unique_interfaces "$tmp_combined_interfaces" > "/tmp/jsinfo_interfaces_$$"
    
    total_unique_methods=$(cut -d':' -f2 "/tmp/jsinfo_interfaces_$$" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
    total_modules=$(cat "/tmp/jsinfo_vars_$$" | grep -c '^[^:]\+:')
    
    echo "💾 Saving JSON directly to: $TARGET_DIR"
    
    # Build main JSON
    cat > "$TARGET_DIR/analysis.json" << MAIN_EOF
{
  "metadata": {
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
    "files_analyzed": ${TOTAL_FILES},
    "total_unique_methods": ${total_unique_methods},
    "total_modules": ${total_modules}
  },
  "modules": {
MAIN_EOF
    
    # Add each module
    first=1
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            # Get methods for this module
            methods_line=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2)
            
            # Create methods array
            if [ -n "$methods_line" ]; then
                methods_array=$(echo "$methods_line" | tr ',' '\n' | sed 's/^/      "/; s/$/"/' | paste -sd ',' -)
            else
                methods_array=""
            fi
            
            # Create variations array (clean)
            variations_array=$(echo "$variations" | tr '|' '\n' | sed 's/^/      "/; s/$/"/' | paste -sd ',' -)
            
            # Add to JSON
            if [ $first -eq 1 ]; then
                echo "    \"${module}\": {" >> "$TARGET_DIR/analysis.json"
                first=0
            else
                echo "    \"${module}\": {" >> "$TARGET_DIR/analysis.json"
            fi
            
            echo "      \"methods\": [${methods_array}]," >> "$TARGET_DIR/analysis.json"
            echo "      \"import_variations\": [${variations_array}]" >> "$TARGET_DIR/analysis.json"
            echo "    }," >> "$TARGET_DIR/analysis.json"
        fi
    done
    
    # Remove trailing comma and close
    sed -i '$ s/,$//' "$TARGET_DIR/analysis.json"
    echo "  }" >> "$TARGET_DIR/analysis.json"
    echo "}" >> "$TARGET_DIR/analysis.json"
    
    # Create individual module files with cleaner structure
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            safe_module=$(echo "$module" | sed 's/\//_/g')
            methods_line=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2)
            
            # Create methods array
            if [ -n "$methods_line" ]; then
                methods_array=$(echo "$methods_line" | tr ',' '\n' | sed 's/^/    "/; s/$/"/' | paste -sd ',' -)
            else
                methods_array=""
            fi
            
            # Create variations array
            variations_array=$(echo "$variations" | tr '|' '\n' | sed 's/^/    "/; s/$/"/' | paste -sd ',' -)
            
            cat > "$TARGET_DIR/modules/${safe_module}.json" << MODULE_EOF
{
  "module_name": "${module}",
  "total_methods": $(echo "$methods_line" | tr ',' '\n' | grep -v '^$' | wc -l),
  "methods": [${methods_array}],
  "import_variations": [${variations_array}]
}
MODULE_EOF
        fi
    done
    
    # Create summary JSON
    cat > "$TARGET_DIR/summary.json" << SUMMARY_EOF
{
  "statistics": {
    "total_modules": ${total_modules},
    "total_unique_methods": ${total_unique_methods},
    "total_files_analyzed": ${TOTAL_FILES},
    "generation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
    "output_format": "json"
  },
  "module_list": [
$(cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
    if [ -n "$module" ]; then
        method_count=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | grep -v '^$' | wc -l)
        echo "    { \"name\": \"${module}\", \"method_count\": ${method_count} },"
    fi
done | sed '$ s/,$//')
  ]
}
SUMMARY_EOF
    
    echo "✅ JSON saved directly to: $TARGET_DIR"
    echo "📄 Main file: $TARGET_DIR/analysis.json"
    echo "📊 Summary: $TARGET_DIR/summary.json"
    
    # Cleanup
    rm -f "$tmp_combined_imports" "$tmp_combined_interfaces" /tmp/jsinfo_vars_$$ /tmp/jsinfo_interfaces_$$
}

# Generate shell script (script generator mode)
generate_shell_script() {
    output_script="generate-jsinfo-${TIMESTAMP}.sh"
    tmp_combined_imports="/tmp/jsinfo_combined_imports_$$"
    tmp_combined_interfaces="/tmp/jsinfo_combined_interfaces_$$"
    
    > "$tmp_combined_imports"
    > "$tmp_combined_interfaces"
    
    # Combine all results
    for result_dir in /tmp/jsinfo_results_$$_*; do
        if [ -f "${result_dir}/imports" ]; then
            cat "${result_dir}/imports" >> "$tmp_combined_imports"
        fi
        if [ -f "${result_dir}/interfaces" ]; then
            cat "${result_dir}/interfaces" >> "$tmp_combined_interfaces"
        fi
    done
    
    # Get unique variations and count total unique methods
    total_unique_methods=0
    get_unique_interfaces "$tmp_combined_interfaces" > "/tmp/jsinfo_interfaces_$$"
    total_unique_methods=$(cut -d':' -f2 "/tmp/jsinfo_interfaces_$$" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
    
    # Create script header
    cat > "$output_script" << EOF
#!/bin/sh
# Generated by Node.js Interface Analyzer
# Generated at: $(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
# This script creates a directory structure in /tmp/jsinfo/

BASE_DIR="/tmp/jsinfo"
TIMESTAMP="${TIMESTAMP}"
TARGET_DIR="\$BASE_DIR/\$TIMESTAMP"

echo "Creating interface directory structure in \$TARGET_DIR..."
mkdir -p "\$TARGET_DIR"

EOF
    
    # Process unique variations and interfaces
    get_unique_variations "$tmp_combined_imports" > "/tmp/jsinfo_vars_$$" &
    wait
    
    # Generate directory creation and README for each module
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            safe_module=$(echo "$module" | tr '/' '_')
            module_dir="\$TARGET_DIR/${safe_module}"
            
            cat >> "$output_script" << EOF
echo "Creating structure for module: ${module}"
mkdir -p "${module_dir}"

EOF
            
            # Create README for module
            cat >> "$output_script" << EOF
cat > "${module_dir}/README.md" << 'MODULE_EOF'
# Module: ${module}

## Import Variations
EOF
            
            # Add variations to README
            echo "$variations" | tr '|' '\n' | sort -u | while read -r var; do
                echo "- \`${var}\`" >> "$output_script"
            done
            
            cat >> "$output_script" << EOF

## Interfaces & Methods

\`\`\`
EOF
            
            # Get interfaces for this module
            interfaces=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | sort -u)
            if [ -n "$interfaces" ]; then
                echo "$interfaces" | while read -r method; do
                    # Create method file
                    safe_method=$(echo "$method" | sed 's/[^a-zA-Z0-9_]/_/g')
                    echo "echo \"# Method: ${method}\" > \"${module_dir}/${safe_method}.method\"" >> "$output_script"
                    echo "${method}()" >> "$output_script"
                done
            fi
            
            cat >> "$output_script" << EOF
\`\`\`
MODULE_EOF

EOF
        fi
    done
    
    # Create root README with minimalistic tree view
    cat >> "$output_script" << EOF
# Create root README
cat > "\$TARGET_DIR/README.md" << 'ROOT_EOF'
# Node.js Interface Analysis

**Generated:** \$(date)
**Files analyzed:** ${TOTAL_FILES}
**Unique methods:** ${total_unique_methods}

## Modules Overview

\`\`\`
EOF
    
    # Add minimalistic tree view (one line per module with method count)
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            method_count=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | grep -v '^$' | wc -l)
            echo "📦 ${module}/ (${method_count} methods)" >> "$output_script"
        fi
    done
    
    cat >> "$output_script" << EOF
\`\`\`

## Quick Stats

- **Total modules:** $(cat "/tmp/jsinfo_vars_$$" | grep -c '^[^:]\+:')
- **Generated:** \$(date -u +%Y-%m-%d)
- **Format:** One directory per module with .method files

ROOT_EOF

echo ""
echo "✅ Directory structure created successfully!"
echo "📍 Location: \$TARGET_DIR"
echo ""
echo "Modules analyzed:"
EOF
    
    # Add module summary
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            method_count=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2 | tr ',' '\n' | grep -v '^$' | wc -l)
            echo "echo \"  📦 ${module}: ${method_count} methods\"" >> "$output_script"
        fi
    done
    
    cat >> "$output_script" << EOF
echo ""
echo "To explore: cd \$TARGET_DIR && find . -type f | sort"
EOF
    
    # Make script executable
    chmod 755 "$output_script"
    
    # Cleanup
    rm -f "$tmp_combined_imports" "$tmp_combined_interfaces" /tmp/jsinfo_vars_$$ /tmp/jsinfo_interfaces_$$
    
    echo "$output_script"
}

# Generate JSON shell script (script generator mode for JSON)
generate_json_script() {
    output_script="generate-jsinfo-json-${TIMESTAMP}.sh"
    tmp_combined_imports="/tmp/jsinfo_combined_imports_$$"
    tmp_combined_interfaces="/tmp/jsinfo_combined_interfaces_$$"
    
    > "$tmp_combined_imports"
    > "$tmp_combined_interfaces"
    
    # Combine all results
    for result_dir in /tmp/jsinfo_results_$$_*; do
        if [ -f "${result_dir}/imports" ]; then
            cat "${result_dir}/imports" >> "$tmp_combined_imports"
        fi
        if [ -f "${result_dir}/interfaces" ]; then
            cat "${result_dir}/interfaces" >> "$tmp_combined_interfaces"
        fi
    done
    
    # Get unique data
    get_unique_variations "$tmp_combined_imports" > "/tmp/jsinfo_vars_$$"
    get_unique_interfaces "$tmp_combined_interfaces" > "/tmp/jsinfo_interfaces_$$"
    
    # Count total unique methods
    total_unique_methods=$(cut -d':' -f2 "/tmp/jsinfo_interfaces_$$" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
    total_modules=$(cat "/tmp/jsinfo_vars_$$" | grep -c '^[^:]\+:')
    
    # Create JSON script
    cat > "$output_script" << 'EOF'
#!/bin/sh
# Generated by Node.js Interface Analyzer (JSON mode)
EOF

    cat >> "$output_script" << EOF
# Generated at: $(date -u +%Y-%m-%dT%H:%M:%S.%NZ)

BASE_DIR="/tmp/jsinfo/json"
TIMESTAMP="${TIMESTAMP}"
TARGET_DIR="\$BASE_DIR/\$TIMESTAMP"

echo "Creating JSON structure in \$TARGET_DIR..."
mkdir -p "\$TARGET_DIR/modules"

EOF

    # Start building the main JSON file
    cat > "/tmp/jsinfo_main_json_$$" << EOF
{
  "metadata": {
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
    "files_analyzed": ${TOTAL_FILES},
    "total_unique_methods": ${total_unique_methods},
    "total_modules": ${total_modules}
  },
  "modules": {
EOF

    # Add each module to JSON
    first_module=1
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            # Get methods for this module
            methods_line=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2)
            
            # Build methods array
            if [ -n "$methods_line" ]; then
                method_array=$(echo "$methods_line" | tr ',' '\n' | sed 's/^/      "/; s/$/"/' | paste -sd ',' -)
            else
                method_array=""
            fi
            
            # Build variations array
            variation_array=$(echo "$variations" | tr '|' '\n' | sed 's/^/      "/; s/$/"/' | paste -sd ',' -)
            
            # Add comma if not first module
            if [ $first_module -eq 1 ]; then
                echo "    \"${module}\": {" >> "/tmp/jsinfo_main_json_$$"
                first_module=0
            else
                echo "    \"${module}\": {" >> "/tmp/jsinfo_main_json_$$"
            fi
            
            echo "      \"methods\": [${method_array}]," >> "/tmp/jsinfo_main_json_$$"
            echo "      \"import_variations\": [${variation_array}]" >> "/tmp/jsinfo_main_json_$$"
            echo "    }," >> "/tmp/jsinfo_main_json_$$"
        fi
    done
    
    # Remove trailing comma from last module
    sed -i '$ s/,$//' "/tmp/jsinfo_main_json_$$"
    
    # Close JSON
    cat >> "/tmp/jsinfo_main_json_$$" << EOF
  }
}
EOF

    # Add JSON content to script
    echo "cat > \"\$TARGET_DIR/analysis.json\" << 'MAIN_JSON_EOF'" >> "$output_script"
    cat "/tmp/jsinfo_main_json_$$" >> "$output_script"
    echo "MAIN_JSON_EOF" >> "$output_script"
    echo "" >> "$output_script"

    # Create individual module JSON files
    cat "/tmp/jsinfo_vars_$$" | while IFS=':' read -r module variations; do
        if [ -n "$module" ]; then
            safe_module=$(echo "$module" | sed 's/\//_/g')
            methods_line=$(grep "^${module}:" "/tmp/jsinfo_interfaces_$$" 2>/dev/null | cut -d':' -f2)
            
            # Build methods array
            if [ -n "$methods_line" ]; then
                method_array=$(echo "$methods_line" | tr ',' '\n' | sed 's/^/    "/; s/$/"/' | paste -sd ',' -)
            else
                method_array=""
            fi
            
            # Build variations array
            variation_array=$(echo "$variations" | tr '|' '\n' | sed 's/^/    "/; s/$/"/' | paste -sd ',' -)
            
            cat >> "$output_script" << MODULE_EOF
cat > "\$TARGET_DIR/modules/${safe_module}.json" << MODULE_JSON_EOF
{
  "module_name": "${module}",
  "total_methods": $(echo "$methods_line" | tr ',' '\n' | grep -v '^$' | wc -l),
  "methods": [${method_array}],
  "import_variations": [${variation_array}]
}
MODULE_JSON_EOF

MODULE_EOF
        fi
    done

    # Create summary JSON
    cat >> "$output_script" << SUMMARY_EOF

# Create summary JSON
cat > "\$TARGET_DIR/summary.json" << 'SUMMARY_JSON_EOF'
{
  "statistics": {
    "total_modules": ${total_modules},
    "total_methods": ${total_unique_methods},
    "files_analyzed": ${TOTAL_FILES},
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
  }
}
SUMMARY_JSON_EOF

echo ""
echo "✅ JSON structure created successfully!"
echo "📍 Location: \$TARGET_DIR"
echo ""
echo "Files created:"
echo "  - analysis.json (complete analysis)"
echo "  - summary.json (quick overview)"
echo "  - modules/*.json (one per module)"
echo ""
echo "To explore: cd \$TARGET_DIR && ls -la"

SUMMARY_EOF

    # Make script executable
    chmod 755 "$output_script"
    
    # Cleanup
    rm -f "$tmp_combined_imports" "$tmp_combined_interfaces" /tmp/jsinfo_vars_$$ /tmp/jsinfo_interfaces_$$ /tmp/jsinfo_main_json_$$
    
    echo "$output_script"
}

# Get all .js files from path
get_js_files() {
    input_path="$1"
    
    if [ ! -e "$input_path" ]; then
        echo "Path not found: $input_path" >&2
        return
    fi
    
    if [ -f "$input_path" ]; then
        case "$input_path" in
            *.js|*.mjs|*.cjs) echo "$input_path" ;;
        esac
    elif [ -d "$input_path" ]; then
        find "$input_path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \)
    fi
}

# Main execution
main() {
    TOTAL_FILES=0
    
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
        echo "  --script-generator    Generate .sh script instead of saving directly (optional)"
        echo ""
        echo "Default behavior (without --script-generator): Saves directly to /tmp/jsinfo/"
        echo "With --script-generator: Creates a .sh script that you can run later"
        exit 1
    fi
    
    # Collect all JS files
    ALL_FILES=""
    for path in $PATHS; do
        files=$(get_js_files "$path")
        if [ -n "$files" ]; then
            if [ -z "$ALL_FILES" ]; then
                ALL_FILES="$files"
            else
                ALL_FILES="$ALL_FILES
$files"
            fi
        fi
    done
    
    if [ -z "$ALL_FILES" ]; then
        echo "❌ No .js files found"
        exit 1
    fi
    
    # Count files and display
    TOTAL_FILES=$(echo "$ALL_FILES" | wc -l)
    echo "📁 Found ${TOTAL_FILES} JavaScript file(s):"
    echo "$ALL_FILES" | while read -r file; do
        echo "   - ${file}"
    done
    echo ""
    
    # Create temp directory for results
    RESULTS_DIR="/tmp/jsinfo_results_$$_0"
    mkdir -p "$RESULTS_DIR"
    
    # Analyze each file
    file_index=0
    echo "$ALL_FILES" | while read -r file; do
        if [ -n "$file" ]; then
            RESULT_DIR="/tmp/jsinfo_results_$$_${file_index}"
            mkdir -p "$RESULT_DIR"
            
            echo "📄 Analyzing: $(basename "$file")"
            
            # Count imports
            count_native_imports "$file" "${RESULT_DIR}/imports"
            
            # Extract interfaces
            extract_interfaces "$file" "${RESULT_DIR}/interfaces"
            
            # Print results
            print_results "${RESULT_DIR}/imports" "${RESULT_DIR}/interfaces"
            echo ""
            
            file_index=$((file_index + 1))
        fi
    done
    
    wait
    
    # Decide action based on flags
    if [ "$SCRIPT_GENERATOR" = "1" ]; then
        # Generate shell script mode
        if [ "$JSON_MODE" = "1" ]; then
            echo "🔨 Generating JSON shell script..."
            SCRIPT_NAME=$(generate_json_script)
            echo "✅ JSON shell script generated: $SCRIPT_NAME"
            echo ""
            echo "📝 To create the JSON structure, run:"
            echo "   ./$SCRIPT_NAME"
            echo ""
            echo "📍 This will create: /tmp/jsinfo/json/[timestamp]/"
        elif [ "$GENERATE_SH" = "1" ]; then
            echo "🔨 Generating directory shell script..."
            SCRIPT_NAME=$(generate_shell_script)
            echo "✅ Shell script generated: $SCRIPT_NAME"
            echo ""
            echo "📝 To create the interface structure, run:"
            echo "   ./$SCRIPT_NAME"
            echo ""
            echo "📍 This will create: /tmp/jsinfo/[timestamp]/"
        fi
    else
        # Direct save mode (default)
        if [ "$JSON_MODE" = "1" ]; then
            direct_json_save
        elif [ "$GENERATE_SH" = "1" ]; then
            direct_save
        else
            # Default to directory save if no mode specified
            direct_save
        fi
    fi
    
    # Cleanup temp files
    rm -rf /tmp/jsinfo_results_$$_*
}

# Run main function
main "$@"