#!/bin/bash
# VM 200 へのSSH接続スクリプト

ssh -i "/home/aslan/.ssh/prox_vm_200" -o StrictHostKeyChecking=no "maki@192.168.0.200" "$@"
