#!/bin/bash

# =============================================================================
# RAWJS & BASM INSTALLATION SCRIPT
# =============================================================================

# PROJECT INFO
RAWJS_NAME="rawjs-runtime"
RAWJS_DESCRIPTION="RawJS JavaScript Runtime Environment"
BASM_NAME="basm-tool"
BASM_DESCRIPTION="Universal Assembly/Bash/Binary Runner with fallback logic"

# INSTALLATION PATHS
INSTALL_DIR="/usr/local/etc/rawjs-runtime"
BIN_DIR="/usr/local/bin"

# SOURCE PATHS
REPO_DIR=$(pwd)
RAWJS_SOURCE_DIR="$REPO_DIR"  # Main level for Raw.sh
BASM_SOURCE_DIR="$REPO_DIR/._/basm"  # BASM in ._/basm

# LOGGING
LOG_FILE="/var/log/rawjs-install.log"
LOG_MODE=false
BACKUP_DIR="/usr/local/etc/rawjs-runtime_old_$(date +%s)"

# =============================================================================
# SYSTEM DETECTION AND PACKAGE INSTALLATION
# =============================================================================

# Detect system type (ash compatible)
detect_system() {
  if [ -f /etc/alpine-release ]; then
    echo "alpine"
  elif [ -f /etc/lsb-release ]; then
    # Check for Ubuntu specifically
    if grep -qi "ubuntu" /etc/lsb-release 2>/dev/null; then
      echo "ubuntu"
    else
      echo "unknown"
    fi
  elif [ -f /etc/os-release ]; then
    # More generic detection using os-release
    if grep -qi "alpine" /etc/os-release 2>/dev/null; then
      echo "alpine"
    elif grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
      echo "ubuntu"
    else
      echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

# =============================================================================
# ALPINE-SPECIFIC NASM BINARY REPLACEMENT (RUNS ONCE PER INSTALLATION SOURCE)
# =============================================================================

# This function handles the Alpine-specific NASM binary replacement
# It only runs if Alpine is detected and the source binary exists in alpine-pack
# After moving, the binary is no longer in alpine-pack, so it won't run again
handle_alpine_nasm_replacement() {
  local system_type="$1"
  
  # Only proceed if system is Alpine
  if [ "$system_type" != "alpine" ]; then
    return 0
  fi
  
  log_message "Alpine Linux detected - checking for Alpine-specific NASM binary..."
  
  # Define paths relative to the script execution directory (REPO_DIR)
  local alpine_pack_nasm="$REPO_DIR/._/basm/alpine-pack/nasm-x86_64-linux"
  local target_nasm_dir="$REPO_DIR/._/basm/x86_64-linux"
  local target_nasm="$target_nasm_dir/nasm-x86_64-linux"
  
  # Check if the Alpine-specific NASM binary exists in alpine-pack
  if [ ! -f "$alpine_pack_nasm" ]; then
    log_message "No Alpine-specific NASM binary found in alpine-pack (already processed or not present)"
    return 0
  fi
  
  log_message "Found Alpine-specific NASM binary in alpine-pack"
  
  # Create target directory if it doesn't exist
  if [ ! -d "$target_nasm_dir" ]; then
    mkdir -p "$target_nasm_dir"
    log_message "Created target directory: $target_nasm_dir"
  fi
  
  # Remove ANY existing NASM binary in target directory (both possible names)
  if [ -f "$target_nasm_dir/nasm-x86_64-linux" ]; then
    rm -f "$target_nasm_dir/nasm-x86_64-linux"
    log_message "Removed existing NASM binary: nasm-x86_64-linux"
  fi
  
  if [ -f "$target_nasm_dir/nasm-x86_64-linux-linux" ]; then
    rm -f "$target_nasm_dir/nasm-x86_64-linux-linux"
    log_message "Removed existing NASM binary: nasm-x86_64-linux-linux"
  fi
  
  # Also remove any other nasm binaries that might exist
  find "$target_nasm_dir" -maxdepth 1 -name "nasm*" -type f -exec rm -f {} \; 2>/dev/null
  log_message "Cleaned all existing NASM binaries from target directory"
  
  # Move the Alpine-specific NASM binary to the target location with CORRECT name
  mv "$alpine_pack_nasm" "$target_nasm"
  
  if [ $? -eq 0 ]; then
    log_message "✓ Moved Alpine-specific NASM binary to: $target_nasm"
    # Make it executable
    chmod +x "$target_nasm"
    log_message "✓ Set executable permissions on NASM binary"
  else
    log_message "⚠ Warning: Failed to move Alpine-specific NASM binary"
    return 1
  fi
  
  return 0
}

# Check if required commands are available
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install .deb packages - EXACT COPY from working EasyAI install.sh
install_debs() {
  local deb_dir="$BASM_SOURCE_DIR/ubuntu-pack"
  
  if [ -d "$deb_dir" ]; then
    deb_files=$(find "$deb_dir" -maxdepth 1 -name "*.deb" 2>/dev/null | tr '\n' ' ')
    if [ -n "$deb_files" ]; then
      log_message "Installing .deb packages from $deb_dir..."
      if [ "$LOG_MODE" = true ]; then
        sudo dpkg -i $deb_files &
      else
        sudo dpkg -i $deb_files > /dev/null 2>&1 &
      fi
      show_progress "Installing dependencies" $!
      
      # Run dpkg configure to fix any dependency issues
      log_message "Configuring packages..."
      if [ "$LOG_MODE" = true ]; then
        sudo dpkg --configure -a &
      else
        sudo dpkg --configure -a > /dev/null 2>&1 &
      fi
      show_progress "Configuring packages" $!
    else
      log_message "No .deb files found in $deb_dir. Skipping .deb installation."
    fi
  else
    log_message "The .deb directory ($deb_dir) does not exist. Skipping .deb installation."
  fi
}

# Function to install .apk packages - FIXED FOR ALPINE
install_apks() {
  local apk_dir="$BASM_SOURCE_DIR/alpine-pack"
  
  if [ ! -d "$apk_dir" ]; then
    log_message "The .apk directory ($apk_dir) does not exist. Skipping .apk installation."
    return 1
  fi
  
  # Check if apk command exists
  if ! check_command apk; then
    log_message "Error: apk package manager not found"
    return 1
  fi
  
  # Get list of APK files
  apk_files=$(find "$apk_dir" -maxdepth 1 -name "*.apk" 2>/dev/null)
  
  if [ -z "$apk_files" ]; then
    log_message "No .apk files found in $apk_dir. Skipping .apk installation."
    return 0
  fi
  
  log_message "Found APK packages, installing..."
  
  # First installation attempt - install all packages together
  log_message "Installing all APK packages..."
  
  # Build list of all APK files for bulk installation
  all_apks=""
  for apk_file in $apk_files; do
    all_apks="$all_apks $apk_file"
  done
  
  # Try to install all packages at once (this handles dependencies better)
  log_message "Attempting bulk installation of all packages..."
  if [ "$LOG_MODE" = true ]; then
    apk add --allow-untrusted $all_apks 2>&1
    bulk_result=$?
  else
    apk add --allow-untrusted $all_apks > /dev/null 2>&1
    bulk_result=$?
  fi
  
  if [ $bulk_result -eq 0 ]; then
    log_message "✓ All packages installed successfully in bulk"
  else
    log_message "Bulk installation had issues, trying individual installation..."
    
    # Individual installation attempt with retry logic
    first_attempt_failed=false
    
    for apk_file in $apk_files; do
      pkg_name=$(basename "$apk_file")
      log_message "Installing: $pkg_name"
      
      if [ "$LOG_MODE" = true ]; then
        if apk add --allow-untrusted "$apk_file" 2>&1; then
          log_message "✓ Successfully installed: $pkg_name"
        else
          log_message "✗ Failed to install: $pkg_name"
          first_attempt_failed=true
        fi
      else
        if apk add --allow-untrusted "$apk_file" > /dev/null 2>&1; then
          log_message "✓ Installed: $pkg_name"
        else
          log_message "✗ Failed: $pkg_name"
          first_attempt_failed=true
        fi
      fi
    done
    
    # Second pass for failed packages (this often resolves dependency issues)
    if [ "$first_attempt_failed" = true ]; then
      log_message "Retrying failed packages..."
      
      for apk_file in $apk_files; do
        pkg_name=$(basename "$apk_file")
        
        # Check if package is already installed
        pkg_base_name=$(echo "$pkg_name" | sed 's/-[0-9].*//')
        if apk info -e "$pkg_base_name" > /dev/null 2>&1; then
          log_message "Package $pkg_base_name already installed, skipping"
          continue
        fi
        
        log_message "Second attempt for: $pkg_name"
        
        if [ "$LOG_MODE" = true ]; then
          if apk add --allow-untrusted --force "$apk_file" 2>&1; then
            log_message "✓ Installed on second attempt: $pkg_name"
          else
            log_message "✗ Still failed: $pkg_name"
          fi
        else
          if apk add --allow-untrusted --force "$apk_file" > /dev/null 2>&1; then
            log_message "✓ Installed on second attempt: $pkg_name"
          else
            log_message "✗ Still failed: $pkg_name"
          fi
        fi
      done
    fi
  fi
  
  # Update APK cache
  log_message "Updating APK cache..."
  apk update > /dev/null 2>&1
  
  log_message "APK installation process completed."
  return 0
}

# Install Alpine packages if needed
install_alpine_packages() {
  log_message "Installing required Alpine packages..."
  
  # First try to install from local APK files
  install_apks
  
  # Then verify and install any missing packages from repositories
  if ! check_command ld; then
    log_message "Installing binutils from Alpine repository..."
    apk add --no-cache binutils 2>&1 || echo "Warning: Failed to install binutils" >&2
  fi
  
  if ! check_command bash; then
    log_message "Installing bash from Alpine repository..."
    apk add --no-cache bash 2>&1 || echo "Warning: Failed to install bash" >&2
  fi
  
  # Final verification
  if check_command ld; then
    log_message "✓ Linker (ld) is available"
  else
    log_message "⚠ Warning: Linker (ld) is not available"
  fi
  
  if check_command bash; then
    log_message "✓ Bash is available"
  else
    log_message "⚠ Warning: Bash is not available"
  fi
}

# Install Ubuntu packages if needed
install_ubuntu_packages() {
  # Check what's already installed
  local need_ld=false
  
  if ! check_command ld; then
    need_ld=true
  fi
  
  # If nothing needed, return
  if [ "$need_ld" = false ]; then
    log_message "All required Ubuntu packages already installed"
    return 0
  fi
  
  log_message "Installing required Ubuntu packages..."
  
  # Use the working DEB installation function
  install_debs
  
  # If still missing, try to install from repositories
  if [ "$need_ld" = true ] && ! check_command ld; then
    # Check if apt-get is available
    if check_command apt-get; then
      log_message "Installing binutils from Ubuntu repository..."
      apt-get update -qq 2>&1
      apt-get install -y binutils 2>&1 || echo "Warning: Failed to install binutils from repository" >&2
    fi
  fi
}

# Install system-specific packages (first-time installation only)
install_system_packages() {
  local system_type="$1"
  
  log_message "Detected system: $system_type"
  
  case "$system_type" in
    alpine)
      install_alpine_packages
      ;;
    ubuntu)
      install_ubuntu_packages
      ;;
    *)
      log_message "Unknown system type. Skipping automatic package installation."
      log_message "Please ensure 'ld' (linker) is installed manually."
      if ! check_command ld; then
        echo "Warning: 'ld' (linker) not found. BASM .asm compilation may not work." >&2
      fi
      ;;
  esac
  
  # Final verification
  if check_command ld; then
    log_message "✓ Linker (ld) is available"
  else
    log_message "⚠ Warning: Linker (ld) is not available"
  fi
  
  if check_command bash; then
    log_message "✓ Bash is available"
  else
    log_message "⚠ Warning: Bash is not available (required for BASM)"
  fi
}

