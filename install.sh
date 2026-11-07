#!/usr/bin/env bash
# ==============================================================================
# ForceQuit GNOME Shell Extension Installer & Manager
# Universal, cross-distribution installer for GNOME Shell (45+)
# ==============================================================================

# Ensure script runs with bash even if invoked with 'sh install.sh'
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi

set -euo pipefail

# ------------------------------------------------------------------------------
# Terminal formatting & colors (respects NO_COLOR standard)
# ------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
fi

log_step() {
    printf "${C_BLUE}${C_BOLD}[➜]${C_RESET} %s\n" "$*"
}

log_success() {
    printf "${C_GREEN}${C_BOLD}[✓]${C_RESET} %s\n" "$*"
}

log_warn() {
    printf "${C_YELLOW}${C_BOLD}[!]${C_RESET} %s\n" "$*"
}

log_error() {
    printf "${C_RED}${C_BOLD}[✗]${C_RESET} %s\n" "$*" >&2
}

log_info() {
    printf "${C_CYAN}[i]${C_RESET} %s\n" "$*"
}

# ------------------------------------------------------------------------------
# Resolve source directory (handles symlinks universally)
# ------------------------------------------------------------------------------
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
METADATA_FILE="$SCRIPT_DIR/metadata.json"

# ------------------------------------------------------------------------------
# Read metadata dynamically (No hardcoded paths or UUIDs)
# ------------------------------------------------------------------------------
if [ ! -f "$METADATA_FILE" ]; then
    log_error "metadata.json not found in $SCRIPT_DIR!"
    log_error "Please run this script from the ForceQuit repository root."
    exit 1
fi

get_json_value() {
    local key="$1"
    local file="$2"
    sed -n -E 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"?([^",]+)"?.*/\1/p' "$file" | head -n 1
}

UUID="$(get_json_value "uuid" "$METADATA_FILE")"
NAME="$(get_json_value "name" "$METADATA_FILE")"
VERSION="$(get_json_value "version" "$METADATA_FILE")"

if [ -z "$UUID" ]; then
    log_error "Unable to extract extension UUID from $METADATA_FILE."
    exit 1
fi

NAME="${NAME:-ForceQuit}"
VERSION="${VERSION:-unknown}"

# ------------------------------------------------------------------------------
# Defaults & Options
# ------------------------------------------------------------------------------
SYSTEM_MODE=false
UNINSTALL_MODE=false
AUTO_ENABLE=true
DRY_RUN=false

show_help() {
    cat <<EOF
${C_BOLD}${NAME} GNOME Shell Extension Installer${C_RESET}
Universal installer and manager for ${NAME} (${UUID})

${C_BOLD}USAGE:${C_RESET}
    ./install.sh [OPTIONS]

${C_BOLD}OPTIONS:${C_RESET}
    ${C_GREEN}-u, --uninstall${C_RESET}       Uninstall ${NAME} from the system
    ${C_GREEN}-s, --system${C_RESET}          Install system-wide for all users (/usr/share/gnome-shell/extensions)
                            (Requires root/sudo privileges)
    ${C_GREEN}--no-enable${C_RESET}            Copy files without attempting to run 'gnome-extensions enable'
    ${C_GREEN}-n, --dry-run${C_RESET}          Simulate the installation without writing any files
    ${C_GREEN}-h, --help${C_RESET}             Show this help screen and exit

${C_BOLD}EXAMPLES:${C_RESET}
    ./install.sh                    # Standard user installation (recommended)
    ./install.sh --uninstall        # Remove the extension
    sudo ./install.sh --system      # Install system-wide for all users
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--uninstall)
            UNINSTALL_MODE=true
            shift
            ;;
        -s|--system)
            SYSTEM_MODE=true
            shift
            ;;
        --no-enable)
            AUTO_ENABLE=false
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run './install.sh --help' for available options."
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Determine Target Installation Directory
# ------------------------------------------------------------------------------
if [ "$SYSTEM_MODE" = true ]; then
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        log_error "System-wide installation requires root/sudo privileges."
        log_info "Try: sudo ./install.sh --system"
        exit 1
    fi
    TARGET_DIR="/usr/share/gnome-shell/extensions/$UUID"
