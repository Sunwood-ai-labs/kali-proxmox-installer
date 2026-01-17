#!/bin/bash
#===============================================================================
# Proxmox VM - セットアップ検証スクリプト
#
# VMのセットアップ状態を検証（インストール完了、ネットワーク、SSH接続）
#
# 使用方法:
#   ./verify-vm-setup.sh <VMID> <IPアドレス> [ユーザー名]
#
# 例:
#   ./verify-vm-setup.sh 200 192.168.0.200 maki
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
    echo "  $0 200 192.168.0.200 maki"
    echo ""
    exit 1
fi

VMID="$1"
VM_IP="$2"
VM_USER="${3:-maki}"

# 検証結果カウンター
PASS_COUNT=0
FAIL_COUNT=0

#-------------------------------------------------------------------------------
# 検証結果を記録
#-------------------------------------------------------------------------------
check_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"

    if [[ "$result" == "pass" ]]; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        [[ -n "$message" ]] && echo "      $message"
        ((PASS_COUNT++))
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        [[ -n "$message" ]] && echo "      $message"
        ((FAIL_COUNT++))
    fi
}

#-------------------------------------------------------------------------------
# VMの状態を検証
#-------------------------------------------------------------------------------
verify_vm_status() {
    log_step "VMの状態を検証中..."

    # VMIDの存在チェック
    if qm status $VMID &> /dev/null; then
        check_result "VMID $VMID の存在確認" "pass"
    else
        check_result "VMID $VMID の存在確認" "fail" "VMが見つかりません"
        return 1
    fi

    # VMの実行状態チェック
    local status=$(qm status $VMID | awk '{print $2}')
    if [[ "$status" == "running" ]]; then
        check_result "VMの実行状態" "pass" "ステータス: $status"
    else
        check_result "VMの実行状態" "fail" "ステータス: $status (runningではありません)"
    fi
}

#-------------------------------------------------------------------------------
# ネットワーク接続を検証
#-------------------------------------------------------------------------------
verify_network() {
    log_step "ネットワーク接続を検証中..."

    # Pingで到達確認
    if ping -c 3 -W 3 "$VM_IP" &> /dev/null; then
        local ping_time=$(ping -c 1 -W 3 "$VM_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
        check_result "ネットワーク到達性（Ping）" "pass" "応答時間: ${ping_time}ms"
    else
        check_result "ネットワーク到達性（Ping）" "fail" "$VM_IP に到達できません"
        return 1
    fi

    # SSHポート確認
    if timeout 3 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then
        check_result "SSHポート（22）の稼働" "pass"
    else
        check_result "SSHポート（22）の稼働" "fail" "SSHポートに到達できません"
    fi
}

#-------------------------------------------------------------------------------
# SSH接続を検証
#-------------------------------------------------------------------------------
verify_ssh() {
    log_step "SSH接続を検証中..."

    # SSHバージョンチェック
    local ssh_version=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'echo "SSH接続成功"' 2>/dev/null || echo "")

    if [[ "$ssh_version" == "SSH接続成功" ]]; then
        check_result "SSH接続（鍵認証）" "pass" "SSHキーで接続できました"
    else
        # SSHキーがない場合はパスワード認証を試す
        log_info "SSHキーでの接続に失敗しました。パスワード認証を試します..."
        check_result "SSH接続（鍵認証）" "fail" "SSHキーが設定されていません"
    fi
}

#-------------------------------------------------------------------------------
# OS内の設定を検証
#-------------------------------------------------------------------------------
verify_os_settings() {
    log_step "OS内の設定を検証中..."

    # IPアドレス確認
    local actual_ip=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'hostname -I' 2>/dev/null | awk '{print $1}')

    if [[ "$actual_ip" == "$VM_IP" ]]; then
        check_result "固定IPの設定" "pass" "IP: $actual_ip"
    else
        check_result "固定IPの設定" "fail" "期待値: $VM_IP, 実際: $actual_ip"
    fi

    # SSHサーバーの状態確認
    local ssh_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'systemctl is-active ssh 2>/dev/null || echo "unknown"' 2>/dev/null)

    if [[ "$ssh_status" == "active" ]]; then
        check_result "SSHサーバーの状態" "pass"
    else
        check_result "SSHサーバーの状態" "fail" "状態: $ssh_status"
    fi

    # QEMU Guest Agentの状態確認
    local guest_agent_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'systemctl is-active qemu-guest-agent 2>/dev/null || echo "unknown"' 2>/dev/null)

    if [[ "$guest_agent_status" == "active" ]]; then
        check_result "QEMU Guest Agentの状態" "pass"
    else
        check_result "QEMU Guest Agentの状態" "warn" "状態: $guest_agent_status (オプション)"
    fi
}

#-------------------------------------------------------------------------------
# ディスクとメモリの使用量を確認
#-------------------------------------------------------------------------------
verify_resources() {
    log_step "リソース使用量を確認中..."

    # ディスク使用量
    local disk_usage=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'df -h / | tail -1 | awk "{print \$5}"' 2>/dev/null)

    if [[ -n "$disk_usage" ]]; then
        check_result "ディスク使用量の取得" "pass" "使用率: $disk_usage"
    else
        check_result "ディスク使用量の取得" "fail"
    fi

    # メモリ使用量
    local mem_usage=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" -o BatchMode=yes 'free -h | grep Mem | awk "{print \$3 \"/\"\$2}"' 2>/dev/null)

    if [[ -n "$mem_usage" ]]; then
        check_result "メモリ使用量の取得" "pass" "使用量: $mem_usage"
    else
        check_result "メモリ使用量の取得" "fail"
    fi
}

#-------------------------------------------------------------------------------
# 最終結果を表示
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  検証結果サマリー${NC}"
    echo "==============================================================================="
    echo ""
    echo "【ターゲット】"
    echo "  VMID:   $VMID"
    echo "  IPアドレス: $VM_IP"
    echo "  ユーザー名:  $VM_USER"
    echo ""
    echo "【結果】"
    echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
    echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ すべての検証に合格しました！${NC}"
        echo ""
        echo "【次のステップ】"
        echo "  SSHで接続:"
        echo "    ssh $VM_USER@$VM_IP"
        echo ""
        return 0
    else
        echo -e "${RED}✗ 一部の検証に失敗しました${NC}"
        echo ""
        echo "【推奨アクション】"
        if [[ $FAIL_COUNT -gt 0 ]]; then
            echo "  - ネットワーク設定を確認してください"
            echo "  - SSHキー設定を実行してください:"
            echo "    ./setup-ssh-keys.sh $VMID $VM_IP $VM_USER"
        fi
        echo ""
        return 1
    fi
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VM - セットアップ検証${NC}"
    echo "==============================================================================="
    echo ""

    verify_vm_status
    verify_network
    verify_ssh

    # SSHが接続できる場合のみOS内の検証を実行
    if ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
        verify_os_settings
        verify_resources
    fi

    show_summary
}

main "$@"
