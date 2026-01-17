#!/bin/bash
# =============================================================================
# Kali Linux VM Creator for Proxmox VE
# =============================================================================
# Creates a VM on Proxmox VE using the preseeded Kali Linux ISO.
# Supports environment variables for customization.
#
# Usage:
#   ./create-vm-from-iso.sh [options]
#
# Options:
#   -i, --iso <path>        Path to preseeded ISO (required)
#   -n, --name <name>       VM name (default: kali-linux)
#   -id, --vmid <id>        VM ID (default: auto)
#   -c, --cores <num>       CPU cores (default: 2)
#   -m, --memory <size>     Memory in MB (default: 4096)
#   -d, --disk <size>       Disk size (default: 50G)
#   -s, --storage <name>    Storage name (default: local-lvm)
#   --user <username>       Username for preseed (default: kali)
#   --password <password>   User password (default: empty)
#   --hostname <name>       Hostname (default: kali)
#
# Environment Variables:
#   PROXMOX_HOST            Proxmox host (default: localhost)
#   PROXMOX_USER            Proxmox user (default: root)
#
# Example:
#   ./create-vm-from-iso.sh -i kali-linux-2024.3-preseed.iso --user maki
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
VM_NAME="kali-linux"
VM_ID=""
VM_CORES=2
VM_MEMORY=4096
DISK_SIZE="50G"
STORAGE="local-lvm"
BRIDGE="vmbr0"
ISO_PATH=""
KALI_USER="kali"
KALI_PASSWORD=""
KALI_HOSTNAME="kali"
KALI_DOMAIN="localdomain"
PROXMOX_HOST="${PROXMOX_HOST:-localhost}"
PROXMOX_USER="${PROXMOX_USER:-root}"

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

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -i, --iso <path>         Path to preseeded ISO (required)
  -n, --name <name>        VM name (default: kali-linux)
  -id, --vmid <id>         VM ID (default: auto)
  -c, --cores <num>        CPU cores (default: 2)
  -m, --memory <size>      Memory in MB (default: 4096)
  -d, --disk <size>        Disk size (default: 50G)
  -s, --storage <name>     Storage name (default: local-lvm)
  --user <username>        Username for preseed (default: kali)
  --password <password>    User password (default: empty)
  --hostname <name>        Hostname (default: kali)
  -h, --help               Show this help

Environment Variables:
  PROXMOX_HOST             Proxmox host (default: localhost)
  PROXMOX_USER             Proxmox user (default: root)

Example:
  $0 -i kali-linux-2024.3-preseed.iso --user maki
EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--iso)
                ISO_PATH="$2"
                shift 2
                ;;
            -n|--name)
                VM_NAME="$2"
                shift 2
                ;;
            -id|--vmid)
                VM_ID="$2"
                shift 2
                ;;
            -c|--cores)
                VM_CORES="$2"
                shift 2
                ;;
            -m|--memory)
                VM_MEMORY="$2"
                shift 2
                ;;
            -d|--disk)
                DISK_SIZE="$2"
                shift 2
                ;;
            -s|--storage)
                STORAGE="$2"
                shift 2
                ;;
            --user)
                KALI_USER="$2"
                shift 2
                ;;
            --password)
                KALI_PASSWORD="$2"
                shift 2
                ;;
            --hostname)
                KALI_HOSTNAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$ISO_PATH" ]; then
        log_error "ISO path is required. Use -i or --iso"
        show_usage
    fi

    if [ ! -f "$ISO_PATH" ]; then
        log_error "ISO file not found: $ISO_PATH"
        exit 1
    fi
}

# Check if running on Proxmox or need remote connection
check_proxmox() {
    log_info "Checking Proxmox connection..."

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        if ! command -v qm &> /dev/null; then
            log_error "qm command not found. Are you on a Proxmox host?"
            exit 1
        fi
        log_success "Running on local Proxmox host"
    else
        log_info "Will connect to remote Proxmox host: $PROXMOX_HOST"
        if ! command -v ssh &> /dev/null; then
            log_error "ssh command not found"
            exit 1
        fi
    fi
}

# Get next available VM ID
get_next_vmid() {
    if [ -z "$VM_ID" ]; then
        log_info "Getting next available VM ID..."
        if [ "$PROXMOX_HOST" = "localhost" ]; then
            VM_ID=$(qm list | awk 'NR>2 && $1 !~ /VMID/ {print $1}' | sort -n | tail -1)
            VM_ID=$((VM_ID + 1))
        else
            VM_ID=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "qm list | awk 'NR>2 && \$1 !~ /VMID/ {print \$1}' | sort -n | tail -1")
            VM_ID=$((VM_ID + 1))
        fi
        log_success "Using VM ID: $VM_ID"
    fi
}

# Check if VM already exists
check_vm_exists() {
    log_info "Checking if VM $VM_ID already exists..."

    local exists
    if [ "$PROXMOX_HOST" = "localhost" ]; then
        exists=$(qm config "$VM_ID" &> /dev/null && echo "yes" || echo "no")
    else
        exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "qm config $VM_ID &> /dev/null && echo 'yes' || echo 'no'")
    fi

    if [ "$exists" = "yes" ]; then
        log_error "VM $VM_ID already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Deleting existing VM $VM_ID..."
            if [ "$PROXMOX_HOST" = "localhost" ]; then
                qm destroy "$VM_ID" --destroy-unreferenced-disks 1
            else
                ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "qm destroy $VM_ID --destroy-unreferenced-disks 1"
            fi
            log_success "VM deleted"
        else
            log_info "Aborting..."
            exit 0
        fi
    fi
}