# =============================================================================
# FUNCTION DEFINITIONS (ORIGINAL - PRESERVED WITH ASH COMPATIBILITY)
# =============================================================================

show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Install RawJS Runtime and BASM - JavaScript Runtime + Universal Runner"
  echo
  echo "Options:"
  echo "  -h, --help       Show this help"
  echo "  -log             Enable installation logging"
  echo
  echo "This will install:"
  echo "  • RawJS runtime to $INSTALL_DIR"
  echo "  • BASM tools to $INSTALL_DIR/._basm"
  echo "  • Global 'raw' command (RawJS JavaScript runtime)"
  echo "  • Global 'basm' command (Universal file runner)"
  echo
  echo "RAWJS COMMAND:"
  echo "  • Run from the caller's current directory"
  echo "  • Execute Raw.sh with provided arguments"
  echo "  • JavaScript runtime environment"
  echo
  echo "BASM COMMAND:"
  echo "  • Run from the caller's current directory"
  echo "  • Execute basm.sh with provided arguments"
  echo "  • Intelligently handle .asm, .sh, and binary files with fallback logic"
  echo
  echo "File type detection and fallback order (BASM):"
  echo "  1. .asm files → compile and run with NASM"
  echo "  2. .sh files → execute with bash/sh"
  echo "  3. Binary files → execute directly"
  echo "  4. Fallback: file.asm → file.sh → file"
  exit 0
}

