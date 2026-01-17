#!/bin/bash
#===============================================================================
# Proxmox VM - 自動固定IP設定スクリプト
#
# DHCPでIPを取得して、SSHで接続し、固定IPを設定
#
# 使用方法:
#   ./auto-setup-static-ip.sh <VMID> <固定IP> <ゲートウェイ> [ユーザー名]
#
# 例:
#   ./auto-setup-static-ip.sh 200 192.168.0.200 192.168.0.1 kali
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
if [[ $# -lt 4 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID> <現在のIP> <固定IP> <ゲートウェイ> [ユーザー名]"
    echo ""
    echo "例:"
    echo "  $0 200 192.168.0.136 192.168.0.200 192.168.0.1 kali"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
STATIC_IP="$3"
GATEWAY="$4"
VM_USER="${5:-kali}"
NETMASK="255.255.255.0"
DNS_SERVER="8.8.8.8"

#-------------------------------------------------------------------------------
# VMへの接続確認
#-------------------------------------------------------------------------------
check_vm_connectivity() {
    log_step "VMへの接続を確認中..."

    if ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
        log_success "VMに到達可能: $VM_IP"
    else
        log_error "VMに到達できません: $VM_IP"
        log_info "IPアドレスが正しいか確認してください"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# SSH接続テスト（パスワード認証）
#-------------------------------------------------------------------------------
test_ssh_connection() {
    log_step "SSH接続をテスト中..."
    log_info "パスワード入力が必要です"

    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VM_USER}@${VM_IP}" "echo 'SSH接続成功'"; then
        log_success "SSH接続成功"
        return 0
    else
        log_error "SSH接続失敗"
        log_info "ユーザー名とパスワードを確認してください"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# 固定IP設定スクリプトを生成して転送
#-------------------------------------------------------------------------------
setup_static_ip() {
    log_step "固定IPを設定中..."

    # NetworkManagerを使用した設定
    local nmconnection_cmd="sudo bash -c 'cat > /etc/NetworkManager/system-connections/static-eth0.nmconnection << EOF
[connection]
id=static-eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=manual
addresses=${STATIC_IP}/24
gateway=${GATEWAY}
dns=${DNS_SERVER}

[ipv6]
method=disabled
EOF
chmod 600 /etc/NetworkManager/system-connections/static-eth0.nmconnection
systemctl restart NetworkManager'"

    # 実行
    log_info "NetworkManager設定を適用中..."
    ssh -tt "${VM_USER}@${VM_IP}" "$nmconnection_cmd"

    log_success "固定IP設定完了"
}

#-------------------------------------------------------------------------------
# 設定後の接続テスト
#----------------------------------------------------------------------------#
test_static_ip_connection() {
    log_step "固定IPでの接続をテスト中..."

    sleep 3  # ネットワークが安定するまで待機

    if ping -c 2 -W 3 "$STATIC_IP" &> /dev/null; then
        log_success "固定IP $STATIC_IP で到達可能"
    else
        log_warning "固定IP $STATIC_IP でまだ到達できません"
        log_info "ネットワークの再起動に時間がかかっている可能性があります"
        log_info "後で \"ping $STATIC_IP\" で確認してください"
    fi
}

#-------------------------------------------------------------------------------
# 設定サマリー表示
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}固定IP設定完了${NC}"
    echo "==============================================================================="
    echo ""
    echo "【設定内容】"
    echo "  VMID:       $VMID"
    echo "  固定IP:     $STATIC_IP"
    echo "  サブネット: $NETMASK"
    echo "  ゲートウェイ: $GATEWAY"
    echo "  DNS:        $DNS_SERVER"
    echo "  ユーザー名:   $VM_USER"
    echo ""
    echo "【接続確認】"
    echo "  ping $STATIC_IP"
    echo "  ssh ${VM_USER}@${STATIC_IP}"
    echo ""
    echo "【次のステップ】"
    echo "  SSHキー設定を実行:"
    echo "    ./setup-ssh-keys.sh $VMID $STATIC_IP $VM_USER"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - 自動固定IP設定${NC}"
    echo "==============================================================================="
    echo ""

    log_info "現在のIP: $VM_IP"
    log_info "設定する固定IP: $STATIC_IP"

    if ! check_vm_connectivity; then
        log_error "VMに接続できません。IPアドレスを確認してください"
        exit 1
    fi

    if ! test_ssh_connection; then
        log_error "SSH接続できません。ユーザー名とパスワードを確認してください"
        exit 1
    fi

    setup_static_ip
    test_static_ip_connection
    show_summary

    echo ""
    log_success "すべて完了！"
    echo ""
}

# スクリプト実行
main "$@"
