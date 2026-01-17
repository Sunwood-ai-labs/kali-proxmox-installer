#!/bin/bash
# =============================================================================
# Proxmox SSH Configuration Script
# =============================================================================
# Configures SSH access to Proxmox VE for remote management.
# Sets up SSH keys and config for passwordless authentication.
#
# Usage:
#   ./setup-proxmox-ssh.sh [options]
#
# Options:
#   -h, --host <host>      Proxmox host (default: 192.168.0.147)
#   -u, --user <user>      Proxmox user (default: root)
#   -p, --port <port>      SSH port (default: 22)
#   -k, --key <path>       SSH key path (default: ~/.ssh/id_rsa)
#   --setup-keys           Generate and setup new SSH keys
#   --test                 Test SSH connection
#
# Example:
#   ./setup-proxmox-ssh.sh --host 192.168.0.147 --setup-keys
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.147}"
PROXMOX_USER="${PROXMOX_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
SSH_CONFIG="$HOME/.ssh/config"
SETUP_KEYS=false
TEST_CONNECTION=false

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
  -h, --host <host>       Proxmox host (default: 192.168.0.147)
  -u, --user <user>       Proxmox user (default: root)
  -p, --port <port>       SSH port (default: 22)
  -k, --key <path>        SSH key path (default: ~/.ssh/id_rsa)
  --setup-keys            Generate and setup new SSH keys
  --test                  Test SSH connection
  --help                  Show this help

Example:
  $0 --host 192.168.0.147 --setup-keys
EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                PROXMOX_HOST="$2"
                shift 2
                ;;
            -u|--user)
                PROXMOX_USER="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            --setup-keys)
                SETUP_KEYS=true
                shift
                ;;
            --test)
                TEST_CONNECTION=true
                shift
                ;;
            --help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v ssh &> /dev/null; then
        log_error "ssh command not found"
        exit 1
    fi

    if ! command -v ssh-keygen &> /dev/null; then
        log_error "ssh-keygen command not found"
        exit 1
    fi

    log_success "All dependencies are installed"
}

# Generate SSH keys
generate_ssh_keys() {
    log_info "Generating SSH keys..."

    # Check if key already exists
    if [ -f "$SSH_KEY_PATH" ]; then
        log_warning "SSH key already exists: $SSH_KEY_PATH"
        read -p "Do you want to generate a new key? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Using existing key"
            return
        fi
        # Backup existing key
        mv "$SSH_KEY_PATH" "${SSH_KEY_PATH}.bak.$(date +%Y%m%d%H%M%S)"
        [ -f "${SSH_KEY_PATH}.pub" ] && mv "${SSH_KEY_PATH}.pub" "${SSH_KEY_PATH}.pub.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # Generate new key
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "proxmox@${HOSTNAME}"

    log_success "SSH keys generated"
}

# Setup SSH config
setup_ssh_config() {
    log_info "Setting up SSH config..."

    local host_entry="proxmox"
    local config_content="
Host proxmox
    HostName ${PROXMOX_HOST}
    User ${PROXMOX_USER}
    Port ${SSH_PORT}
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"

    # Backup existing config
    if [ -f "$SSH_CONFIG" ]; then
        # Check if entry already exists
        if grep -q "Host proxmox" "$SSH_CONFIG"; then
            log_warning "Proxmox entry already exists in SSH config"
            read -p "Do you want to update it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Keeping existing config"
                return
            fi
            # Remove old entry
            sed -i '/^Host proxmox/,/^$/d' "$SSH_CONFIG"
        fi
    fi

    # Create config directory if needed
    mkdir -p "$(dirname "$SSH_CONFIG")"
    chmod 700 "$(dirname "$SSH_CONFIG")"

    # Add new entry
    echo "$config_content" >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    log_success "SSH config updated"
}

# Copy SSH key to Proxmox host
copy_ssh_key() {
    log_info "Copying SSH key to Proxmox host..."

    local ssh_copy_id_cmd="ssh-copy-id -i ${SSH_KEY_PATH}.pub -p ${SSH_PORT} ${PROXMOX_USER}@${PROXMOX_HOST}"

    log_info "You will be prompted for the Proxmox password"
    eval "$ssh_copy_id_cmd" || {
        log_error "Failed to copy SSH key"
        log_info "Please copy the public key manually:"
        echo ""
        cat "${SSH_KEY_PATH}.pub"
        echo ""
        log_info "Add this key to: ${PROXMOX_USER}@${PROXMOX_HOST}:~/.ssh/authorized_keys"
        exit 1
    }

    log_success "SSH key copied"
}

# Test SSH connection
test_connection() {
    log_info "Testing SSH connection..."

    local ssh_test_cmd="ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p ${SSH_PORT} ${PROXMOX_USER}@${PROXMOX_HOST} 'echo \"Connection successful\"'"

    if eval "$ssh_test_cmd"; then
        log_success "SSH connection test passed"
    else
        log_error "SSH connection test failed"
        log_info "Please check:"
        echo "  - Proxmox host is reachable: ${PROXMOX_HOST}"
        echo "  - SSH service is running on port ${SSH_PORT}"
        echo "  - SSH key is properly configured"
        exit 1
    fi
}

# Verify Proxmox command
verify_proxmox() {
    log_info "Verifying Proxmox installation..."

    local ssh_cmd="ssh -p ${SSH_PORT} ${PROXMOX_USER}@${PROXMOX_HOST}"

    if eval "$ssh_cmd 'command -v qm &> /dev/null'"; then
        log_success "Proxmox VE installation verified"
    else
        log_warning "qm command not found on Proxmox host"
        log_info "Make sure you're running this on a Proxmox VE host"
    fi
}

# Show summary
show_summary() {
    echo ""
    log_success "Proxmox SSH configuration complete!"
    echo ""
    echo "Configuration:"
    echo "  Host:     ${PROXMOX_HOST}"
    echo "  User:     ${PROXMOX_USER}"
    echo "  Port:     ${SSH_PORT}"
    echo "  Key:      ${SSH_KEY_PATH}"
    echo ""
    echo "You can now connect to Proxmox using:"
    echo "  ssh proxmox"
    echo ""
    echo "Or use the host alias in other scripts:"
    echo "  PROXMOX_HOST=proxmox ./create-vm-from-iso.sh -i kali.iso"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Proxmox SSH Configuration${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    parse_args "$@"
    check_dependencies

    if [ "$SETUP_KEYS" = true ]; then
        generate_ssh_keys
    fi

    # Check if key exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_warning "SSH key not found: $SSH_KEY_PATH"
        read -p "Do you want to generate it? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            generate_ssh_keys
        else
            log_error "SSH key is required for passwordless authentication"
            exit 1
        fi
    fi

    setup_ssh_config
    copy_ssh_key
    test_connection
    verify_proxmox
    show_summary
}

# Run main function
main "$@"