else
    # Detect if user accidentally executed with sudo for a local user install
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
            log_warn "Running with sudo: installing for user '${SUDO_USER}' rather than root."
            log_info "(Use --system if you intended a global system-wide install)"
            TARGET_DIR="$USER_HOME/.local/share/gnome-shell/extensions/$UUID"
        else
            TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
        fi
    else
        TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
    fi
fi

# ------------------------------------------------------------------------------
# Target Directory Safety Validation (Fail-safe against accidental root deletion)
# ------------------------------------------------------------------------------
validate_target_dir() {
    local dir="$1"

    # 1. Reject empty or whitespace-only directory
    if [ -z "${dir:-}" ] || [ -z "${dir// }" ]; then
        log_error "CRITICAL SAFETY CHECK: Target directory is empty or unset!"
        exit 1
    fi

    # 2. Reject root or top-level patterns
    if [ "$dir" = "/" ] || [ "$dir" = "/*" ]; then
        log_error "CRITICAL SAFETY CHECK: Refusing to operate on '/'! Aborting."
        exit 1
    fi

    # 3. Resolve canonical path if possible
    local canonical_dir
    canonical_dir="$(realpath -m "$dir" 2>/dev/null || readlink -f "$dir" 2>/dev/null || echo "$dir")"

    if [ "$canonical_dir" = "/" ]; then
        log_error "CRITICAL SAFETY CHECK: Target directory resolves to root ('/')! Aborting."
        exit 1
    fi

    # 4. Critical system paths blacklist
    case "$canonical_dir" in
        ""|"/"|"/bin"|"/boot"|"/dev"|"/etc"|"/home"|"/lib"|"/lib64"|"/media"|"/mnt"|"/opt"|"/proc"|"/root"|"/run"|"/sbin"|"/srv"|"/sys"|"/tmp"|"/usr"|"/usr/share"|"/var")
            log_error "CRITICAL SAFETY CHECK: Target directory is a critical system path: $canonical_dir"
            exit 1
            ;;
    esac

    # 5. Strict structure check: Must contain gnome-shell/extensions and end with the extension UUID
    if [ -z "${UUID:-}" ] || [[ "$canonical_dir" != */gnome-shell/extensions/"$UUID" ]]; then
        log_error "CRITICAL SAFETY CHECK: Target directory must end with 'gnome-shell/extensions/${UUID:-<empty>}'!"
        log_error "Attempted path: $canonical_dir"
        exit 1
    fi
}

# Fail-safe removal helper
safe_remove_target_dir() {
    validate_target_dir "$TARGET_DIR"

    if [ -d "$TARGET_DIR" ]; then
        if [ "$DRY_RUN" = false ]; then
            # Protect against cross-device deletion using --one-file-system and --preserve-root
            rm -rf --preserve-root --one-file-system "$TARGET_DIR" 2>/dev/null || rm -rf --preserve-root "$TARGET_DIR"
        else
            echo "  [dry-run] rm -rf $TARGET_DIR"
        fi
    fi
}

# Run validation immediately upon determining target directory
validate_target_dir "$TARGET_DIR"

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
printf "\n${C_BOLD}${C_MAGENTA}====================================================${C_RESET}\n"
printf "  ${C_BOLD}${NAME} GNOME Shell Extension${C_RESET} ${C_DIM}(v%s)${C_RESET}\n" "$VERSION"
printf "  ${C_DIM}UUID:${C_RESET} %s\n" "$UUID"
printf "${C_BOLD}${C_MAGENTA}====================================================${C_RESET}\n\n"