log_message() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  if [ "$LOG_MODE" = true ]; then
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
  else
    echo "[$timestamp] $message"
  fi
}

# ASH-COMPATIBLE PROGRESS FUNCTION (without read -t)
show_progress() {
  local message="$1"
  local pid="$2"
  local spinner="|/-\\"
  local i=0
  
  # Just show a simple message that we're working
  echo "$message (in progress...)"
  
  # Wait for the process to complete
  wait $pid 2>/dev/null
  
  echo "$message completed."
}

# FIXED: Robust file copying that works without rsync
copy_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local description="$3"

  mkdir -p "$dest_dir"
  log_message "Copying $description files to $dest_dir..."

  # Use cp with proper options instead of rsync (more compatible)
  if [ "$LOG_MODE" = true ]; then
    # Verbose copy with progress indication
    (cd "$src_dir" && find . -type f \
      ! -path "./.git/*" \
      ! -name "build_output.asm" \
      ! -path "./dev/*" \
      | while read file; do
      dest_file="$dest_dir/$file"
      dest_folder=$(dirname "$dest_file")
      mkdir -p "$dest_folder"
      cp -v "$file" "$dest_file" 2>&1
    done) | tee -a "$LOG_FILE" &
    copy_pid=$!
  else
    # Silent copy
    (cd "$src_dir" && find . -type f \
      ! -path "./.git/*" \
      ! -name "build_output.asm" \
      ! -path "./dev/*" \
      | while read file; do
      dest_file="$dest_dir/$file"
      dest_folder=$(dirname "$dest_file")
      mkdir -p "$dest_folder"
      cp "$file" "$dest_file" 2>/dev/null
    done) &
    copy_pid=$!
  fi

  show_progress "Copying $description files" $copy_pid
  
  # Verify files were copied
  local src_count=$(cd "$src_dir" && find . -type f \
    ! -path "./.git/*" \
    ! -name "build_output.asm" \
    ! -path "./dev/*" \
    | wc -l)
  local dest_count=$(find "$dest_dir" -type f | wc -l)
  
  log_message "Copied $dest_count of $src_count files"
  
  if [ "$dest_count" -eq 0 ]; then
    log_message "ERROR: No files were copied!"
    return 1
  fi
  
  return 0
}