# Upload ISO to Proxmox storage if remote
upload_iso() {
    if [ "$PROXMOX_HOST" != "localhost" ]; then
        log_info "Uploading ISO to remote Proxmox host..."

        local iso_name=$(basename "$ISO_PATH")
        local remote_path="/tmp/$iso_name"

        scp "$ISO_PATH" "${PROXMOX_USER}@${PROXMOX_HOST}:${remote_path}"
        ISO_PATH="$remote_path"
        log_success "ISO uploaded"
    fi
}

# Calculate password hash for preseed
calculate_password_hash() {
    if [ -n "$KALI_PASSWORD" ]; then
        # Generate SHA-512 hash (this is a simplified approach)
        # In production, you should use openssl passwd -6
        KALI_PASSWORD_HASH=$(openssl passwd -6 "$KALI_PASSWORD")
    fi
}

# Create VM
create_vm() {
    log_info "Creating VM $VM_ID: $VM_NAME..."

    local qm_cmd="qm create $VM_ID \\
        --name $VM_NAME \\
        --cores $VM_CORES \\
        --memory $VM_MEMORY \\
        --net0 virtio,bridge=$BRIDGE \\
        --serial0 socket \\
        --vga serial0 \\
        --ostype l26 \\
        --scsihw virtio-scsi-pci \\
        --agent enabled=1"

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        eval "$qm_cmd"
    else
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "$qm_cmd"
    fi

    log_success "VM created"
}

# Attach disk
attach_disk() {
    log_info "Attaching disk..."

    local disk_cmd="qm set $VM_ID \\
        --scsi0 $STORAGE:${DISK_SIZE},ssd=1"

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        eval "$disk_cmd"
    else
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "$disk_cmd"
    fi

    log_success "Disk attached"
}

# Attach CD-ROM with ISO
attach_cdrom() {
    log_info "Attaching CD-ROM with ISO..."

    # Import ISO if it's not in Proxmox storage
    local iso_name=$(basename "$ISO_PATH")

    local cdrom_cmd="qm set $VM_ID --cdrom local:iso/$iso_name"

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        # Check if ISO exists in storage
        if [ ! -f "/var/lib/vz/template/iso/$iso_name" ]; then
            log_warning "ISO not found in Proxmox storage, copying..."
            cp "$ISO_PATH" "/var/lib/vz/template/iso/$iso_name"
        fi
        eval "$cdrom_cmd"
    else
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "
            if [ ! -f /var/lib/vz/template/iso/$iso_name ]; then
                echo 'Copying ISO to storage...'
                cp $ISO_PATH /var/lib/vz/template/iso/$iso_name
            fi
            $cdrom_cmd
        "
    fi

    log_success "CD-ROM attached"
}

# Set boot order
set_boot_order() {
    log_info "Setting boot order..."

    local boot_cmd="qm set $VM_ID --boot order=ide2"

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        eval "$boot_cmd"
    else
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "$boot_cmd"
    fi

    log_success "Boot order set"
}

# Start VM
start_vm() {
    log_info "Starting VM $VM_ID..."

    local start_cmd="qm start $VM_ID"

    if [ "$PROXMOX_HOST" = "localhost" ]; then
        eval "$start_cmd"
    else
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "$start_cmd"
    fi

    log_success "VM started"
}

# Show VM info
show_vm_info() {
    echo ""
    log_success "VM created successfully!"
    echo ""
    echo "VM Information:"
    echo "  ID:        $VM_ID"
    echo "  Name:      $VM_NAME"
    echo "  Hostname:  $KALI_HOSTNAME"
    echo "  User:      $KALI_USER"
    echo "  CPU:       $VM_CORES cores"
    echo "  Memory:    $VM_MEMORY MB"
    echo "  Disk:      $DISK_SIZE"
    echo "  Storage:   $STORAGE"
    echo ""
    log_info "Monitor installation with:"
    if [ "$PROXMOX_HOST" = "localhost" ]; then
        echo "  qm terminal $VM_ID"
    else
        echo "  ssh ${PROXMOX_USER}@${PROXMOX_HOST} 'qm terminal $VM_ID'"
    fi
    echo ""
    log_info "Or use the Proxmox web UI:"
    echo "  https://${PROXMOX_HOST}:8006/"
    echo ""
    log_warning "Installation will take 10-15 minutes."
    log_info "After installation, you can connect with:"
    echo "  ssh ${KALI_USER}@<vm-ip-address>"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Kali Linux VM Creator${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    parse_args "$@"
    check_proxmox
    get_next_vmid
    check_vm_exists
    upload_iso
    calculate_password_hash
    create_vm
    attach_disk
    attach_cdrom
    set_boot_order
    start_vm
    show_vm_info
}

# Run main function
main "$@"
