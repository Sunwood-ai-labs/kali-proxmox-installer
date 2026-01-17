#!/bin/bash
#===============================================================================
# Proxmox VE - Kali Linux 自動インストール（preseed使用）
#
# preseed設定ファイルを使ってKali Linuxを完全自動インストール
#
# 使用方法:
#   ./kali-autoinstall.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 設定変数
#-------------------------------------------------------------------------------

# Proxmox設定
PROXMOX_HOST="192.168.0.147"
STORAGE="local-lvm"
ISO_STORAGE="local"

# VM設定
VMID="200"
VM_NAME="kali-linux"
VM_MEMORY="4096"
VM_CORES="2"
VM_SOCKETS="1"
DISK_SIZE="50"

# ネットワーク設定
BRIDGE="vmbr0"
STATIC_IP="192.168.0.200"
GATEWAY="192.168.0.1"
NETMASK="255.255.255.0"
DNS_SERVER="8.8.8.8"
HOSTNAME="kali"
DOMAIN="local"

# ユーザー設定
USERNAME="maki"
FULLNAME="Kali User"
PASSWORD="kali"  # 後で変更してください
ROOT_PASSWORD="root"  # 後で変更してください

# Kali Linux ISO
KALI_VERSION="2025.3"
KALI_ISO_URL="https://cdimage.kali.org/kali-${KALI_VERSION}/kali-linux-${KALI_VERSION}-installer-amd64.iso"
ISO_FILE="kali-linux-${KALI_VERSION}-installer-amd64.iso"

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
# preseedファイルを作成
#-------------------------------------------------------------------------------
create_preseed() {
    log_step "preseed設定ファイルを作成中..."

    local preseed_file="/tmp/kali-preseed.cfg"

    cat > "$preseed_file" << 'PRESEED_EOF'
# Kali Linux 自動インストール preseed設定

# ロケール設定
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

# ネットワーク設定
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string __HOSTNAME__
d-i netcfg/get_domain string __DOMAIN__
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/use_autoconfig boolean false
d-i netcfg/get_ipaddress string __STATIC_IP__
d-i netcfg/get_netmask string __NETMASK__
d-i netcfg/get_gateway string __GATEWAY__
d-i netcfg/get_nameservers string __DNS_SERVER__
d-i netcfg/confirm_static boolean true

# ミラー設定
d-i mirror/country string manual
d-i mirror/http/hostname string http.kali.org
d-i mirror/http/directory string /kali
d-i mirror/http/proxy string

# 時間設定
d-i clock-setup/utc boolean true
d-i time/zone string Asia/Tokyo
d-i clock-setup/ntp boolean true

# パーティション設定
d-i partman-auto/method string lvm
d-i partman-auto-lvm/guided_size string max
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman-lvm/confirm boolean true
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-md/confirm boolean true
d-i partman-partitioning/confirm_new_label boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# ベースシステムのインストール
d-i base-installer/kernel/image string linux-image-amd64

# ブートローダー設定
d-i grub-installer/bootdev string default
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true

# インストール完了後のオプション
d-i finish-install/reboot_in_progress note

# パスワード設定
d-i passwd/make-user boolean true
d-i passwd/user-fullname string __FULLNAME__
d-i passwd/username string __USERNAME__
d-i passwd/user-password password __PASSWORD__
d-i passwd/user-password-again password __PASSWORD__
d-i passwd/root-password password __ROOT_PASSWORD__
d-i passwd/root-password-again password __ROOT_PASSWORD__
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# パッケージ選択
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string openssh-server sudo qemu-guest-agent

# インストール中のパッケージアップグレード
d-i pkgsel/upgrade select none

# APT設定
d-i apt-setup/contrib boolean true
d-i apt-setup/use_mirror boolean true
d-i apt-setup/services-select multiselect security

# Popularityコンテスト（不要）
popularity-contest popularity-contest/participate boolean false
PRESEED_EOF

    # 変数を置換
    sed -i "s|__STATIC_IP__|${STATIC_IP}|g" "$preseed_file"
    sed -i "s|__NETMASK__|${NETMASK}|g" "$preseed_file"
    sed -i "s|__GATEWAY__|${GATEWAY}|g" "$preseed_file"
    sed -i "s|__DNS_SERVER__|${DNS_SERVER}|g" "$preseed_file"
    sed -i "s|__HOSTNAME__|${HOSTNAME}|g" "$preseed_file"
    sed -i "s|__DOMAIN__|${DOMAIN}|g" "$preseed_file"
    sed -i "s|__FULLNAME__|${FULLNAME}|g" "$preseed_file"
    sed -i "s|__USERNAME__|${USERNAME}|g" "$preseed_file"
    sed -i "s|__PASSWORD__|${PASSWORD}|g" "$preseed_file"
    sed -i "s|__ROOT_PASSWORD__|${ROOT_PASSWORD}|g" "$preseed_file"

    log_success "preseedファイル作成完了: $preseed_file"
    echo "$preseed_file"
}

