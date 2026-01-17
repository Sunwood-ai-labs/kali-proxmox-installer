#!/bin/bash
#===============================================================================
# Proxmox VE - Kali Linux 自動セットアップスクリプト
# 
# 使用方法:
#   1. このスクリプトをProxmoxホストにコピー
#   2. 変数を環境に合わせて編集
#   3. chmod +x setup-kali-proxmox.sh && ./setup-kali-proxmox.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 設定変数（必要に応じて変更してください）
#-------------------------------------------------------------------------------

# Proxmox設定
PROXMOX_HOST="192.168.0.147"
PROXMOX_PORT="8006"
STORAGE="local-lvm"           # VMディスク用ストレージ
ISO_STORAGE="local"           # ISOイメージ用ストレージ

# VM設定
VMID="200"                    # VM ID（空いているIDを指定）
VM_NAME="kali-linux"
VM_MEMORY="4096"              # メモリ（MB）
VM_CORES="2"                  # CPUコア数
VM_SOCKETS="1"                # CPUソケット数
DISK_SIZE="50G"               # ディスクサイズ

# ネットワーク設定（固定IP）
BRIDGE="vmbr0"                # ネットワークブリッジ
STATIC_IP="192.168.0.200"     # 固定IPアドレス
GATEWAY="192.168.0.1"         # ゲートウェイ
NETMASK="24"                  # サブネットマスク
DNS_SERVER="8.8.8.8"          # DNSサーバー

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

