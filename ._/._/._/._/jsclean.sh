#!/bin/bash

# Function to clean .js files in a single directory (non-recursive)
clean_js_single() {
    local dir="$1"
    local file_count=0
    
    # Check if there are any .js files to remove
    if ls "$dir"/*.js 1> /dev/null 2>&1; then
        file_count=$(ls "$dir"/*.js 2>/dev/null | wc -l)
        rm "$dir"/*.js
        echo "  Removed $file_count .js file(s) from $dir"
    fi
    
    return $file_count
}

# Function to clean .js files recursively
clean_js_recursive() {
    local dir="$1"
    local total_count=0
    local current_count=0
    
    # Clean current directory
    clean_js_single "$dir"
    current_count=$?
    total_count=$((total_count + current_count))
    
    # Recursively process subdirectories
    while IFS= read -r -d '' subdir; do
        # Skip .git directory but include ._ directory
        if [[ "$subdir" == *"/.git"* ]]; then
            continue
        fi
        
        clean_js_recursive "$subdir"
        current_count=$?
        total_count=$((total_count + current_count))
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -name ".git" -print0)
    
    return $total_count
}

# Get the directory where the script is being called from
TARGET_DIR="$(pwd)"
TOTAL_FILES=0

# Check for --full argument
if [[ "$1" == "--full" ]]; then
    echo "Cleaning .js files recursively from $TARGET_DIR"
    echo "----------------------------------------"
    clean_js_recursive "$TARGET_DIR"
    TOTAL_FILES=$?
    echo "----------------------------------------"
    echo "Successfully removed $TOTAL_FILES .js file(s) recursively from $TARGET_DIR"
else
    echo "Cleaning .js files from $TARGET_DIR (non-recursive)"
    echo "----------------------------------------"
    
    # Check if there are any .js files to remove
    if ls "$TARGET_DIR"/*.js 1> /dev/null 2>&1; then
        # Count the files before removing
        FILE_COUNT=$(ls "$TARGET_DIR"/*.js 2>/dev/null | wc -l)
        
        # Remove all .js files
        rm "$TARGET_DIR"/*.js
        
        echo "Successfully removed $FILE_COUNT .js file(s) from $TARGET_DIR"
    else
        echo "No .js files found in $TARGET_DIR"
    fi
fi