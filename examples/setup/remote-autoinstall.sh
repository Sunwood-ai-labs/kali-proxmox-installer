#!/bin/bash
#===============================================================================
# Proxmox リモート自動インストール ラッパースクリプト
#
# ローカルマシンからProxmoxにSSH接続してKali Linuxを完全自動インストール
#===============================================================================

#-------------------------------------------------------------------------------
# 設定変数
#-------------------------------------------------------------------------------
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.147}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PORT="${PROXMOX_PORT:-22}"
PROXMOX_SSH_HOST="${PROXMOX_SSH_HOST:-proxmox}"  # SSH configのホスト名

SCRIPT_NAME="kali-autoinstall.sh"
SCRIPT_PATH="$(dirname "$0")/${SCRIPT_NAME}"

#-------------------------------------------------------------------------------
# カラー出力
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${CYAN}  Proxmox リモート自動インストール${NC}"
    echo "==============================================================================="
    echo ""

    # スクリプト存在確認
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        log_error "セットアップスクリプトが見つかりません: $SCRIPT_PATH"
        exit 1
    fi

    log_step "前準備"
    log_info "ローカルマシンでHTTPサーバーを起動するための準備..."

    # Python3の確認
    if ! command -v python3 &> /dev/null; then
        log_error "python3が見つかりません。インストールしてください"
        exit 1
    fi
    log_success "Python3: OK"

    # ローカルIPアドレスの取得
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    log_info "ローカルIPアドレス: $LOCAL_IP"

    log_info "Proxmox ($PROXMOX_SSH_HOST) に接続中..."

    # スクリプトをProxmoxにコピー
    log_step "スクリプト転送"
    scp "$SCRIPT_PATH" "${PROXMOX_SSH_HOST}:/tmp/${SCRIPT_NAME}"

    if [[ $? -ne 0 ]]; then
        log_error "スクリプト転送に失敗しました"
        log_info "まず以下を実行してSSH接続を設定してください:"
        echo "  ./setup-proxmox-ssh.sh"
        exit 1
    fi

    log_success "スクリプト転送完了"

    # preseedファイルも転送（事前に作成する場合）
    # 自動生成されるので転送不要

    # リモートで実行
    log_step "自動インストール実行"
    log_info "Proxmox上で自動インストールを開始します..."
    echo ""

    ssh "${PROXMOX_SSH_HOST}" "chmod +x /tmp/${SCRIPT_NAME} && /tmp/${SCRIPT_NAME}"

    if [[ $? -eq 0 ]]; then
        echo ""
        log_success "自動インストールが開始されました"
        echo ""
        echo "【次のステップ】"
        echo "  1. インストール完了まで約10-15分待ちます"
        echo "  2. Proxmox WebUI (https://${PROXMOX_HOST}:8006) で進捗を確認できます"
        echo "  3. 完了後、以下でSSH接続できます:"
        echo "     ssh maki@192.168.0.201"
        echo "     パスワード: kali (要変更)"
        echo ""
    else
        echo ""
        log_error "インストール中にエラーが発生しました"
        exit 1
    fi
}

main "$@"
