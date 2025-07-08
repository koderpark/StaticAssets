### Instructions

```bash
# install container image
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Download the script
curl -O https://raw.githubusercontent.com/koderpark/StaticAssets/main/Server/pve-lxc-runner.sh

# Inspect script, customize variables

# Run the script
bash pve-lxc-runner.sh
```

Warning: make sure you read and understand the code you are running before executing it on your machine.

https://nad4.tistory.com/entry/Proxmox-LXC-Docker-Error

배시파일 실행 후 apparmor 오류 발생시 윗글 따라 해결할것.