create_raw_wrapper() {
  local install_dir="$1"
  local wrapper_path="$install_dir/wrappers/raw"
  
  log_message "Creating RawJS wrapper..."
  
  mkdir -p "$(dirname "$wrapper_path")"
  
  # Create wrapper that runs from caller's directory with proper path handling
  cat > "$wrapper_path" << 'WRAPPER_EOF'
#!/bin/bash

# Get the caller's current working directory
CALLER_DIR="$(pwd)"
INSTALL_DIR="/usr/local/etc/rawjs-runtime"

# Process arguments to convert relative paths to absolute paths
# BUT preserve special flags (--tool, --test, --reset, --log) and their arguments
args=()
skip_next=false

for arg in "$@"; do
  if [ "$skip_next" = true ]; then
    # This argument is part of a special flag's value, pass through unchanged
    args+=("$arg")
    skip_next=false
    continue
  fi
  
  # Check if this is a special flag that shouldn't have its arguments path-converted
  case "$arg" in
    --tool|--test|--reset|--log)
      # Special flag - pass through unchanged
      args+=("$arg")
      # For --tool, the next argument is the command name - don't convert it
      if [ "$arg" = "--tool" ]; then
        skip_next=true
      fi
      ;;
    -*)
      # Other flags - pass through unchanged
      args+=("$arg")
      ;;
    *)
      # Not a flag - check if it's a file that exists in caller's directory
      if [ -f "$CALLER_DIR/$arg" ]; then
        # Convert to absolute path
        args+=("$CALLER_DIR/$arg")
      else
        # Pass through unchanged
        args+=("$arg")
      fi
      ;;
  esac
