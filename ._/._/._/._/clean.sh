#!/bin/bash

# Function to check if a file/directory is ignored by git
is_git_ignored() {
    local path="$1"
    git check-ignore -q "$path" 2>/dev/null
    return $?
}

# Function to clean gitignored files in a single directory (non-recursive)
clean_single() {
    local dir="$1"
    local file_count=0
    
    echo "  Cleaning $dir"
    
    # Process all files in the current directory
    while IFS= read -r -d '' file; do
        # Skip if it's the .git directory
        if [[ "$file" == *"/.git/"* ]] || [[ "$file" == *"/.git" ]]; then
            continue
        fi
        
        # Check if file is gitignored (only remove if it IS ignored)
        if is_git_ignored "$file"; then
            rm "$file"
            file_count=$((file_count + 1))
            echo "    Removed gitignored file: $(basename "$file")"
        fi
    done < <(find "$dir" -maxdepth 1 -type f -print0)
    
    return $file_count
}

# Function to clean gitignored files recursively
clean_recursive() {
    local dir="$1"
    local total_count=0
    local current_count=0
    
    # Clean current directory
    clean_single "$dir"
    current_count=$?
    total_count=$((total_count + current_count))
    
    # Recursively process subdirectories
    while IFS= read -r -d '' subdir; do
        # Skip .git directory but include ._ directory
        if [[ "$subdir" == *"/.git"* ]]; then
            continue
        fi
        
        # Process only if directory is NOT gitignored (otherwise skip entire directory)
        if is_git_ignored "$subdir"; then
            echo "  Skipping gitignored directory: $subdir"
            continue
        fi
        
        clean_recursive "$subdir"
        current_count=$?
        total_count=$((total_count + current_count))
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -name ".git" -print0)
    
    return $total_count
}

# Get the directory where the script is being called from
TARGET_DIR="$(pwd)"
TOTAL_FILES=0

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Check for --full argument
if [[ "$1" == "--full" ]]; then
    echo "Cleaning gitignored files recursively from $TARGET_DIR"
    echo "-----------------------------------------------------"
    clean_recursive "$TARGET_DIR"
    TOTAL_FILES=$?
    echo "-----------------------------------------------------"
    echo "Successfully removed $TOTAL_FILES gitignored file(s) recursively from $TARGET_DIR"
else
    echo "Cleaning gitignored files from $TARGET_DIR (non-recursive)"
    echo "----------------------------------------------------------"
    clean_single "$TARGET_DIR"
    TOTAL_FILES=$?
    echo "----------------------------------------------------------"
    if [ $TOTAL_FILES -eq 0 ]; then
        echo "No gitignored files found in $TARGET_DIR"
    else
        echo "Successfully removed $TOTAL_FILES gitignored file(s) from $TARGET_DIR"
    fi
fi