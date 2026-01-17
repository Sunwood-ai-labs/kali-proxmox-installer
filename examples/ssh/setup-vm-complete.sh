#!/bin/bash
#===============================================================================
# Proxmox VM - 完全セットアップスクリプト
#
# ユーザー作成 → SSHキー設定 → sudo設定 → SSH config追加 まで一括実行
#
# 使用方法:
#   ./setup-vm-complete.sh <VMID> <IPアドレス> [接続ユーザー]
#
# 例:
#   ./setup-vm-complete.sh 200 192.168.0.200 maki
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# デフォルト設定
#-------------------------------------------------------------------------------
DEFAULT_CONNECT_USER="maki"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$HOME/.ssh"

# 作成するユーザーリスト
USERS=("wolf" "zero-cc" "maki")

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
# 引数チェック
#-------------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID> <IPアドレス> [接続ユーザー]"
    echo ""
    echo "例:"
    echo "  $0 200 192.168.0.200 maki"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
CONNECT_USER="${3:-$DEFAULT_CONNECT_USER}"

#-------------------------------------------------------------------------------
# VMへの接続確認
#-------------------------------------------------------------------------------
check_vm_connectivity() {
    log_step "VMへの接続を確認中..."

    if ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
        log_success "VMに到達可能: $VM_IP"
    else
        log_error "VMに到達できません: $VM_IP"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# ユーザー作成スクリプトを転送して実行
#-------------------------------------------------------------------------------
setup_users() {
    log_step "ユーザー作成＆sudo設定..."

    local setup_users_script="${SCRIPT_DIR}/setup-users.sh"

    if [[ ! -f "$setup_users_script" ]]; then
        log_error "setup-users.sh が見つかりません: $setup_users_script"
        return 1
    fi

    # スクリプトを転送して実行
    cat "$setup_users_script" | ssh "${CONNECT_USER}@${VM_IP}" "sudo bash"

    log_success "ユーザー作成完了"
}

#-------------------------------------------------------------------------------
# SSHキーペアを生成
#-------------------------------------------------------------------------------
generate_ssh_key() {
    local user="$1"
    local key_name="prox_vm_${VMID}-${user}"
    local private_key="${SSH_DIR}/${key_name}"
    local public_key="${private_key}.pub"

    if [[ -f "$private_key" ]]; then
        log_warning "キーは既に存在します: $private_key"
        read -p "既存のキーを使用しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "新しいキーを生成します"
            rm -f "$private_key" "$public_key"
        else
            log_info "既存のキーを使用します"
            return 0
        fi
    fi

    log_step "SSHキーペアを生成中... ($user)"
    log_info "キー名: $key_name"

    ssh-keygen -t ed25519 -a 100 -f "$private_key" -C "prox_vm_${VMID}-${user}@$(hostname)" -N ""

    log_success "SSHキーペア生成完了: $user"
}

#-------------------------------------------------------------------------------
# 公開キーをVMに配置
#----------------------------------------------------------------------------#
deploy_public_key() {
    local user="$1"
    local key_name="prox_vm_${VMID}-${user}"
    local public_key="${SSH_DIR}/${key_name}.pub"

    if [[ ! -f "$public_key" ]]; then
        log_error "公開キーが見つかりません: $public_key"
        return 1
    fi

    log_step "公開キーをVMに配置中... ($user)"

    # 公開キーの内容を読み込み
    local pubkey_content
    pubkey_content=$(cat "$public_key")

    # VM上でroot権限を使って公開キーを配置
    ssh "${CONNECT_USER}@${VM_IP}" "sudo bash -c \"
        user_home=\\$(getent passwd '$user' | cut -d: -f6)
        ssh_dir=\\\"\${user_home}/.ssh\\\"
        auth_keys=\\\"\${ssh_dir}/authorized_keys\\\"

        if [[ ! -d \\\"\\\$ssh_dir\\\" ]]; then
            mkdir -p \\\"\\\$ssh_dir\\\"
            chmod 700 \\\"\\\$ssh_dir\\\"
            chown '$user':'$user' \\\"\\\$ssh_dir\\\"
        fi

        if [[ ! -f \\\"\\\$auth_keys\\\" ]]; then
            touch \\\"\\\$auth_keys\\\"
            chmod 600 \\\"\\\$auth_keys\\\"
            chown '$user':'$user' \\\"\\\$auth_keys\\\"
        fi

        if ! grep -qF '$pubkey_content' \\\"\\\$auth_keys\\\" 2>/dev/null; then
            echo '$pubkey_content' >> \\\"\\\$auth_keys\\\"
            echo '公開キーを追加しました: $user'
        else
            echo '既に公開キーが存在します: $user'
        fi
    \""

    log_success "公開キー配置完了: $user"
}

#-------------------------------------------------------------------------------
# SSH接続テスト
#-------------------------------------------------------------------------------
test_ssh_connection() {
    local user="$1"
    local key_name="prox_vm_${VMID}-${user}"
    local private_key="${SSH_DIR}/${key_name}"

    log_step "SSH接続をテスト中... ($user)"

    if ssh -i "$private_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${user}@${VM_IP}" "echo 'SSH接続成功！'" 2>/dev/null; then
        log_success "SSH接続テスト成功: $user"
        return 0
    else
        log_warning "SSH接続テスト失敗: $user"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# SSH configに設定を追加
#-------------------------------------------------------------------------------
add_to_ssh_config() {
    local user="$1"
    local config_file="$SSH_DIR/config"
    local host_entry="prox-${VMID}-${user}"
    local key_name="prox_vm_${VMID}-${user}"
    local private_key="${SSH_DIR}/${key_name}"

    log_step "SSH configに設定を追加中... ($user)"

    # configファイルが存在しない場合は作成
    if [[ ! -f "$config_file" ]]; then
        log_info "SSH configファイルを作成: $config_file"
        touch "$config_file"
        chmod 600 "$config_file"
    fi

    # 重複チェック
    if grep -q "^Host ${host_entry}" "$config_file" 2>/dev/null; then
        log_warning "Host ${host_entry} は既に存在します"
        return 0
    fi

    # 設定を追加
    cat >> "$config_file" << CONFIG_EOF

# Proxmox VM - 自動追加
Host ${host_entry}
    HostName ${VM_IP}
    User ${user}
    IdentityFile ${private_key}
    StrictHostKeyChecking no
CONFIG_EOF

    log_success "SSH configに追加完了: ${host_entry}"
}

#-------------------------------------------------------------------------------
# サマリー表示
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "==============================================================================="
    log_success "セットアップ完了！"
    echo "==============================================================================="
    echo ""
    echo -e "${MAGENTA}【接続情報】${NC}"
    echo "  VMID:      $VMID"
    echo "  IPアドレス: $VM_IP"
    echo "  ユーザー:   ${USERS[*]}"
    echo ""
    echo -e "${MAGENTA}【接続方法】${NC}"
    for user in "${USERS[@]}"; do
        echo "  ssh prox-${VMID}-${user}"
    done
    echo ""
    echo -e "${MAGENTA}【ユーザー情報】${NC}"
    echo "  すべてのユーザーで sudo NOPASSWD が設定されています"
    echo "  初回ログイン後にパスワード変更を推奨: passwd <username>"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - 完全セットアップ${NC}"
    echo "==============================================================================="
    echo ""
    echo -e "${MAGENTA}【ターゲット情報】${NC}"
    echo "  VMID:      $VMID"
    echo "  IPアドレス: $VM_IP"
    echo "  接続ユーザー: $CONNECT_USER"
    echo "  対象ユーザー: ${USERS[*]}"
    echo ""

    check_vm_connectivity
    setup_users

    # 各ユーザーに対してSSHキーを設定
    for user in "${USERS[@]}"; do
        echo ""
        echo "==============================================================================="
        log_step "ユーザー '${user}' のSSHキーを設定中..."
        echo "==============================================================================="
        echo ""

        generate_ssh_key "$user"
        deploy_public_key "$user"
        test_ssh_connection "$user"
        add_to_ssh_config "$user"
    done

    show_summary
}

# スクリプト実行
main "$@"
