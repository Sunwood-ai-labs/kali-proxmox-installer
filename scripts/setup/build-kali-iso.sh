#!/bin/bash
# =============================================================================
# Kali Linux ISO Builder with Preseed
# =============================================================================
# Downloads Kali Linux ISO and rebuilds it with preseed configuration
# for automated installation on Proxmox VE.
#
# Usage:
#   ./build-kali-iso.sh [kali_version]
#
# Arguments:
#   kali_version - Kali version to download (default: 2024.3)
#
# Requirements:
#   - xorriso
#   - wget or curl
#   - root privileges
#
# Output:
#   - kali-linux-<version>-preseed.iso in the current directory
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KALI_VERSION="${1:-2025.4}"
ISO_FILENAME="kali-linux-${KALI_VERSION}-installer-amd64.iso"

# Determine base URL based on version
# Current versions use cdimage.kali.org/kali-<version>/
# Older versions use old.kali.org/kali-images/kali-<version>/
VERSION_YEAR=$(echo "$KALI_VERSION" | cut -d. -f1)
if [ "$VERSION_YEAR" -ge 2025 ]; then
    ISO_URL="https://cdimage.kali.org/kali-${KALI_VERSION}/${ISO_FILENAME}"
else
    ISO_URL="https://old.kali.org/kali-images/kali-${KALI_VERSION}/${ISO_FILENAME}"
fi

PRESEED_FILE="../../templates/preseed.cfg"
WORK_DIR="./kali-iso-work"
OUTPUT_ISO="kali-linux-${KALI_VERSION}-preseed.iso"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0 $@"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    for cmd in xorriso wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: apt-get install ${missing_deps[*]}"
        exit 1
    fi

    log_success "All dependencies are installed"
}

# Download Kali ISO
download_iso() {
    log_info "Downloading Kali Linux ${KALI_VERSION} ISO..."

    if [ -f "$ISO_FILENAME" ]; then
        log_warning "ISO file already exists: $ISO_FILENAME"
        read -p "Do you want to re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Using existing ISO file"
            return
        fi
        rm -f "$ISO_FILENAME"
    fi

    wget --show-progress "$ISO_URL" || {
        log_error "Failed to download ISO"
        log_info "Please check the version and your internet connection"
        exit 1
    }

    log_success "ISO downloaded successfully"
}

# Extract ISO
extract_iso() {
    log_info "Extracting ISO to working directory..."

    # Clean up previous work directory
    if [ -d "$WORK_DIR" ]; then
        log_warning "Removing existing work directory"
        rm -rf "$WORK_DIR"
    fi

    mkdir -p "$WORK_DIR"

    # Extract ISO using xorriso
    xorriso -osirrox on -indev "$ISO_FILENAME" -extract / "$WORK_DIR" || {
        log_error "Failed to extract ISO"
        exit 1
    }

    # Make extracted files writable
    chmod -R u+w "$WORK_DIR"

    log_success "ISO extracted successfully"
}

# Add preseed configuration
add_preseed() {
    log_info "Adding preseed configuration..."

    if [ ! -f "$PRESEED_FILE" ]; then
        log_error "Preseed file not found: $PRESEED_FILE"
        exit 1
    fi

    # Create preseed directory structure
    mkdir -p "$WORK_DIR/preseed"

    # Copy preseed file
    cp "$PRESEED_FILE" "$WORK_DIR/preseed/kali.preseed" || {
        log_error "Failed to copy preseed file"
        exit 1
    }

    log_success "Preseed configuration added"

    # Modify boot menu to use preseed
    configure_boot_menu
}

