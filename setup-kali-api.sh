#!/bin/bash
#===============================================================================
# Proxmox VE API - Kali Linux 自動セットアップスクリプト
# 
# Proxmox REST APIを使用してリモートからVMを作成します
# 事前にAPI Token または ユーザー認証情報が必要です
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 設定変数
#-------------------------------------------------------------------------------
# Proxmox接続設定
PROXMOX_HOST="192.168.0.147"
PROXMOX_PORT="8006"
PROXMOX_NODE="pve"            # ノード名（デフォルト: pve）

# 認証設定（いずれかを設定）
# 方法1: APIトークン（推奨）
API_TOKEN_ID=""               # 例: "root@pam!mytoken"
API_TOKEN_SECRET=""           # トークンシークレット

# 方法2: ユーザー認証
PROXMOX_USER="root@pam"
PROXMOX_PASS=""               # パスワード（セキュリティ上、入力プロンプト推奨）

# VM設定
VMID="200"
VM_NAME="kali-linux"
VM_MEMORY="4096"
VM_CORES="2"
VM_SOCKETS="1"
DISK_SIZE="50"                # GB
STORAGE="local-lvm"
ISO_STORAGE="local"
BRIDGE="vmbr0"

# ネットワーク設定（固定IP - OS内で設定必要）
STATIC_IP="192.168.0.200"
GATEWAY="192.168.0.1"
NETMASK="24"
DNS_SERVER="8.8.8.8"

# Kali Linux ISO
KALI_VERSION="2024.4"
ISO_FILE="kali-linux-${KALI_VERSION}-installer-amd64.iso"

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#-------------------------------------------------------------------------------
# 依存関係チェック
#-------------------------------------------------------------------------------
check_dependencies() {
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd がインストールされていません"
            exit 1
        fi
    done
}

#-------------------------------------------------------------------------------
# 認証
#-------------------------------------------------------------------------------
AUTH_HEADER=""

authenticate() {
    log_info "Proxmoxに認証中..."
    
    # APIトークンが設定されている場合
    if [[ -n "$API_TOKEN_ID" && -n "$API_TOKEN_SECRET" ]]; then
        AUTH_HEADER="Authorization: PVEAPIToken=${API_TOKEN_ID}=${API_TOKEN_SECRET}"
        log_success "APIトークン認証を使用"
        return 0
    fi
    
    # パスワード認証
    if [[ -z "$PROXMOX_PASS" ]]; then
        echo -n "Proxmoxパスワードを入力: "
        read -s PROXMOX_PASS
        echo ""
    fi
    
    local response
    response=$(curl -s -k -d "username=${PROXMOX_USER}&password=${PROXMOX_PASS}" \
        "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json/access/ticket")
    
    TICKET=$(echo "$response" | jq -r '.data.ticket')
    CSRF_TOKEN=$(echo "$response" | jq -r '.data.CSRFPreventionToken')
    
    if [[ "$TICKET" == "null" || -z "$TICKET" ]]; then
        log_error "認証に失敗しました"
        echo "$response"
        exit 1
    fi
    
    AUTH_HEADER="Cookie: PVEAuthCookie=${TICKET}"
    CSRF_HEADER="CSRFPreventionToken: ${CSRF_TOKEN}"
    
    log_success "認証成功"
}

#-------------------------------------------------------------------------------
# API呼び出しヘルパー
#-------------------------------------------------------------------------------
api_get() {
    local endpoint="$1"
    
    if [[ -n "$CSRF_HEADER" ]]; then
        curl -s -k -H "$AUTH_HEADER" -H "$CSRF_HEADER" \
            "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json${endpoint}"
    else
        curl -s -k -H "$AUTH_HEADER" \
            "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json${endpoint}"
    fi
}

api_post() {
    local endpoint="$1"
    shift
    local data="$@"
    
    if [[ -n "$CSRF_HEADER" ]]; then
        curl -s -k -X POST -H "$AUTH_HEADER" -H "$CSRF_HEADER" \
            -d "$data" \
            "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json${endpoint}"
    else
        curl -s -k -X POST -H "$AUTH_HEADER" \
            -d "$data" \
            "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json${endpoint}"
    fi
}

#-------------------------------------------------------------------------------
# VMIDチェック
#-------------------------------------------------------------------------------
check_vmid() {
    log_info "VMID $VMID の使用状況を確認中..."
    
    local response
    response=$(api_get "/cluster/resources?type=vm")
    
    if echo "$response" | jq -e ".data[] | select(.vmid == $VMID)" > /dev/null 2>&1; then
        log_error "VMID $VMID は既に使用されています"
        exit 1
    fi
    
    log_success "VMID $VMID は使用可能です"
}

