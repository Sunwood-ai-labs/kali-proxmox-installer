<div align="center">
  <img src="assets/header.jpg" alt="Kali Prox Installer Header" width="100%">
</div>

<div align="center">

  [![Shell Script](https://img.shields.io/badge/Shell-Script-black?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
  [![GitHub](https://img.shields.io/badge/GitHub-kali--proxmox--installer-lightgrey?style=flat-square&logo=github)](https://github.com/Sunwood-ai-labs/kali-proxmox-installer)


# Proxmox VE - Kali Linux 自動セットアップスクリプト

</div>


<div align="center">
  Proxmox VE上にKali Linux VMを自動作成・管理するbashスクリプト集です。
</div>

## 特徴

- 🚀 **ワンコマンドでVM作成** - ISOダウンロードからVM設定まで完全自動化
- ⚙️ **柔軟な実行方法** - 直接実行/SSH経由、複数の方式に対応
- 🔧 **VirtIO最適化** - パフォーマンス最大化のための設定済み
- 🌐 **固定IP対応** - セットアップ後のネットワーク設定自動化
- 🔑 **SSHキー設定** - パスワードなし接続の自動設定
- 💾 **ディスク拡張** - ワンコマンドでVMディスクを拡張

## 📁 プロジェクト構成

```
prox/
├── scripts/
│   ├── setup/           # VMセットアップ
│   │   ├── setup-kali-proxmox.sh
│   │   └── remote-setup.sh
│   ├── ssh/             # SSH設定
│   │   ├── setup-ssh-keys.sh
│   │   ├── setup-ssh-via-qm.sh
│   │   └── remote-setup-ssh.sh
│   ├── network/         # ネットワーク設定
│   │   ├── auto-setup-static-ip.sh
│   │   └── fix-static-ip.sh
│   └── manage/          # VM管理
│       └── resize-vm-disk.sh
├── assets/              # 画像等のリソース
├── README.md
└── LICENSE
```

## 📋 前提条件

- Proxmox VEがインストールされていること
- root権限またはsudo権限があること
- インターネット接続（ISOダウンロード用）

## 🚀 クイックスタート

### 1. VMを作成

```bash
cd scripts/setup
./remote-setup.sh
```

### 2. Kali Linuxをインストール

1. Proxmox WebUI (https://192.168.0.147:8006) にアクセス
2. 作成したVM → コンソール を開く
3. Kali Linuxのインストールを完了

### 3. SSHサーバーを有効化

```bash
cd ../ssh
./remote-setup-ssh.sh 200
```

### 4. 固定IPを設定

```bash
cd ../network
./auto-setup-static-ip.sh 200 <現在のIP> <固定IP> <ゲートウェイ> <ユーザー名>

# 例
./auto-setup-static-ip.sh 200 192.168.0.136 192.168.0.200 192.168.0.1 maki
```

### 5. SSHキーを設定

```bash
cd ../ssh
./setup-ssh-keys.sh 200 <固定IP> <ユーザー名>

# 例
./setup-ssh-keys.sh 200 192.168.0.200 maki
```

## 📖 スクリプト詳細

### VMセットアップ (scripts/setup/)

| スクリプト | 説明 |
|----------|------|
| `setup-kali-proxmox.sh` | メインスクリプト（Proxmoxホストで直接実行） |
| `remote-setup.sh` | リモートからSSH経由で実行するラッパー |

### SSH設定 (scripts/ssh/)

| スクリプト | 説明 |
|----------|------|
| `setup-ssh-keys.sh` | SSHキーペアを生成してVMに転送 |
| `setup-ssh-via-qm.sh` | QEMU Guest Agent経由でSSHサーバーを有効化 |
| `remote-setup-ssh.sh` | リモートからSSH設定を実行するラッパー |

### ネットワーク設定 (scripts/network/)

| スクリプト | 説明 |
|----------|------|
| `auto-setup-static-ip.sh` | 固定IPを自動設定 |
| `fix-static-ip.sh` | 固定IP設定の問題を診断・修正 |

### VM管理 (scripts/manage/)

| スクリプト | 説明 |
|----------|------|
| `resize-vm-disk.sh` | VMディスクを拡張 |

## ⚙️ 設定変数

各スクリプト内の以下の変数をお使いの環境に合わせて編集してください：

```bash
# Proxmox設定
PROXMOX_HOST="192.168.0.147"
PROXMOX_USER="root"
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

## 🔧 使用例

### ディスクを拡張

```bash
cd scripts/manage
./resize-vm-disk.sh 200 scsi0 +50G
```

### 固定IPを修正

```bash
cd scripts/network
./fix-static-ip.sh 200 <現在のIP> <固定IP> <ゲートウェイ> <ユーザー名>
```

## 🔗 参考リンク

- [Kali Linux Downloads](https://www.kali.org/get-kali/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
