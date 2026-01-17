#!/bin/bash
#===============================================================================
# Proxmox VM - SSHキー設定スクリプト
#
# 使用方法:
#   ./setup-ssh-keys.sh <VMID> <IPアドレス> [ユーザー名]
#
# 例:
#   ./setup-ssh-keys.sh 200 192.168.0.200 kali
#   ./setup-ssh-keys.sh 200 192.168.0.200 root
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# デフォルト設定
#-------------------------------------------------------------------------------
DEFAULT_USER="kali"
KEY_NAME="prox_vm_${VMID:-default}"
SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="${SSH_DIR}/${KEY_NAME}"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
AUTH_KEYS_BACKUP="/tmp/authorized_keys.backup"

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

#-------------------------------------------------------------------------------
# 引数チェック
#-------------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID> <IPアドレス> [ユーザー名]"
    echo ""
    echo "例:"
    echo "  $0 200 192.168.0.200 kali      # kaliユーザーで接続"
    echo "  $0 200 192.168.0.200 root      # rootユーザーで接続"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
VM_USER="${3:-$DEFAULT_USER}"
KEY_NAME="prox_vm_${VMID}"
PRIVATE_KEY="${SSH_DIR}/${KEY_NAME}"
PUBLIC_KEY="${PRIVATE_KEY}.pub"

#-------------------------------------------------------------------------------
# SSHディレクトリの存在確認
#-------------------------------------------------------------------------------
check_ssh_dir() {
    log_step "SSHディレクトリをチェック中..."

    if [[ ! -d "$SSH_DIR" ]]; then
        log_info "SSHディレクトリを作成: $SSH_DIR"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    log_success "SSHディレクトリOK"
}

#-------------------------------------------------------------------------------
# 既存のキー確認
#-------------------------------------------------------------------------------
check_existing_keys() {
    log_step "既存のSSHキーをチェック中..."

    if [[ -f "$PRIVATE_KEY" ]]; then
        log_warning "キーは既に存在します: $PRIVATE_KEY"
        read -p "既存のキーを使用しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "新しいキーを生成します"
            return 1
        fi
        log_info "既存のキーを使用します"
        return 0
    fi

    return 1
}

#-------------------------------------------------------------------------------
# SSHキーペアを生成
#-------------------------------------------------------------------------------
generate_ssh_key() {
    log_step "SSHキーペアを生成中..."

    log_info "キー名: $KEY_NAME"
    log_info "保存先: $PRIVATE_KEY"

    ssh-keygen -t ed25519 -a 100 -f "$PRIVATE_KEY" -C "prox_vm_${VMID}@$(hostname)" -N ""

    log_success "SSHキーペア生成完了"
}

#-------------------------------------------------------------------------------
# VMへの接続確認
#-------------------------------------------------------------------------------
check_vm_connectivity() {
    log_step "VMへの接続を確認中..."

    if ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
        log_success "VMに到達可能: $VM_IP"
    else
        log_error "VMに到達できません: $VM_IP"
        log_info "VMが起動しているか、ネットワーク設定を確認してください"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 公開キーをVMに転送
#----------------------------------------------------------------------------#
copy_public_key() {
    log_step "公開キーをVMに転送中..."

    log_info "公開キーの内容:"
    cat "$PUBLIC_KEY"
    echo ""

    # ssh-copy-idを使用
    if command -v ssh-copy-id &> /dev/null; then
        log_info "ssh-copy-id を使用して転送..."

        # 既存のauthorized_keysをバックアップ
        log_info "VM上のauthorized_keysをバックアップ..."
        ssh "${VM_USER}@${VM_IP}" "mkdir -p ~/.ssh && cat ~/.ssh/authorized_keys > ${AUTH_KEYS_BACKUP} 2>/dev/null || true"

        # 公開キーを転送
        ssh-copy-id -i "$PUBLIC_KEY" "${VM_USER}@${VM_IP}"

        log_success "公開キー転送完了"
    else
        log_warning "ssh-copy-id が見つかりません"
        log_info "手動で公開キーを転送します..."

        # 公開キーをVMに転送
        cat "$PUBLIC_KEY" | ssh "${VM_USER}@${VM_IP}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

        log_success "公開キー転送完了"
    fi
}

#-------------------------------------------------------------------------------
# SSH接続テスト
#-------------------------------------------------------------------------------
test_ssh_connection() {
    log_step "SSH接続をテスト中..."

    # SSH configの作成を提案
    echo ""
    log_info "SSH configに以下を追加すると便利です："
    echo ""
    echo -e "${GREEN}Host prox-${VMID}${NC}"
    echo "    HostName ${VM_IP}"
    echo "    User ${VM_USER}"
    echo "    IdentityFile ${PRIVATE_KEY}"
    echo "    StrictHostKeyChecking no"
    echo ""

    # 接続テスト
    log_info "接続テストを実行中..."

    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VM_USER}@${VM_IP}" "echo 'SSH接続成功！'; uname -a"; then
        log_success "SSH接続テスト成功！"
    else
        log_warning "SSH接続テスト失敗"
        log_info "パスワード認証が必要な場合があります"
    fi
}

#-------------------------------------------------------------------------------
# 簡易接続スクリプトを生成
#-------------------------------------------------------------------------------
generate_connect_script() {
    local script_name="connect-vm-${VMID}.sh"

    cat > "$script_name" << SCRIPT_EOF
#!/bin/bash
# VM ${VMID} へのSSH接続スクリプト

ssh -i "${PRIVATE_KEY}" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "\$@"
SCRIPT_EOF

    chmod +x "$script_name"

    log_success "接続スクリプト生成: $script_name"
    log_info "使用方法: ./$script_name または ./connect-vm-${VMID}.sh <command>"
}

#-------------------------------------------------------------------------------
# 設定サマリー表示
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}SSHキー設定完了${NC}"
    echo "==============================================================================="
    echo ""
    echo "【接続情報】"
    echo "  VMID:      $VMID"
    echo "  IPアドレス: $VM_IP"
    echo "  ユーザー名:  $VM_USER"
    echo ""
    echo "【SSHキー】"
    echo "  秘密鍵:     $PRIVATE_KEY"
    echo "  公開鍵:     $PUBLIC_KEY"
    echo ""
    echo "【接続方法】"
    echo ""
    echo "  方法1: スクリプトを使用（推奨）"
    echo "    ./connect-vm-${VMID}.sh"
    echo "    ./connect-vm-${VMID}.sh 'ls -la'"
    echo ""
    echo "  方法2: 直接SSH"
    echo "    ssh -i $PRIVATE_KEY ${VM_USER}@${VM_IP}"
    echo ""
    echo "  方法3: SSH configに追加後"
    echo "    ssh prox-${VMID}"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - SSHキー設定${NC}"
    echo "==============================================================================="
    echo ""

    check_ssh_dir

    if ! check_existing_keys; then
        generate_ssh_key
    fi

    check_vm_connectivity
    copy_public_key
    test_ssh_connection
    generate_connect_script
    show_summary

    echo ""
    log_success "すべて完了！"
    echo ""
}

# スクリプト実行
main "$@"