#-------------------------------------------------------------------------------
# ISOファイル確認
#-------------------------------------------------------------------------------
check_iso() {
    log_info "ISOファイルの存在を確認中..."
    
    local response
    response=$(api_get "/nodes/${PROXMOX_NODE}/storage/${ISO_STORAGE}/content?content=iso")
    
    if echo "$response" | jq -e ".data[] | select(.volid | contains(\"${ISO_FILE}\"))" > /dev/null 2>&1; then
        log_success "ISOファイルが見つかりました: $ISO_FILE"
        return 0
    fi
    
    log_warning "ISOファイルが見つかりません: $ISO_FILE"
    log_info "Proxmox WebUIまたはSSHでISOをダウンロードしてください:"
    echo ""
    echo "  # SSH接続後、以下を実行:"
    echo "  cd /var/lib/vz/template/iso/"
    echo "  wget https://cdimage.kali.org/kali-${KALI_VERSION}/kali-linux-${KALI_VERSION}-installer-amd64.iso"
    echo ""
    
    read -p "ISOのダウンロードが完了したら Enter を押してください..."
}

#-------------------------------------------------------------------------------
# VM作成
#-------------------------------------------------------------------------------
create_vm() {
    log_info "VM (VMID: $VMID) を作成中..."
    
    local params="vmid=${VMID}"
    params+="&name=${VM_NAME}"
    params+="&memory=${VM_MEMORY}"
    params+="&cores=${VM_CORES}"
    params+="&sockets=${VM_SOCKETS}"
    params+="&cpu=host"
    params+="&ostype=l26"
    params+="&bios=ovmf"
    params+="&machine=q35"
    params+="&agent=enabled=1"
    params+="&net0=virtio,bridge=${BRIDGE}"
    params+="&scsi0=${STORAGE}:${DISK_SIZE}"
    params+="&scsihw=virtio-scsi-pci"
    params+="&ide2=${ISO_STORAGE}:iso/${ISO_FILE},media=cdrom"
    params+="&efidisk0=${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=0"
    params+="&boot=order=ide2;scsi0"
    params+="&vga=qxl"
    
    local response
    response=$(api_post "/nodes/${PROXMOX_NODE}/qemu" "$params")
    
    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        log_success "VM作成タスク開始"
        
        # タスク完了を待機
        local upid
        upid=$(echo "$response" | jq -r '.data')
        wait_for_task "$upid"
    else
        log_error "VM作成に失敗しました"
        echo "$response" | jq .
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# タスク完了待機
#-------------------------------------------------------------------------------
wait_for_task() {
    local upid="$1"
    local encoded_upid=$(echo -n "$upid" | jq -sRr @uri)
    
    log_info "タスク完了を待機中..."
    
    while true; do
        local status
        status=$(api_get "/nodes/${PROXMOX_NODE}/tasks/${encoded_upid}/status")
        
        local task_status
        task_status=$(echo "$status" | jq -r '.data.status')
        
        if [[ "$task_status" == "stopped" ]]; then
            local exitstatus
            exitstatus=$(echo "$status" | jq -r '.data.exitstatus')
            
            if [[ "$exitstatus" == "OK" ]]; then
                log_success "タスク完了"
                return 0
            else
                log_error "タスク失敗: $exitstatus"
                return 1
            fi
        fi
        
        sleep 2
    done
}

#-------------------------------------------------------------------------------
# VM起動（オプション）
#-------------------------------------------------------------------------------
start_vm() {
    read -p "VMを今すぐ起動しますか？ (y/N): " answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log_info "VMを起動中..."
        
        local response
        response=$(api_post "/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/start")
        
        if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
            log_success "VM起動コマンド送信完了"
        else
            log_warning "VM起動に問題が発生した可能性があります"
        fi
    fi
}

#-------------------------------------------------------------------------------
# 設定サマリー表示
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}Kali Linux VM セットアップ完了${NC}"
    echo "==============================================================================="
    echo ""
    echo "【VM情報】"
    echo "  VMID:         $VMID"
    echo "  名前:         $VM_NAME"
    echo "  メモリ:       ${VM_MEMORY}MB"
    echo "  CPU:          ${VM_CORES}コア x ${VM_SOCKETS}ソケット"
    echo "  ディスク:     ${DISK_SIZE}GB"
    echo ""
    echo "【アクセス方法】"
    echo "  WebUI: https://${PROXMOX_HOST}:${PROXMOX_PORT}"
    echo "  VNC:   VM → コンソール から接続"
    echo ""
    echo "【固定IP設定（Kaliインストール後）】"
    echo "  IP:           ${STATIC_IP}/${NETMASK}"
    echo "  ゲートウェイ: $GATEWAY"
    echo "  DNS:          $DNS_SERVER"
    echo ""
    echo "【Kali Linux内での固定IP設定コマンド】"
    echo "  # NetworkManagerを使用する場合:"
    echo "  nmcli con add con-name static-eth0 ifname eth0 type ethernet \\"
    echo "    ipv4.method manual \\"
    echo "    ipv4.addresses ${STATIC_IP}/${NETMASK} \\"
    echo "    ipv4.gateway ${GATEWAY} \\"
    echo "    ipv4.dns ${DNS_SERVER}"
    echo "  nmcli con up static-eth0"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo "  Proxmox VE API - Kali Linux 自動セットアップ"
    echo "==============================================================================="
    echo ""
    
    check_dependencies
    authenticate
    check_vmid
    check_iso
    create_vm
    start_vm
    show_summary
}

main "$@"