#-------------------------------------------------------------------------------
# HTTPサーバーを起動してpreseedを配信
#-------------------------------------------------------------------------------
start_http_server() {
    local preseed_file="$1"

    log_step "HTTPサーバーを起動中..."

    # Pythonで簡易HTTPサーバーを起動
    cd /tmp
    python3 -m http.server 8000 > /dev/null 2>&1 &
    local http_pid=$!

    sleep 2

    if ps -p $http_pid > /dev/null; then
        log_success "HTTPサーバー起動完了 (PID: $http_pid)"
        echo "$http_pid"
    else
        log_error "HTTPサーバーの起動に失敗しました"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# VMを作成して自動インストール開始
#-------------------------------------------------------------------------------
create_autoinstall_vm() {
    local preseed_file="$1"
    local http_pid="$2"

    log_step "VMを作成して自動インストールを開始中..."

    # VM作成
    log_info "VMを作成中..."
    qm create $VMID \
        --name "$VM_NAME" \
        --memory $VM_MEMORY \
        --cores $VM_CORES \
        --sockets $VM_SOCKETS \
        --cpu host \
        --ostype l26 \
        --bios ovmf \
        --machine q35 \
        --agent enabled=1

    # EFIディスク
    log_info "EFIディスクを追加中..."
    qm set $VMID --efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=0

    # ストレージ
    log_info "ストレージを設定中..."
    local disk_num=$(echo $DISK_SIZE | sed 's/[^0-9]//g')
    qm set $VMID --scsi0 ${STORAGE}:${disk_num}
    qm set $VMID --scsihw virtio-scsi-pci
    qm set $VMID --ide2 ${ISO_STORAGE}:iso/${ISO_FILE},media=cdrom
    qm set $VMID --boot order='ide2;scsi0'

    # ネットワーク
    log_info "ネットワークを設定中..."
    qm set $VMID --net0 virtio,bridge=${BRIDGE}

    # ディスプレイ
    log_info "ディスプレイを設定中..."
    qm set $VMID --vga serial0

    # シリアルコンソール
    qm set $VMID --serial0 socket

    # 起動パラメータにpreseedを指定
    local local_ip=$(hostname -I | awk '{print $1}')
    log_info "起動パラメータを設定中... (preseed: http://${local_ip}:8000/$(basename $preseed_file))"

    qm set $VMID --args "auto=true priority=critical url=http://${local_ip}:8000/$(basename $preseed_file)"

    # VMを起動
    log_info "VMを起動中..."
    qm start $VMID

    log_success "VM起動完了"
    log_info "自動インストールが開始されました"
    log_info "Proxmox WebUI (https://${PROXMOX_HOST}:8006) でコンソールを開いて進捗を確認できます"

    # HTTPサーバーはインストール完了後に停止
    sleep 30
    log_info "HTTPサーバーを停止中..."
    kill $http_pid 2>/dev/null || true
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox VE - Kali Linux 自動インストール${NC}"
    echo "==============================================================================="
    echo ""

    log_warning "このスクリプトはKali Linuxを完全自動インストールします"
    log_warning "既存のVMID $VMID は上書きされます"
    echo ""

    # 既存VMのチェック
    if qm status $VMID &> /dev/null; then
        log_error "VMID $VMID は既に存在します"
        read -p "既存のVMを削除して続行しますか？ [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "VMを削除中..."
            qm destroy $VMID --destroy-unreferenced-disks 1 --purge 1
        else
            log_info "キャンセルしました"
            exit 0
        fi
    fi

    # preseedファイル作成
    local preseed_file=$(create_preseed)

    # HTTPサーバー起動
    local http_pid=$(start_http_server)

    # VM作成と自動インストール
    create_autoinstall_vm "$preseed_file" "$http_pid"

    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}自動インストール開始${NC}"
    echo "==============================================================================="
    echo ""
    echo "【VM情報】"
    echo "  VMID:   $VMID"
    echo "  名前:    $VM_NAME"
    echo "  メモリ:   ${VM_MEMORY}MB"
    echo "  CPU:    ${VM_CORES}コア"
    echo "  ディスク:  ${DISK_SIZE}GB"
    echo ""
    echo "【ネットワーク設定】"
    echo "  固定IP:    ${STATIC_IP}"
    echo "  ゲートウェイ: ${GATEWAY}"
    echo "  DNS:     ${DNS_SERVER}"
    echo ""
    echo "【ユーザー設定】"
    echo "  ユーザー名:  $USERNAME"
    echo "  パスワード:  $PASSWORD (要変更)"
    echo "  rootパスワード: $ROOT_PASSWORD (要変更)"
    echo ""
    echo "【次のステップ】"
    echo "  1. インストール完了まで約10-15分待ちます"
    echo "  2. 完了後、以下で接続できます:"
    echo "     ssh ${USERNAME}@${STATIC_IP}"
    echo "  3. パスワードを変更してください"
    echo ""
    echo "==============================================================================="
    echo ""
    log_success "セットアップ完了！"
}

main "$@"
