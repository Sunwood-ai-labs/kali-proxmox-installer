#!/bin/bash
#===============================================================================
# Proxmox VM - SSHキー配置スクリプト（VM上で実行）
#
# 使用方法:
#   cat deploy-keys-data.sh | ssh prox-200 'sudo bash'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

#-------------------------------------------------------------------------------
# ユーザーと公開キーのマッピング
#-------------------------------------------------------------------------------
declare -A SSH_KEYS
SSH_KEYS=(
    ["wolf"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKJ72BqM7V0SX/4tSH6RGW1VjePWYOL43TS1BpRQf7KZ prox_vm_200-wolf@Aslan"
    ["zero-cc"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYEdS/Cg523233Fh9pasi6z4vI9OpIegsYM8XtVdPRg prox_vm_200-zero-cc@Aslan"
    ["maki"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIvjlkjPYssMwBi/i8jKKORYDvVsMpPyDYkv/13VneZV prox_vm_200-maki@Aslan"
)

#-------------------------------------------------------------------------------
# 公開キーを配置
#-------------------------------------------------------------------------------
deploy_key() {
    local user="$1"
    local pubkey="$2"

    log_step "ユーザー '${user}' にSSHキーを配置中..."

    # ユーザーのホームディレクトリを取得
    local user_home
    user_home=$(getent passwd "$user" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_warning "ユーザー '${user}' が見つかりません"
        return 1
    fi

    local ssh_dir="${user_home}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    # SSHディレクトリが存在しない場合は作成
    if [[ ! -d "$ssh_dir" ]]; then
        log_info "SSHディレクトリを作成: $ssh_dir"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$user:$user" "$ssh_dir"
    fi

    # authorized_keysが存在しない場合は作成
    if [[ ! -f "$auth_keys" ]]; then
        log_info "authorized_keysを作成: $auth_keys"
        touch "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$user:$user" "$auth_keys"
    fi

    # 公開キーが既に存在するか確認
    if grep -q "$user" "$auth_keys" 2>/dev/null; then
        log_info "既に公開キーが存在します"
        return 0
    fi

    # 公開キーを追加
    echo "$pubkey" >> "$auth_keys"
    log_success "公開キーを追加しました: $user"
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - SSHキー配置${NC}"
    echo "==============================================================================="
    echo ""

    # root権限チェック
    if [[ $EUID -ne 0 ]]; then
        echo "このスクリプトはroot権限で実行する必要があります"
        exit 1
    fi

    for user in "${!SSH_KEYS[@]}"; do
        deploy_key "$user" "${SSH_KEYS[$user]}"
        echo ""
    done

    echo "==============================================================================="
    log_success "すべて完了！"
    echo "==============================================================================="
    echo ""
}

# スクリプト実行
main "$@"