done

# Navigate to the caller's directory to maintain context
cd "$CALLER_DIR" || {
  echo "Error: Cannot navigate to directory: $CALLER_DIR" >&2
  exit 1
}

# Execute Raw.sh from the installation directory with processed arguments
exec bash "$INSTALL_DIR/Raw.sh" "${args[@]}"
WRAPPER_EOF
  
  chmod +x "$wrapper_path"
  
  # Create symlink in bin directory
  local dest_path="$BIN_DIR/raw"
  [ -L "$dest_path" ] && rm -f "$dest_path"
  ln -sf "$wrapper_path" "$dest_path"
  
  log_message "Created 'raw' command symlink"
}

create_basm_wrapper() {
  local install_dir="$1"
  local wrapper_path="$install_dir/wrappers/basm"
  
  log_message "Creating BASM wrapper..."
  
  mkdir -p "$(dirname "$wrapper_path")"
  
  # Create wrapper that runs from caller's directory
  cat > "$wrapper_path" << 'WRAPPER_EOF'
#!/bin/bash

# Get the caller's current working directory
CALLER_DIR="$(pwd)"
INSTALL_DIR="/usr/local/etc/rawjs-runtime"

# Navigate to the caller's directory to work with their files
cd "$CALLER_DIR" || {
  echo "Error: Cannot navigate to directory: $CALLER_DIR" >&2
  exit 1
}

# Execute basm.sh from the BASM installation subdirectory with all arguments
exec bash "$INSTALL_DIR/._basm/basm.sh" "$@"
WRAPPER_EOF
  
  chmod +x "$wrapper_path"
  
  # Create symlink in bin directory
  local dest_path="$BIN_DIR/basm"
  [ -L "$dest_path" ] && rm -f "$dest_path"
  ln -sf "$wrapper_path" "$dest_path"
  
  log_message "Created 'basm' command symlink"
}

verify_rawjs_structure() {
  local install_dir="$1"
  
  log_message "Verifying RawJS installation structure..."
  
  # Check essential files
  if [ -f "$install_dir/Raw.sh" ]; then
    echo "✓ Found required file: Raw.sh"
    chmod +x "$install_dir/Raw.sh" 2>/dev/null || true
  else
    echo "✗ Error: Missing required file: Raw.sh"
    return 1
  fi
  
  # Check for JavaScript files
  if [ -f "$install_dir/output.js" ]; then
    echo "✓ Found JavaScript file: output.js"
  else
    echo "  Note: JavaScript file not found: output.js"
  fi
  
  if [ -f "$install_dir/test.js" ]; then
    echo "✓ Found JavaScript file: test.js"
  else
    echo "  Note: JavaScript file not found: test.js"
  fi
  
  return 0
}