#-------------------------------------------------------------------------------
# 前提条件チェック
#-------------------------------------------------------------------------------
check_prerequisites() {
    log_info "前提条件をチェック中..."
    
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
    
    # VMIDの重複チェック
    if qm status $VMID &> /dev/null; then
        log_error "VMID $VMID は既に使用されています。別のIDを指定してください"
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

#-------------------------------------------------------------------------------
# Kali Linux ISOダウンロード
#-------------------------------------------------------------------------------
download_iso() {
    local iso_path="/var/lib/vz/template/iso/${ISO_FILE}"
    
    if [[ -f "$iso_path" ]]; then
        log_info "ISOファイルは既に存在します: $iso_path"
        return 0
    fi
    
    log_info "Kali Linux ISOをダウンロード中..."
    log_info "URL: $KALI_ISO_URL"
    
    wget -c "$KALI_ISO_URL" -O "$iso_path" || {
        log_error "ISOダウンロードに失敗しました"
        exit 1
    }
    
    log_success "ISOダウンロード完了: $iso_path"
}

#-------------------------------------------------------------------------------
# VM作成
#-------------------------------------------------------------------------------
create_vm() {
    log_info "VM (VMID: $VMID) を作成中..."
    
    # VM作成
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
    
    log_success "VM作成完了"
}

#-------------------------------------------------------------------------------
# EFIディスク追加
#-------------------------------------------------------------------------------
add_efi_disk() {
    log_info "EFIディスクを追加中..."
    
    qm set $VMID --efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=0
    
    log_success "EFIディスク追加完了"
}

#-------------------------------------------------------------------------------
# ストレージ設定
#-------------------------------------------------------------------------------
configure_storage() {
    log_info "ストレージを設定中..."

    # ディスクサイズから単位を削除（50G -> 50）
    DISK_NUM=$(echo $DISK_SIZE | sed 's/[^0-9]//g')

    # メインディスク追加
    qm set $VMID --scsi0 ${STORAGE}:${DISK_NUM}
    
    # SCSIコントローラー設定
    qm set $VMID --scsihw virtio-scsi-pci
    
    # ISOをCDドライブにマウント
    qm set $VMID --ide2 ${ISO_STORAGE}:iso/${ISO_FILE},media=cdrom
    
    # ブート順序設定
    qm set $VMID --boot order='ide2;scsi0'
    
    log_success "ストレージ設定完了"
}

#-------------------------------------------------------------------------------
# ネットワーク設定
#-------------------------------------------------------------------------------
configure_network() {
    log_info "ネットワークを設定中..."
    
    # ネットワークインターフェース追加
    qm set $VMID --net0 virtio,bridge=${BRIDGE}
    
    log_success "ネットワーク設定完了"
    log_info "固定IP設定: ${STATIC_IP}/${NETMASK}"
}

#-------------------------------------------------------------------------------
# ディスプレイ設定
#-------------------------------------------------------------------------------
configure_display() {
    log_info "ディスプレイを設定中..."
    
    qm set $VMID --vga qxl
    
    log_success "ディスプレイ設定完了"
}

#-------------------------------------------------------------------------------
# Cloud-Init設定（オプション）
#-------------------------------------------------------------------------------
configure_cloudinit() {
    log_info "Cloud-Init設定をスキップ（Kali LinuxはCloud-Init非対応のため）"
    log_warning "固定IPはOS内部で手動設定が必要です"
}

#-------------------------------------------------------------------------------
# 固定IP設定用スクリプト生成
#-------------------------------------------------------------------------------
generate_network_config() {
    log_info "Kali Linux内での固定IP設定スクリプトを生成中..."
    
    cat > /tmp/kali-network-config.sh << 'NETWORK_EOF'
#!/bin/bash
#===============================================================================
# Kali Linux 固定IP設定スクリプト
# Kali Linuxインストール後、このスクリプトを実行してください
#===============================================================================

STATIC_IP="__STATIC_IP__"
GATEWAY="__GATEWAY__"
NETMASK="__NETMASK__"
DNS_SERVER="__DNS_SERVER__"

# NetworkManagerを使用した設定
cat > /etc/NetworkManager/system-connections/static-eth0.nmconnection << EOF
[connection]
id=static-eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=manual
addresses=${STATIC_IP}/${NETMASK}
gateway=${GATEWAY}
dns=${DNS_SERVER}

[ipv6]
method=disabled
EOF

chmod 600 /etc/NetworkManager/system-connections/static-eth0.nmconnection

# NetworkManager再起動
systemctl restart NetworkManager

echo "固定IP設定完了: ${STATIC_IP}/${NETMASK}"
echo "ゲートウェイ: ${GATEWAY}"
echo "DNS: ${DNS_SERVER}"
NETWORK_EOF

    # 変数を置換
    sed -i "s|__STATIC_IP__|${STATIC_IP}|g" /tmp/kali-network-config.sh
    sed -i "s|__GATEWAY__|${GATEWAY}|g" /tmp/kali-network-config.sh
    sed -i "s|__NETMASK__|${NETMASK}|g" /tmp/kali-network-config.sh
    sed -i "s|__DNS_SERVER__|${DNS_SERVER}|g" /tmp/kali-network-config.sh
    
    chmod +x /tmp/kali-network-config.sh
    
    log_success "ネットワーク設定スクリプト生成完了: /tmp/kali-network-config.sh"
}

#-------------------------------------------------------------------------------
# /etc/network/interfaces用設定生成
#-------------------------------------------------------------------------------
generate_interfaces_config() {
    cat > /tmp/kali-interfaces << EOF
# Kali Linux /etc/network/interfaces 設定
# このファイルを /etc/network/interfaces にコピーしてください

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address ${STATIC_IP}
    netmask 255.255.255.0
    gateway ${GATEWAY}
    dns-nameservers ${DNS_SERVER}
EOF

    log_info "interfaces設定ファイル生成: /tmp/kali-interfaces"
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
    echo "  ディスク:     $DISK_SIZE"
    echo ""
    echo "【ネットワーク設定（OS内で設定が必要）】"
    echo "  固定IP:       ${STATIC_IP}/${NETMASK}"
    echo "  ゲートウェイ: $GATEWAY"
    echo "  DNS:          $DNS_SERVER"
    echo ""
    echo "【次のステップ】"
    echo "  1. VMを起動:  qm start $VMID"
    echo "  2. Proxmox WebUI (https://${PROXMOX_HOST}:${PROXMOX_PORT}) でコンソールを開く"
    echo "  3. Kali Linuxをインストール"
    echo "  4. インストール後、以下のいずれかで固定IPを設定:"
    echo ""
    echo "     方法A: NetworkManager使用（推奨）"
    echo "       /tmp/kali-network-config.sh をKali内にコピーして実行"
    echo ""
    echo "     方法B: /etc/network/interfaces 使用"
    echo "       /tmp/kali-interfaces の内容を /etc/network/interfaces にコピー"
    echo ""
    echo "  5. インストール完了後、CDROMを取り外す:"
    echo "     qm set $VMID --ide2 none"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo "  Proxmox VE - Kali Linux 自動セットアップ"
    echo "==============================================================================="
    echo ""
    
    check_prerequisites
    download_iso
    create_vm
    add_efi_disk
    configure_storage
    configure_network
    configure_display
    configure_cloudinit
    generate_network_config
    generate_interfaces_config
    show_summary
}

# スクリプト実行
main "$@"