# ------------------------------------------------------------------------------
# Uninstall Routine
# ------------------------------------------------------------------------------
if [ "$UNINSTALL_MODE" = true ]; then
    log_step "Uninstalling ${NAME}..."

    if command -v gnome-extensions >/dev/null 2>&1; then
        log_info "Disabling extension via gnome-extensions CLI..."
        if [ "$DRY_RUN" = false ]; then
            gnome-extensions disable "$UUID" 2>/dev/null || true
        else
            echo "  [dry-run] gnome-extensions disable $UUID"
        fi
    fi

    if [ -d "$TARGET_DIR" ]; then
        log_info "Removing directory: $TARGET_DIR"
        safe_remove_target_dir
        log_success "${NAME} successfully uninstalled."
    else
        log_warn "Extension directory not found at $TARGET_DIR. Nothing to remove."
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# Pre-flight Checks: Dependencies & GNOME Shell
# ------------------------------------------------------------------------------
log_step "Checking system environment and dependencies..."

# 1. glib-compile-schemas
if ! command -v glib-compile-schemas >/dev/null 2>&1; then
    log_error "Dependency 'glib-compile-schemas' not found!"
    echo ""
    echo "To compile GSettings schemas, install the GLib development package for your distribution:"
    echo "  - Debian / Ubuntu / Mint:  sudo apt install libglib2.0-bin"
    echo "  - Fedora / RHEL / CentOS:  sudo dnf install glib2-devel"
    echo "  - Arch Linux / Manjaro:    sudo pacman -S glib2"
    echo "  - openSUSE:                sudo zypper install glib2-tools"
    echo "  - Alpine Linux:            sudo apk add glib-dev"
    echo ""
    exit 1
else
    log_success "Found glib-compile-schemas"
fi

# 2. GNOME Shell check & version detection
GNOME_VERSION=""
if command -v gnome-shell >/dev/null 2>&1; then
    GNOME_VERSION="$(gnome-shell --version 2>/dev/null | awk '{print $3}' || true)"
    if [ -n "$GNOME_VERSION" ]; then
        log_success "Detected GNOME Shell version: ${C_BOLD}${GNOME_VERSION}${C_RESET}"

        # Check version compatibility against metadata.json
        GNOME_MAJOR="${GNOME_VERSION%%.*}"
        if ! grep -q "\"$GNOME_MAJOR\"" "$METADATA_FILE" 2>/dev/null; then
            log_warn "GNOME Shell $GNOME_MAJOR may not be explicitly listed in metadata.json shell-version."
            log_warn "If needed, add \"$GNOME_MAJOR\" to the 'shell-version' array in metadata.json."
        fi
    fi
else
    log_warn "gnome-shell command not detected in PATH. (Are you on GNOME?)"
fi

