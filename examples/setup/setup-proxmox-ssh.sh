#!/bin/bash
#===============================================================================
# Proxmox SSH接続設定スクリプト
#
# ProxmoxホストへのSSHキー設定とSSH configの自動登録
#
# 使用方法:
#   ./setup-proxmox-ssh.sh [ホスト] [ユーザー名]
#
# 例:
#   ./setup-proxmox-ssh.sh 192.168.0.147 root
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 設定変数
#-------------------------------------------------------------------------------
PROXMOX_HOST="${1:-192.168.0.147}"
PROXMOX_USER="${2:-root}"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
PROXMOX_KEY_NAME="prox_proxmox"
PROXMOX_KEY="$SSH_DIR/${PROXMOX_KEY_NAME}"

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
# SSHディレクトリの確認と作成
#-------------------------------------------------------------------------------
ensure_ssh_dir() {
    log_step "SSHディレクトリを確認中..."

    if [[ ! -d "$SSH_DIR" ]]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        log_success "SSHディレクトリを作成: $SSH_DIR"
    else
        log_success "SSHディレクトリ: OK"
    fi
}

#-------------------------------------------------------------------------------
# 既存のキー確認
#-------------------------------------------------------------------------------
check_existing_key() {
    log_step "既存のSSHキーを確認中..."

    if [[ -f "$PROXMOX_KEY" ]]; then
        log_warning "キーは既に存在します: $PROXMOX_KEY"
        read -p "既存のキーを使用しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "既存のキーを使用します"
            return 0
        else
            log_info "新しいキーを生成します"
            rm -f "$PROXMOX_KEY" "$PROXMOX_KEY.pub"
        fi
    fi

    return 1
}

#-------------------------------------------------------------------------------
# SSHキーペアを生成
#-------------------------------------------------------------------------------
generate_ssh_key() {
    log_step "SSHキーペアを生成中..."

    log_info "キー名: $PROXMOX_KEY_NAME"
    log_info "保存先: $PROXMOX_KEY"

    ssh-keygen -t ed25519 -a 100 -f "$PROXMOX_KEY" -C "prox_proxmox@$(hostname)" -N ""

    log_success "SSHキーペア生成完了"
}

#-------------------------------------------------------------------------------
# 公開キーをProxmoxに転送
#-------------------------------------------------------------------------------
copy_public_key() {
    log_step "公開キーをProxmoxに転送中..."

    # 公開キーの内容を表示
    log_info "公開キーの内容:"
    cat "${PROXMOX_KEY}.pub"
    echo ""

    # ssh-copy-idを使用
    if command -v ssh-copy-id &> /dev/null; then
        log_info "ssh-copy-id を使用して転送..."

        if ssh-copy-id -i "${PROXMOX_KEY}.pub" "${PROXMOX_USER}@${PROXMOX_HOST}"; then
            log_success "公開キー転送完了"
        else
            log_error "公開キー転送に失敗しました"
            log_info "手動で転送してください:"
            echo "  cat ${PROXMOX_KEY}.pub | ssh ${PROXMOX_USER}@${PROXMOX_HOST} 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
            exit 1
        fi
    else
        log_warning "ssh-copy-id が見つかりません"
        log_info "手動で転送します..."

        cat "${PROXMOX_KEY}.pub" | ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

        log_success "公開キー転送完了"
    fi
}

#-------------------------------------------------------------------------------
# SSH接続テスト
#-------------------------------------------------------------------------------
test_ssh_connection() {
    log_step "SSH接続をテスト中..."

    local ssh_cmd="ssh -i $PROXMOX_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${PROXMOX_USER}@${PROXMOX_HOST} 'echo \"SSH接続成功！\"; hostname; uptime'"

    if eval "$ssh_cmd"; then
        log_success "SSH接続テスト成功！"
    else
        log_error "SSH接続テスト失敗"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# SSH configに設定を追加
#-------------------------------------------------------------------------------
setup_ssh_config() {
    log_step "SSH configにProxmoxの設定を追加中..."

    # 既存の設定を確認
    if grep -q "Host proxmox" "$SSH_CONFIG" 2>/dev/null; then
        log_warning "SSH configに 'proxmox' の設定は既に存在します"
        read -p "設定を更新しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "SSH configの更新をスキップします"
            return 0
        fi

        # 既存の設定を削除
        log_info "既存の設定を削除中..."
        sed -i '/^Host proxmox$/,/^$/d' "$SSH_CONFIG"
    fi

    # 設定を追加
    log_info "設定を追加中..."
    cat >> "$SSH_CONFIG" << SSH_CONFIG_EOF

# Proxmox VE - 自動追加
Host proxmox
    HostName ${PROXMOX_HOST}
    User ${PROXMOX_USER}
    IdentityFile ${PROXMOX_KEY}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    Port 22

SSH_CONFIG_EOF

    log_success "SSH configの設定完了"
}

#-------------------------------------------------------------------------------
# 接続方法を表示
#-------------------------------------------------------------------------------
show_connection_info() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}Proxmox SSH接続設定完了${NC}"
    echo "==============================================================================="
    echo ""
    echo "【接続方法】"
    echo ""
    echo "  方法1: SSH configを使用（推奨）"
    echo "    ssh proxmox"
    echo ""
    echo "  方法2: 直接SSH"
    echo "    ssh -i $PROXMOX_KEY ${PROXMOX_USER}@${PROXMOX_HOST}"
    echo ""
    echo "  方法3: コマンド実行"
    echo "    ssh proxmox 'qm list'"
    echo ""
    echo "【SSHキー】"
    echo "  秘密鍵:     $PROXMOX_KEY"
    echo "  公開鍵:     ${PROXMOX_KEY}.pub"
    echo ""
    echo "【次のステップ】"
    echo "  自動インストールを実行:"
    echo "    ./remote-autoinstall.sh"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox SSH接続設定${NC}"
    echo "==============================================================================="
    echo ""

    log_info "ターゲット: ${PROXMOX_USER}@${PROXMOX_HOST}"
    echo ""

    ensure_ssh_dir

    if ! check_existing_key; then
        generate_ssh_key
    fi

    copy_public_key
    test_ssh_connection
    setup_ssh_config
    show_connection_info

    echo ""
    log_success "すべて完了！"
    echo ""
}

# スクリプト実行
main "$@"
