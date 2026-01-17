#!/bin/bash
#===============================================================================
# Proxmox VM - qm経由でSSHサーバーを有効化
#
# qm exec / qm guest exec を使ってVM内でSSHサーバーをインストール・有効化
#
# 使用方法:
#   ./setup-ssh-via-qm.sh <VMID>
#
# 例:
#   ./setup-ssh-via-qm.sh 200
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
# 引数チェック
#-------------------------------------------------------------------------------
if [[ $# -ne 1 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID>"
    echo ""
    echo "例:"
    echo "  $0 200"
    echo ""
    exit 1
fi

VMID="$1"

#-------------------------------------------------------------------------------
# VMの状態確認
#-------------------------------------------------------------------------------
check_vm_status() {
    log_step "VMの状態を確認中..."

    local status=$(qm status $VMID | awk '{print $2}')
    log_info "VMステータス: $status"

    if [[ "$status" != "running" ]]; then
        log_error "VMが起動していません。まず起動してください: qm start $VMID"
        exit 1
    fi

    log_success "VMは起動中"
}

#-------------------------------------------------------------------------------
# QEMU Guest Agentの確認・有効化
#-------------------------------------------------------------------------------
check_qemu_guest_agent() {
    log_step "QEMU Guest Agentの状態を確認中..."

    # agentが有効か確認
    local agent_config=$(qm config $VMID | grep "agent:")

    if [[ -z "$agent_config" ]]; then
        log_warning "QEMU Guest Agentが無効です。有効化します..."
        qm set $VMID --agent enabled=1
        log_info "VMを再起動する必要があります"
        read -p "今すぐ再起動しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            qm reboot $VMID
            log_info "VMを再起動中...30秒待機..."
            sleep 30
        fi
    else
        log_success "QEMU Guest Agentは有効です"
    fi
}

#-------------------------------------------------------------------------------
# qm guest execでSSHサーバーをインストール
#-------------------------------------------------------------------------------
install_ssh_via_qemu_guest() {
    log_step "QEMU Guest Agent経由でSSHサーバーをインストール中..."

    # qm guest execを試す
    if qm guest exec $VMID -- bash -c "apt-get update && apt-get install -y openssh-server" 2>/dev/null; then
        log_success "SSHサーバーインストール完了"
        return 0
    else
        log_warning "qm guest exec に失敗しました"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# qm execでSSHサーバーをインストール（古い方法）
#-------------------------------------------------------------------------------
install_ssh_via_qm_exec() {
    log_step "qm exec経由でSSHサーバーをインストール中..."

    # qm execを試す
    if qm exec $VMID -- bash -c "apt-get update && apt-get install -y openssh-server" 2>/dev/null; then
        log_success "SSHサーバーインストール完了"
        return 0
    else
        log_warning "qm exec に失敗しました"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# SSHサーバーを有効化・起動
#-------------------------------------------------------------------------------
start_ssh_server() {
    log_step "SSHサーバーを有効化・起動中..."

    qm guest exec $VMID -- systemctl enable ssh 2>/dev/null || \
    qm exec $VMID -- systemctl enable ssh 2>/dev/null || \
    log_warning "systemctlコマンドが失敗しました"

    qm guest exec $VMID -- systemctl start ssh 2>/dev/null || \
    qm exec $VMID -- systemctl start ssh 2>/dev/null || \
    log_warning "SSH起動コマンドが失敗しました"

    log_success "SSHサーバー設定完了"
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - QEMU Guest Agent経由SSH設定${NC}"
    echo "==============================================================================="
    echo ""

    check_vm_status

    log_info "方法を試します..."

    # 方法1: QEMU Guest Agent経由
    if install_ssh_via_qemu_guest; then
        start_ssh_server
        show_success
        exit 0
    fi

    # 方法2: qm exec経由
    if install_ssh_via_qm_exec; then
        start_ssh_server
        show_success
        exit 0
    fi

    # どちらも失敗した場合
    log_error "自動設定に失敗しました"
    echo ""
    echo "手動でKali Linuxのコンソールから実行してください:"
    echo ""
    echo -e "${GREEN}sudo apt update && sudo apt install -y openssh-server${NC}"
    echo -e "${GREEN}sudo systemctl enable ssh${NC}"
    echo -e "${GREEN}sudo systemctl start ssh${NC}"
    echo ""
    echo "または、QEMU Guest AgentをVM内で有効にしてください:"
    echo ""
    echo -e "${GREEN}sudo apt install -y qemu-guest-agent${NC}"
    echo -e "${GREEN}sudo systemctl enable qemu-guest-agent${NC}"
    echo -e "${GREEN}sudo systemctl start qemu-guest-agent${NC}"
    echo ""
}

show_success() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}SSHサーバー設定完了${NC}"
    echo "==============================================================================="
    echo ""
    echo "【次のステップ】"
    echo "  固定IP設定を実行:"
    echo "    ./auto-setup-static-ip.sh $VMID <固定IP> <ゲートウェイ> kali"
    echo ""
    echo "==============================================================================="
}

# スクリプト実行
main "$@"