# 3. Session detection (Wayland vs X11)
SESSION_TYPE="${XDG_SESSION_TYPE:-}"
if [ -z "$SESSION_TYPE" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        SESSION_TYPE="wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        SESSION_TYPE="x11"
    else
        SESSION_TYPE="unknown"
    fi
fi
log_info "Display session type: ${C_BOLD}${SESSION_TYPE}${C_RESET}"

# ------------------------------------------------------------------------------
# Installation Steps
# ------------------------------------------------------------------------------
log_step "Target installation path: ${C_BOLD}${TARGET_DIR}${C_RESET}"

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE: No files will be modified."
fi

# Clean prior version to avoid orphaned files
if [ -d "$TARGET_DIR" ]; then
    log_info "Updating existing installation..."
    safe_remove_target_dir
fi

# Create target directory
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$TARGET_DIR"
fi

# Copy core extension files
log_step "Copying extension files..."
FILES_TO_COPY=(
    "metadata.json"
    "extension.js"
    "prefs.js"
    "stylesheet.css"
    "icon.png"
    "icon.svg"
)

for file in "${FILES_TO_COPY[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        if [ "$DRY_RUN" = false ]; then
            cp -f "$SCRIPT_DIR/$file" "$TARGET_DIR/"
        fi
        log_info "  Copied $file"
    fi
done

# Copy icons folder if present
if [ -d "$SCRIPT_DIR/icons" ]; then
    if [ "$DRY_RUN" = false ]; then
        cp -r "$SCRIPT_DIR/icons" "$TARGET_DIR/"
    fi
    log_info "  Copied icons/"
fi

# Copy schemas & compile
if [ -d "$SCRIPT_DIR/schemas" ]; then
    log_step "Compiling GSettings schemas..."
    if [ "$DRY_RUN" = false ]; then
        cp -r "$SCRIPT_DIR/schemas" "$TARGET_DIR/"
        glib-compile-schemas "$TARGET_DIR/schemas"
        # Also keep source schemas compiled for development convenience
        glib-compile-schemas "$SCRIPT_DIR/schemas" 2>/dev/null || true
    fi
    log_success "Compiled schemas into $TARGET_DIR/schemas/gschemas.compiled"
fi

log_success "All extension files successfully installed to $TARGET_DIR"

# ------------------------------------------------------------------------------
# Enable Extension via gnome-extensions CLI
# ------------------------------------------------------------------------------
if [ "$AUTO_ENABLE" = true ] && [ "$DRY_RUN" = false ]; then
    if command -v gnome-extensions >/dev/null 2>&1; then
        log_step "Attempting to enable extension..."
        # If GNOME Shell hasn't reloaded yet, enable might return non-zero until next reload
        if gnome-extensions enable "$UUID" 2>/dev/null; then
            log_success "Extension enabled in GNOME Shell!"
        else
            log_info "Registered activation request. (GNOME Shell reload required to apply)"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Session Reload & Next Steps Instructions
# ------------------------------------------------------------------------------
printf "\n${C_BOLD}${C_GREEN}====================================================${C_RESET}\n"
printf "  ${C_BOLD}${C_GREEN}Installation Complete!${C_RESET}\n"
printf "${C_BOLD}${C_GREEN}====================================================${C_RESET}\n\n"

echo "${C_BOLD}How to activate ${NAME}:${C_RESET}"
echo "GNOME Shell scans extension directories when starting. For newly added extensions,"
echo "a quick shell reload is required before GNOME Shell recognizes the new files:"
echo ""

if [ "$SESSION_TYPE" = "wayland" ]; then
    echo "  ${C_BOLD}${C_CYAN}Wayland Session Detected:${C_RESET}"
    echo "  1. Please ${C_BOLD}Log Out${C_RESET} and ${C_BOLD}Log Back In${C_RESET} (or restart your machine)."
    echo "     (Wayland architecture prevents in-place GNOME Shell restarts)"
    echo "  2. Once logged back in, ${NAME} will be active automatically!"
elif [ "$SESSION_TYPE" = "x11" ]; then
    echo "  ${C_BOLD}${C_CYAN}X11 Session Detected:${C_RESET}"
    echo "  1. Press ${C_BOLD}Alt + F2${C_RESET}"
    echo "  2. Type ${C_BOLD}r${C_RESET} and press ${C_BOLD}Enter${C_RESET} to reload GNOME Shell instantly without logging out."
    echo "  3. ${NAME} will be active immediately!"
else
    echo "  - ${C_BOLD}On Wayland:${C_RESET} Log out and log back in."
    echo "  - ${C_BOLD}On X11:${C_RESET}     Press Alt+F2, type 'r', and press Enter."
fi

echo ""
echo "${C_BOLD}Helpful Commands:${C_RESET}"
echo "  - Check status:     ${C_CYAN}gnome-extensions info ${UUID}${C_RESET}"
echo "  - Open preferences: ${C_CYAN}gnome-extensions prefs ${UUID}${C_RESET}"
echo "  - Uninstall:        ${C_CYAN}./install.sh --uninstall${C_RESET}"
echo ""
