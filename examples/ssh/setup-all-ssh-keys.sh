#!/bin/bash
#===============================================================================
# Proxmox VM - 複数ユーザーのSSHキー設定スクリプト
#
# 使用方法:
#   ./setup-all-ssh-keys.sh <VMID> <IPアドレス> [root_user]
#
# 例:
#   ./setup-all-ssh-keys.sh 200 192.168.0.200 maki
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
    echo "  $0 <VMID> <IPアドレス> [sudoユーザー]"
    echo ""
    echo "例:"
    echo "  $0 200 192.168.0.200 maki"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
SUDO_USER="${3:-maki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$HOME/.ssh"

# 設定するユーザーリスト
USERS=("wolf" "zero-cc" "maki")

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
# 公開キーをVMに転送（VM上スクリプト経由）
#----------------------------------------------------------------------------#
deploy_public_key() {
    local user="$1"
    local key_name="prox_vm_${VMID}-${user}"
    local public_key="${SSH_DIR}/${key_name}.pub"

    if [[ ! -f "$public_key" ]]; then
        log_error "公開キーが見つかりません: $public_key"
        return 1
    fi

    log_step "公開キーをVMに転送中... ($user)"

    # 公開キーの内容を読み込み
    local pubkey_content
    pubkey_content=$(cat "$public_key")

    # VM上でroot権限を使って公開キーを配置
    ssh "${SUDO_USER}@${VM_IP}" "sudo bash -c \"
        # ユーザーのSSHディレクトリ確認
        user_home=\\$(getent passwd '$user' | cut -d: -f6)
        ssh_dir=\\\"\${user_home}/.ssh\\\"
        auth_keys=\\\"\${ssh_dir}/authorized_keys\\\"

        # SSHディレクトリが存在しない場合は作成
        if [[ ! -d \\\"\\\$ssh_dir\\\" ]]; then
            mkdir -p \\\"\\\$ssh_dir\\\"
            chmod 700 \\\"\\\$ssh_dir\\\"
            chown '$user':'$user' \\\"\\\$ssh_dir\\\"
        fi

        # authorized_keysが存在しない場合は作成
        if [[ ! -f \\\"\\\$auth_keys\\\" ]]; then
            touch \\\"\\\$auth_keys\\\"
            chmod 600 \\\"\\\$auth_keys\\\"
            chown '$user':'$user' \\\"\\\$auth_keys\\\"
        fi

        # 公開キーが既に存在するか確認
        if grep -q '$user' \\\"\\\$auth_keys\\\" 2>/dev/null; then
            echo '既に公開キーが存在します'
        else
            # 公開キーを追加
            echo '$pubkey_content' >> \\\"\\\$auth_keys\\\"
            echo '公開キーを追加しました'
        fi
    \""

    log_success "公開キー転送完了: $user"
}

#-------------------------------------------------------------------------------
# SSH接続テスト
#-------------------------------------------------------------------------------
test_ssh_connection() {
    local user="$1"
    local key_name="prox_vm_${VMID}-${user}"
    local private_key="${SSH_DIR}/${key_name}"

    log_step "SSH接続をテスト中... ($user)"

    if ssh -i "$private_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${user}@${VM_IP}" "echo 'SSH接続成功！'; uname -a" 2>/dev/null; then
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
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - 複数ユーザーSSHキー設定${NC}"
    echo "==============================================================================="
    echo ""
    echo -e "${MAGENTA}【ターゲット情報】${NC}"
    echo "  VMID:      $VMID"
    echo "  IPアドレス: $VM_IP"
    echo "  接続ユーザー: $SUDO_USER (sudo権限が必要です)"
    echo "  対象ユーザー: ${USERS[*]}"
    echo ""

    # 各ユーザーに対してSSHキーを設定
    for user in "${USERS[@]}"; do
        echo "==============================================================================="
        log_step "ユーザー '${user}' のSSHキーを設定中..."
        echo "==============================================================================="
        echo ""

        generate_ssh_key "$user"
        deploy_public_key "$user"
        test_ssh_connection "$user"
        add_to_ssh_config "$user"

        echo ""
    done

    echo "==============================================================================="
    log_success "すべて完了！"
    echo "==============================================================================="
    echo ""
    echo -e "${MAGENTA}【接続方法】${NC}"
    for user in "${USERS[@]}"; do
        echo "  ssh prox-${VMID}-${user}"
    done
    echo ""
}

# スクリプト実行
main "$@"
