#!/bin/bash

# Get the directory where the script is being called from
TARGET_DIR="$(pwd)"

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