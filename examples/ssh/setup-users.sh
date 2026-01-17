#!/bin/bash
#===============================================================================
# Proxmox VM - ユーザー作成＆sudo設定スクリプト
#
# 使用方法:
#   ssh prox-200 'bash -s' < setup-users.sh
#   または
#   ./setup-users.sh <VM_HOST>
#
# 作成するユーザー: wolf, zero-cc, maki
# sudo: パスワードなしで実行可能
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
# 設定
#-------------------------------------------------------------------------------
USERS=("wolf" "zero-cc" "maki")

#-------------------------------------------------------------------------------
# ユーザー作成
#-------------------------------------------------------------------------------
create_user() {
    local user="$1"

    if id "$user" &>/dev/null; then
        log_warning "ユーザー '$user' は既に存在します"
        return 0
    fi

    log_info "ユーザー '$user' を作成中..."

    # ユーザー作成（ホームディレクトリ付き、シェルはbash）
    useradd -m -s /bin/bash "$user"

    # パスワード設定（ユーザー名と同じにする）
    echo "$user:$user" | chpasswd

    # 初回ログイン時にパスワード変更を強制する場合はコメントを外す
    # chage -d 0 "$user"

    log_success "ユーザー '$user' 作成完了"
}

#-------------------------------------------------------------------------------
# sudoers設定
#-------------------------------------------------------------------------------
setup_sudo() {
    local user="$1"
    local sudoers_file="/etc/sudoers.d/${user}"

    log_info "ユーザー '$user' のsudo権限を設定中..."

    # sudoersファイル作成
    cat > "$sudoers_file" << SUDOERS_EOF
# $user - sudo passwordless
$user ALL=(ALL:ALL) NOPASSWD: ALL
SUDOERS_EOF

    # パーミッション設定（重要）
    chmod 440 "$sudoers_file"

    log_success "sudo権限設定完了: $user"
}

#-------------------------------------------------------------------------------
# SSH公開キー設定（オプション）
#-------------------------------------------------------------------------------
setup_ssh_key() {
    local user="$1"
    local ssh_dir="/home/$user/.ssh"

    if [[ ! -d "$ssh_dir" ]]; then
        log_info "SSHディレクトリ作成: $ssh_dir"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$user:$user" "$ssh_dir"
    fi

    # authorized_keysが存在しない場合は空ファイルを作成
    if [[ ! -f "$ssh_dir/authorized_keys" ]]; then
        touch "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown "$user:$user" "$ssh_dir/authorized_keys"
    fi

    log_info "SSHディレクトリ準備完了: $user"
}

#-------------------------------------------------------------------------------
# ユーザー情報表示
#-------------------------------------------------------------------------------
show_user_info() {
    local user="$1"

    echo ""
    echo "  ┌──────────────────────────────────────┐"
    echo "  │  ユーザー: $user"
    echo "  │  パスワード: $user"
    echo "  │  sudo: NOPASSWD"
    echo "  │  SSH: /home/$user/.ssh/authorized_keys"
    echo "  └──────────────────────────────────────┘"
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - ユーザー作成＆sudo設定${NC}"
    echo "==============================================================================="
    echo ""

    # root権限チェック
    if [[ $EUID -ne 0 ]]; then
        log_error "このスクリプトはroot権限で実行する必要があります"
        log_info "sudoを使用してください: sudo $0"
        exit 1
    fi

    # 各ユーザーを作成
    for user in "${USERS[@]}"; do
        log_step "ユーザー '$user' のセットアップ"

        create_user "$user"
        setup_sudo "$user"
        setup_ssh_key "$user"
        show_user_info "$user"

        echo ""
    done

    echo "==============================================================================="
    log_success "すべて完了！"
    echo "==============================================================================="
    echo ""
    log_info "作成されたユーザー: ${USERS[*]}"
    echo ""
    log_warning "セキュリティのため、初回ログイン後にパスワードを変更してください"
    echo "  変更方法: passwd <username>"
    echo ""
    log_info "SSH公開キーを追加する場合:"
    echo "  ssh-copy-id -i <公開鍵> <user>@<VM_IP>"
    echo "  または手動で /home/<user>/.ssh/authorized_keys に追加"
    echo ""
}

# スクリプト実行
main "$@"