verify_basm_structure() {
  local install_dir="$1"
  
  log_message "Verifying BASM installation structure..."
  
  # Check essential files
  if [ -f "$install_dir/._basm/basm.sh" ]; then
    echo "✓ Found required file: basm.sh"
    chmod +x "$install_dir/._basm/basm.sh" 2>/dev/null || true
  else
    echo "✗ Error: Missing required file: basm.sh"
    return 1
  fi
  
  # Check architecture binaries (NASM binaries for .asm support)
  local has_any_arch=false
  
  if [ -d "$install_dir/._basm/arm-linux" ]; then
    echo "✓ Found NASM architecture: arm-linux"
    has_any_arch=true
    
    # Check for nasm binary
    if [ -f "$install_dir/._basm/arm-linux/nasm-arm-linux-linux" ]; then
      echo "  ✓ NASM binary found"
      chmod +x "$install_dir/._basm/arm-linux/nasm-arm-linux-linux" 2>/dev/null || true
    else
      echo "  ⚠ NASM binary not found (but directory exists)"
    fi
  else
    echo "  Note: NASM architecture directory not found: arm-linux"
  fi
  
  if [ -d "$install_dir/._basm/i386-linux" ]; then
    echo "✓ Found NASM architecture: i386-linux"
    has_any_arch=true
    
    if [ -f "$install_dir/._basm/i386-linux/nasm-i386-linux-linux" ]; then
      echo "  ✓ NASM binary found"
      chmod +x "$install_dir/._basm/i386-linux/nasm-i386-linux-linux" 2>/dev/null || true
    else
      echo "  ⚠ NASM binary not found (but directory exists)"
    fi
  else
    echo "  Note: NASM architecture directory not found: i386-linux"
  fi
  
  if [ -d "$install_dir/._basm/x86_64-linux" ]; then
    echo "✓ Found NASM architecture: x86_64-linux"
    has_any_arch=true
    
    if [ -f "$install_dir/._basm/x86_64-linux/nasm-x86_64-linux" ] || [ -f "$install_dir/._basm/x86_64-linux/nasm-x86_64-linux-linux" ]; then
      echo "  ✓ NASM binary found"
      # Make whatever NASM binary exists executable
      chmod +x "$install_dir/._basm/x86_64-linux/nasm"* 2>/dev/null || true
    else
      echo "  ⚠ NASM binary not found (but directory exists)"
    fi
  else
    echo "  Note: NASM architecture directory not found: x86_64-linux"
  fi
  
  if [ "$has_any_arch" = false ]; then
    echo "⚠ Warning: No NASM architecture directories found"
    echo "  .asm file compilation will not be available"
  fi
  
  # Check for ld (linker)
  if check_command ld; then
    echo "✓ System linker (ld) found"
  else
    echo "⚠ Warning: System linker (ld) not found"
    echo "  .asm file linking will fail"
  fi
  
  return 0
}

remove_installation() {
  log_message "Removing existing installation..."
  
  # Remove symlinks
  if [ -L "$BIN_DIR/raw" ]; then
    rm -f "$BIN_DIR/raw"
    log_message "Removed symlink: $BIN_DIR/raw"
  fi
  
  if [ -L "$BIN_DIR/basm" ]; then
    rm -f "$BIN_DIR/basm"
    log_message "Removed symlink: $BIN_DIR/basm"
  fi
  
  # Remove installation directory
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    log_message "Removed installation directory: $INSTALL_DIR"
  fi
}

cleanup() {
  # Remove backup directory if it exists
  if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR" 2>/dev/null || true
  fi
}

interrupt_handler() {
  log_message "Installation interrupted. Cleaning up..."
  cleanup
  exit 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

trap interrupt_handler INT TERM

# Parse command line arguments
# Check if a JavaScript file was provided as an argument
PROVIDED_JS_FILE=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help ;;
    -log) LOG_MODE=true; touch "$LOG_FILE" ;;
    *)
      # Check if this argument is a .js file (not a flag)
      if [[ "$arg" != -* ]] && [[ "$arg" == *.js ]]; then
        PROVIDED_JS_FILE="$arg"
      fi
      ;;
  esac
