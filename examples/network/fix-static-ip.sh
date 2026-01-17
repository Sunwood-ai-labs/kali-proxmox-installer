#!/bin/bash
#===============================================================================
# Proxmox VM - 固定IP問題診断・修正スクリプト
#
# SSH接続済みのVM内でNetworkManager設定を診断・修正
#
# 使用方法:
#   ./fix-static-ip.sh <VMID> <現在のIP> <固定IP> <ゲートウェイ> [ユーザー名]
#
# 例:
#   ./fix-static-ip.sh 200 192.168.0.136 192.168.0.200 192.168.0.1 maki
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
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1" >&2
}

#-------------------------------------------------------------------------------
# 引数チェック
#-------------------------------------------------------------------------------
if [[ $# -lt 4 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID> <現在のIP> <固定IP> <ゲートウェイ> [ユーザー名]"
    echo ""
    echo "例:"
    echo "  $0 200 192.168.0.136 192.168.0.200 192.168.0.1 maki"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
STATIC_IP="$3"
GATEWAY="$4"
VM_USER="${5:-kali}"

# SSHキーのパス
SSH_KEY="$HOME/.ssh/prox_vm_${VMID}"

#-------------------------------------------------------------------------------
# SSHキーの存在確認
#-------------------------------------------------------------------------------
check_ssh_key() {
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSHキーが見つかりません: $SSH_KEY"
        log_info "まず setup-ssh-keys.sh を実行してください"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# NetworkManagerの状態を診断
#-------------------------------------------------------------------------------
diagnose_network() {
    log_step "NetworkManagerの状態を診断中..."

    log_info "=== NetworkManager サービス状態 ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "systemctl status NetworkManager --no-pager -l" || true

    echo ""
    log_info "=== ネットワーク接続一覧 ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "nmcli connection show" || true

    echo ""
    log_info "=== 現在のIPアドレス ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "ip addr show" || true

    echo ""
    log_info "=== ルート情報 ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "ip route show" || true
}

#-------------------------------------------------------------------------------
# インターフェース名を取得
#-------------------------------------------------------------------------------
get_interface_name() {
    log_step "ネットワークインターフェース名を取得中..."

    local iface=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "ip route get 1.1.1.1 | awk '{print \$5}' | head -1" 2>/dev/null)

    if [[ -n "$iface" ]]; then
        log_success "インターフェース名: $iface"
        echo "$iface"
    else
        log_error "インターフェース名を取得できませんでした"
        echo "eth0"
    fi
}

#-------------------------------------------------------------------------------
# 固定IPを再設定
#-------------------------------------------------------------------------------
reset_static_ip() {
    local iface="$1"

    log_step "固定IPを再設定中..."

    # 既存の接続を削除
    log_info "既存の固定IP接続を削除..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "sudo nmcli connection delete 'static-${iface}' 2>/dev/null || true"

    # 新しい固定IP接続を作成
    log_info "新しい固定IP接続を作成..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "sudo nmcli connection add type ethernet con-name 'static-${iface}' ifname '${iface}' ip4 ${STATIC_IP}/24 gw4 ${GATEWAY} ipv4.dns '8.8.8.8 8.8.4.4' && exit"

    # 接続をアップ
    log_info "接続を有効化..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -t "${VM_USER}@${VM_IP}" "sudo nmcli connection up 'static-${iface}' && exit"

    # 自動接続を有効化
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "sudo nmcli connection modify 'static-${iface}' connection.autoconnect yes"

    log_success "固定IP設定完了"
}

#-------------------------------------------------------------------------------
# 設定を確認
#-------------------------------------------------------------------------------
verify_settings() {
    log_step "設定を確認中..."

    echo ""
    log_info "=== 更新後の接続一覧 ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "nmcli connection show"

    echo ""
    log_info "=== 更新後のIPアドレス ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "ip addr show"

    echo ""
    log_info "=== 更新後のルート情報 ==="
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "ip route show"
}

#-------------------------------------------------------------------------------
# 接続テスト
#-------------------------------------------------------------------------------
test_connectivity() {
    log_step "固定IPでの接続をテスト中..."

    sleep 3

    if ping -c 3 -W 3 "$STATIC_IP" &> /dev/null; then
        log_success "固定IP $STATIC_IP で到達可能！"
        return 0
    else
        log_warning "固定IP $STATIC_IP でまだ到達できません"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - 固定IP問題診断・修正${NC}"
    echo "==============================================================================="
    echo ""

    check_ssh_key

    log_info "現在のIP: $VM_IP"
    log_info "設定する固定IP: $STATIC_IP"
    echo ""

    diagnose_network

    local iface=$(get_interface_name)

    echo ""
    read -p "$(echo -e ${YELLOW}固定IPを再設定しますか？ [y/N]: ${NC})" -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reset_static_ip "$iface"
        verify_settings
        test_connectivity

        echo ""
        echo "==============================================================================="
        echo -e "${GREEN}処理完了${NC}"
        echo "==============================================================================="
        echo ""
        echo "【次のステップ】"
        echo "  固定IPでSSHキーを再設定:"
        echo "    ./setup-ssh-keys.sh $VMID $STATIC_IP $VM_USER"
        echo ""
        echo "==============================================================================="
    else
        log_info "キャンセルしました"
    fi

    echo ""
}

# スクリプト実行
main "$@"