# Configure boot menu
configure_boot_menu() {
    log_info "Configuring boot menu for automated installation..."

    local isolinux_cfg="$WORK_DIR/isolinux/isolinux.cfg"
    local grub_cfg="$WORK_DIR/boot/grub/grub.cfg"

    # Backup original files
    [ -f "$isolinux_cfg" ] && cp "$isolinux_cfg" "${isolinux_cfg}.bak"
    [ -f "$grub_cfg" ] && cp "$grub_cfg" "${grub_cfg}.bak"

    # Add preseed boot entry to isolinux.cfg
    if [ -f "$isolinux_cfg" ]; then
        # Modify default installation to use preseed
        sed -i 's|default install|default preseed|g' "$isolinux_cfg"
        sed -i 's|timeout 0|timeout 10|g' "$isolinux_cfg"

        # Add preseed entry at the beginning
        cat > "$WORK_DIR/isolinux/preseed.cfg" << 'EOF'
label preseed
  menu label ^Automated Install (Preseed)
  kernel /install.amd/vmlinuz
  append vga=788 initrd=/install.amd/initrd.gz auto=true priority=critical file=/cdrom/preseed/kali.preseed ---
EOF

        # Insert preseed entry into main config
        if ! grep -q "include preseed.cfg" "$isolinux_cfg"; then
            sed -i '/label install/i include preseed.cfg\n' "$isolinux_cfg"
        fi
    fi

    # Add preseed boot entry to grub.cfg
    if [ -f "$grub_cfg" ]; then
        # Set default to preseed
        sed -i 's|set default="0"|set default="preseed"|g' "$grub_cfg"
        sed -i 's|set timeout=0|set timeout=10|g' "$grub_cfg"

        # Add preseed menu entry
        if ! grep -q "preseed" "$grub_cfg"; then
            sed -i '/menuentry "Install"/i menuentry "Automated Install (Preseed)" --hotkey preseed {\n  linux /install.amd/vmlinuz auto=true priority=critical file=/cdrom/preseed/kali.preseed\n  initrd /install.amd/initrd.gz\n}\n' "$grub_cfg"
        fi
    fi

    log_success "Boot menu configured"
}

# Rebuild ISO
rebuild_iso() {
    log_info "Rebuilding ISO with preseed configuration..."

    # Remove existing output ISO
    [ -f "$OUTPUT_ISO" ] && rm -f "$OUTPUT_ISO"

    # Check if isohdpfx.bin exists (for hybrid boot)
    if [ -f "$WORK_DIR/isolinux/isohdpfx.bin" ]; then
        log_info "Building hybrid bootable ISO..."
        # Build ISO with hybrid boot support
        xorriso -as mkisofs \
            -r -V "Kali Linux Preseed" \
            -o "$OUTPUT_ISO" \
            -J -l -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -isohybrid-mbr "$WORK_DIR/isolinux/isohdpfx.bin" \
            -eltorito-boot \
            -isohybrid-apm-hfsplus \
            "$WORK_DIR" || {
            log_error "Failed to rebuild ISO"
            exit 1
        }
    else
        log_warning "isohdpfx.bin not found, building non-hybrid ISO..."
        # Build ISO without hybrid boot support
        xorriso -as mkisofs \
            -r -V "Kali Linux Preseed" \
            -o "$OUTPUT_ISO" \
            -J -l -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -eltorito-boot \
            "$WORK_DIR" || {
            log_error "Failed to rebuild ISO"
            exit 1
        }
        log_warning "ISO is bootable via BIOS/UEFI but not from USB (non-hybrid)"
    fi

    log_success "ISO rebuilt successfully: $OUTPUT_ISO"
}

# Clean up
cleanup() {
    log_info "Cleaning up work directory..."
    rm -rf "$WORK_DIR"
    log_success "Work directory removed"
}

# Calculate checksum
calculate_checksum() {
    log_info "Calculating SHA256 checksum..."
    sha256sum "$OUTPUT_ISO" > "${OUTPUT_ISO}.sha256"
    log_success "Checksum saved to ${OUTPUT_ISO}.sha256"
    cat "${OUTPUT_ISO}.sha256"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Kali Linux ISO Builder${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_root "$@"
    check_dependencies
    download_iso
    extract_iso
    add_preseed
    rebuild_iso

    # Ask about cleanup
    read -p "Remove work directory? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        cleanup
    fi

    calculate_checksum

    echo ""
    log_success "Done! Your preseeded ISO is ready: $OUTPUT_ISO"
    echo ""
    log_info "Usage with create-vm-from-iso.sh:"
    echo "  ./create-vm-from-iso.sh $OUTPUT_ISO"
}

# Run main function
main "$@"