done

log_message "Starting RawJS and BASM installation..."

# =============================================================================
# ALPINE-SPECIFIC NASM BINARY REPLACEMENT (RUNS BEFORE ANYTHING ELSE)
# =============================================================================

# Detect system type early for Alpine-specific handling
SYSTEM_TYPE=$(detect_system)

# Handle Alpine-specific NASM binary replacement
# This only runs if Alpine is detected and the binary exists in alpine-pack
# After moving, the binary won't be there for future runs
handle_alpine_nasm_replacement "$SYSTEM_TYPE"

# =============================================================================
# CONTINUE WITH NORMAL INSTALLATION FLOW
# =============================================================================

# Check if Raw.sh exists at main level
if [ ! -f "$RAWJS_SOURCE_DIR/Raw.sh" ]; then
  echo "Error: Raw.sh not found at: $RAWJS_SOURCE_DIR/Raw.sh" >&2
  echo "Make sure you're running this script from the correct directory." >&2
  echo "Current directory: $REPO_DIR" >&2
  echo "Expected to find: Raw.sh" >&2
  echo "Files in current directory:" >&2
  ls -la "$REPO_DIR/" | grep -E "\.sh$" >&2 || echo "  (no .sh files found)" >&2
  exit 1
fi

# Check if BASM source directory exists
if [ ! -d "$BASM_SOURCE_DIR" ]; then
  echo "Warning: BASM directory not found at: $BASM_SOURCE_DIR" >&2
  echo "BASM will not be installed, but RawJS will continue." >&2
  INSTALL_BASM=false
else
  INSTALL_BASM=true
fi

# Detect if this is a first-time installation
IS_FIRST_INSTALL=false
if [ ! -d "$INSTALL_DIR" ]; then
  IS_FIRST_INSTALL=true
fi

# Handle existing installation
# If a JS file was provided, force update (option 1) automatically
if [ -d "$INSTALL_DIR" ]; then
  log_message "Existing installation found at: $INSTALL_DIR"
  
  if [ -n "$PROVIDED_JS_FILE" ]; then
    # JavaScript file provided - force update automatically
    log_message "JavaScript file provided - forcing update..."
    echo "JavaScript file detected: $PROVIDED_JS_FILE"
    echo "Automatically updating installation to run with provided file..."
    remove_installation
    log_message "Clean removal completed. Proceeding with fresh installation..."
    IS_FIRST_INSTALL=true
  else
    # No JavaScript file - show interactive menu
    echo "Choose an option:"
    echo "  1 = Update"
    echo "  2 = Remove"
    echo "  3 = Exit"
    printf "Enter your choice [1-3]: "
    read choice
    
    case "$choice" in
      1) 
        # Completely remove existing installation
        log_message "Removing existing installation for clean update..."
        remove_installation
        log_message "Clean removal completed. Proceeding with fresh installation..."
        IS_FIRST_INSTALL=true
        ;;
      2) 
        remove_installation
        echo "Uninstallation completed."
        exit 0
        ;;
      3) 
        echo "Exiting."
        exit 0
        ;;
      *) 
        echo "Invalid choice. Exiting."
        exit 1
        ;;
    esac
  fi
fi

# Install system packages on first-time installation
if [ "$IS_FIRST_INSTALL" = true ] && [ "$INSTALL_BASM" = true ]; then
  # Use the already detected SYSTEM_TYPE from earlier
  install_system_packages "$SYSTEM_TYPE"
fi

# Create installation directory
log_message "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy RawJS files from main directory
copy_files "$RAWJS_SOURCE_DIR" "$INSTALL_DIR" "RawJS"

# Verify RawJS installation structure
if ! verify_rawjs_structure "$INSTALL_DIR"; then
  echo "Error: RawJS installation verification failed"
  exit 1
fi

