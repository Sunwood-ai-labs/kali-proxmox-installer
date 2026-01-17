<div align="center">
  <img src="assets/header.jpg" alt="Kali Prox Installer Header" width="100%">
</div>

<div align="center">
  [![Shell Script](https://img.shields.io/badge/Shell-Script-black?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
  [![GitHub](https://img.shields.io/badge/GitHub-kali--proxmox--installer-lightgrey?style=flat-square&logo=github)](https://github.com/Sunwood-ai-labs/kali-proxmox-installer)
</div>

# Proxmox VE - Kali Linux 自動セットアップスクリプト

<div align="center">
  Proxmox VE上にKali Linux VMを自動作成するbashスクリプト集です。
</div>

## 特徴

- 🚀 **ワンコマンドでVM作成** - ISOダウンロードからVM設定まで完全自動化
- ⚙️ **柔軟な実行方法** - 直接実行/SSH/API、3つの方式に対応
- 🔧 **VirtIO最適化** - パフォーマンス最大化のための設定済み
- 🌐 **固定IP対応** - セットアップ後のネットワーク設定スクリプト生成

## 📁 ファイル一覧

| ファイル | 説明 |
|----------|------|
| `setup-kali-proxmox.sh` | メインスクリプト（Proxmoxホストで直接実行） |
| `remote-setup.sh` | リモートからSSH経由で実行するラッパー |
| `setup-kali-api.sh` | Proxmox REST API版（SSHなしで実行可能） |

## 📋 前提条件

- Proxmox VEがインストールされていること
- root権限またはsudo権限があること
- インターネット接続（ISOダウンロード用）

### API版を使用する場合
- `curl` および `jq` がインストールされていること
- Proxmox APIトークン（またはパスワード）

## 🚀 使い方

### 方法1: Proxmoxホストで直接実行（推奨）

```bash
# 1. スクリプトをProxmoxにコピー
scp setup-kali-proxmox.sh root@192.168.0.147:/tmp/

# 2. SSH接続
ssh root@192.168.0.147

# 3. 実行
chmod +x /tmp/setup-kali-proxmox.sh
/tmp/setup-kali-proxmox.sh
```

### 方法2: ローカルからリモート実行

```bash
# setup-kali-proxmox.sh と remote-setup.sh を同じディレクトリに配置
chmod +x remote-setup.sh
./remote-setup.sh
```

### 方法3: API経由で実行

```bash
# APIトークンまたはパスワードを設定してから実行
chmod +x setup-kali-api.sh
./setup-kali-api.sh
```

## ⚙️ 設定変数

スクリプト内の以下の変数をお使いの環境に合わせて編集してください：

```bash
# Proxmox設定
PROXMOX_HOST="192.168.0.147"
STORAGE="local-lvm"

# VM設定
VMID="200"                    # VMのID
VM_NAME="kali-linux"
VM_MEMORY="4096"              # メモリ (MB)
VM_CORES="2"                  # CPUコア数
DISK_SIZE="50G"               # ディスクサイズ

# ネットワーク設定（固定IP）
STATIC_IP="192.168.0.200"     # 固定IPアドレス
GATEWAY="192.168.0.1"         # ゲートウェイ
NETMASK="24"                  # サブネットマスク
DNS_SERVER="8.8.8.8"          # DNSサーバー
```

## 📝 セットアップ後の作業

### 1. Kali Linuxをインストール

1. Proxmox WebUI (https://192.168.0.147:8006) にアクセス
2. 作成したVM → コンソール を開く
3. Kali Linuxのインストールを完了

### 2. 固定IPを設定

インストール完了後、Kali Linux内で以下を実行：

#### NetworkManagerを使用（推奨）

```bash
# 接続を追加
nmcli con add con-name static-eth0 ifname eth0 type ethernet \
  ipv4.method manual \
  ipv4.addresses 192.168.0.200/24 \
  ipv4.gateway 192.168.0.1 \
  ipv4.dns 8.8.8.8

# 接続を有効化
nmcli con up static-eth0
```

#### または /etc/network/interfaces を編集

```bash
sudo nano /etc/network/interfaces
```

以下を追加：

```
auto eth0
iface eth0 inet static
    address 192.168.0.200
    netmask 255.255.255.0
    gateway 192.168.0.1
    dns-nameservers 8.8.8.8
```

ネットワーク再起動：

```bash
sudo systemctl restart networking
```

### 3. CDROMを取り外し

```bash
# Proxmoxホストで実行
qm set 200 --ide2 none
```

## 🔧 トラブルシューティング

### ISOダウンロードが遅い/失敗する

ミラーサイトを使用：

```bash
# 日本のミラー例
KALI_ISO_URL="https://ftp.riken.jp/Linux/kali-images/kali-2024.4/kali-linux-2024.4-installer-amd64.iso"
```

### VMIDが既に使用されている

スクリプト内の `VMID` を変更：

```bash
VMID="201"  # 空いているIDに変更
```

### EFIブートに問題がある場合

レガシーBIOSに変更：

```bash
# スクリプト内で以下を変更
--bios seabios \
--machine pc \
# --efidisk0 の行を削除
```

## 📌 作成されるVM仕様

| 項目 | 値 |
|------|-----|
| OS Type | Linux (l26) |
| BIOS | OVMF (UEFI) |
| Machine | q35 |
| SCSI Controller | VirtIO SCSI |
| Display | QXL |
| Network | VirtIO |

## 🔗 参考リンク

- [Kali Linux Downloads](https://www.kali.org/get-kali/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
