#!/bin/bash
#===============================================================================
# Proxmox VE - VM ディスク拡張スクリプト
#
# 使用方法:
#   ./resize-vm-disk.sh <VMID> <ディスク> <サイズ>
#
# 例:
#   ./resize-vm-disk.sh 200 scsi0 +50G    # 50GB追加
#   ./resize-vm-disk.sh 200 scsi0 100G    # 100GBに指定
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
if [[ $# -ne 3 ]]; then
    log_error "引数が不正です"
    echo ""
    echo "使用方法:"
    echo "  $0 <VMID> <ディスク> <サイズ>"
    echo ""
    echo "例:"
    echo "  $0 200 scsi0 +50G     # 50GB追加"
    echo "  $0 200 scsi0 100G     # 100GBに指定"
    echo ""
    exit 1
fi

VMID="$1"
DISK="$2"
SIZE="$3"

#-------------------------------------------------------------------------------
# 前提条件チェック
#-------------------------------------------------------------------------------
check_prerequisites() {
    log_step "前提条件をチェック中..."

    # rootユーザーチェック
    if [[ $EUID -ne 0 ]]; then
        log_error "このスクリプトはroot権限で実行してください"
        exit 1
    fi

    # Proxmox環境チェック
    if ! command -v qm &> /dev/null; then
        log_error "qmコマンドが見つかりません。Proxmox VE環境で実行してください"
        exit 1
    fi

    # VMIDの存在チェック
    if ! qm status $VMID &> /dev/null; then
        log_error "VMID $VMID は存在しません"
        exit 1
    fi

    log_success "前提条件チェック完了"
}

#-------------------------------------------------------------------------------
# 現在のディスク情報を表示
#-------------------------------------------------------------------------------
show_current_disk_info() {
    log_step "現在のディスク情報"

    echo ""
    qm config $VMID | grep -E "^${DISK}:" || true
    echo ""

    # ディスクの実際のサイズを取得
    local disk_config=$(qm config $VMID | grep "^${DISK}:")
    if [[ -n "$disk_config" ]]; then
        log_info "現在の設定: $disk_config"
    fi
}

#-------------------------------------------------------------------------------
# VMの状態を確認
#-------------------------------------------------------------------------------
check_vm_status() {
    local status=$(qm status $VMID | awk '{print $2}')
    echo "$status"
}

#-------------------------------------------------------------------------------
# ディスクサイズの解析
#-------------------------------------------------------------------------------
parse_size() {
    local size="$1"

    # サイズが+で始まる場合（追加サイズ）
    if [[ "$size" == +* ]]; then
        echo "add"
    else
        echo "set"
    fi
}

#-------------------------------------------------------------------------------
# ディスクを拡張
#-------------------------------------------------------------------------------
resize_disk() {
    log_step "ディスクを拡張中..."

    local size_type=$(parse_size "$SIZE")

    if [[ "$size_type" == "add" ]]; then
        log_info "サイズ追加モード: ${SIZE} を追加"
    else
        log_info "サイズ指定モード: ${SIZE} に設定"
    fi

    # 確認プロンプト
    echo ""
    read -p "$(echo -e ${YELLOW}続行しますか？ [y/N]: ${NC})" -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "キャンセルしました"
        exit 0
    fi

    # ディスク拡張実行
    log_info "qm resize $VMID $DISK $SIZE を実行中..."

    if qm resize $VMID $DISK $SIZE; then
        log_success "ディスク拡張完了"
    else
        log_error "ディスク拡張に失敗しました"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 拡張後の情報を表示
#-------------------------------------------------------------------------------
show_resized_info() {
    log_step "拡張後のディスク情報"

    echo ""
    qm config $VMID | grep -E "^${DISK}:" || true
    echo ""
}

#-------------------------------------------------------------------------------
# OS内での拡張手順を表示
#-------------------------------------------------------------------------------
show_os_resize_instructions() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}OS内でのパーティション拡張手順${NC}"
    echo "==============================================================================="
    echo ""
    echo "VM内のOSで以下のコマンドを実行して、パーティションとファイルシステムを拡張してください："
    echo ""
    echo -e "${GREEN}# 方法1: 自動拡張（推奨）${NC}"
    echo "sudo growpart /dev/sda 1           # パーティション1を拡張"
    echo "sudo resize2fs /dev/sda1           # ファイルシステムを拡張（ext4の場合）"
    echo ""
    echo -e "${GREEN}# 方法2: partedを使用${NC}"
    echo "sudo parted /dev/sda"
    echo "  (parted) print"
    echo "  (parted) resizepart"
    echo "  (parted) quit"
    echo "sudo resize2fs /dev/sda1"
    echo ""
    echo -e "${GREEN}# 方法3: LVMを使用している場合${NC}"
    echo "sudo pvresize /dev/sda2"
    echo "sudo lvextend -l +100%FREE /dev/mapper/vg--root-root"
    echo "sudo resize2fs /dev/mapper/vg--root-root"
    echo ""
    echo -e "${YELLOW}注意: デバイス名（/dev/sdaなど）は環境によって異なる場合があります${NC}"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VE - VM ディスク拡張${NC}"
    echo "==============================================================================="
    echo ""

    check_prerequisites
    show_current_disk_info

    local vm_status=$(check_vm_status)
    if [[ "$vm_status" == "running" ]]; then
        log_warning "VMは実行中です。オンラインで拡張します"
    else
        log_info "VMは停止中です"
    fi

    resize_disk
    show_resized_info
    show_os_resize_instructions

    echo ""
    log_success "処理完了！"
    echo ""
}

# スクリプト実行
main "$@"