# Copy BASM files if they exist
if [ "$INSTALL_BASM" = true ]; then
  log_message "Installing BASM tools..."
  mkdir -p "$INSTALL_DIR/._basm"
  copy_files "$BASM_SOURCE_DIR" "$INSTALL_DIR/._basm" "BASM"
  
  # Verify BASM installation structure
  if ! verify_basm_structure "$INSTALL_DIR"; then
    echo "Warning: BASM installation verification failed"
    echo "BASM will not be fully functional"
  fi
else
  log_message "Skipping BASM installation (source not found)"
fi

# Create the raw command wrapper
create_raw_wrapper "$INSTALL_DIR"

# Create the basm command wrapper if BASM was installed
if [ "$INSTALL_BASM" = true ]; then
  create_basm_wrapper "$INSTALL_DIR"
fi

# Cleanup backup if it exists
cleanup

# =============================================================================
# FINAL STEP: INITIALIZE RAWJS ENVIRONMENT
# =============================================================================

log_message "Initializing RawJS environment..."
echo
echo "Running 'raw --reset' to build initial directory structure..."

# Execute raw --reset to initialize the environment
if [ -f "$BIN_DIR/raw" ] && [ -x "$BIN_DIR/raw" ]; then
    if raw --reset; then
        log_message "✓ RawJS environment initialized successfully"
        echo "✓ RawJS environment initialized successfully"
    else
        log_message "⚠ Warning: RawJS environment initialization had issues"
        echo "⚠ Warning: RawJS environment initialization had issues"
        echo "You can manually run: raw --reset"
    fi
else
    log_message "⚠ Warning: raw command not found or not executable"
    echo "⚠ Warning: Cannot run raw --reset - command not available"
    echo "You may need to run manually: raw --reset"
fi

echo

log_message "RawJS and BASM installation completed!"

# =============================================================================
# DISPLAY FINAL MESSAGE OR EXECUTE PROVIDED JAVASCRIPT FILE
# =============================================================================

# Check if a JavaScript file was provided
if [ -n "$PROVIDED_JS_FILE" ]; then
    # A JavaScript file was provided - execute it using the installed raw command
    echo "=========================================="
    echo "Executing provided JavaScript file: $PROVIDED_JS_FILE"
    echo "=========================================="
    echo
    
    # Run the raw command with the provided JavaScript file
    if [ -f "$BIN_DIR/raw" ] && [ -x "$BIN_DIR/raw" ]; then
        raw "$PROVIDED_JS_FILE"
        JS_EXIT_CODE=$?
        echo
        echo "=========================================="
        echo "JavaScript execution completed with exit code: $JS_EXIT_CODE"
        echo "=========================================="
        exit $JS_EXIT_CODE
    else
        echo "Error: raw command not found or not executable after installation" >&2
        exit 1
    fi
else
    # No JavaScript file provided - show the standard usage message
    # Display the same usage message that appears when running Raw.sh without arguments
    echo
    echo "=========================================="
    echo "RAWJS & BASM INSTALLATION SUCCESSFUL"
    echo "=========================================="
    echo
    echo "Usage: bash Raw.sh [--log] <path/to/file.js> [args...]"
    echo "       bash Raw.sh --reset"
    echo "       bash Raw.sh --test"
    echo "       bash Raw.sh --tool [command] [args...]"
    echo "       bash Raw.sh --<tool> [args...]"
    echo "       bash Raw.sh --tools"
    echo "       bash Raw.sh --version"
    echo "       bash Raw.sh --asm [path/to/file.js] [args...]"
    echo
    if [ "$INSTALL_BASM" = true ]; then
        echo "Available commands:"
        echo "  raw              RawJS JavaScript Runtime"
        echo "  basm             BASM Universal Runner (.asm, .sh, binary files)"
        echo
    fi
    echo "Installation directory: $INSTALL_DIR"
    echo "Command symlinks:"
    echo "  • $BIN_DIR/raw (RawJS JavaScript Runtime)"
    if [ "$INSTALL_BASM" = true ]; then
        echo "  • $BIN_DIR/basm (BASM Universal Runner)"
    fi
    echo
    echo "To uninstall, run this script again and choose option 2."
    echo "=========================================="
fi