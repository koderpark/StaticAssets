#!/usr/bin/env bash

# origin of this runner file : https://github.com/oNaiPs/proxmox-scripts/blob/main/lxc_create_github_actions_runner.sh

# This script automates the creation and registration of a Github self-hosted runner within a Proxmox LXC (Linux Container).
# The runner is based on Ubuntu 23.04. Before running the script, ensure you have your GITHUB_TOKEN 
# and the OWNERREPO (github owner/repository) available.

set -e

# Variables
GITHUB_RUNNER_URL="https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz"
PCTSIZE="20G"
PCT_ARCH="amd64"
PCT_CORES="4"
PCT_MEMORY="2048"
PCT_SWAP="2048"
PCT_STORAGE="local"
DEFAULT_IP_ADDR="192.168.20.1/16"
DEFAULT_GATEWAY="192.168.0.1"
DISTRO="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

# Ask for GitHub token and owner/repo if they're not set
if [ -z "$GITHUB_TOKEN" ]; then
    read -r -p "Enter github token: " GITHUB_TOKEN
    echo
fi
if [ -z "$OWNERREPO" ]; then
    read -r -p "Enter github owner/repo: " OWNERREPO
    echo
fi

# log function prints text in yellow
log() {
  local text="$1"
  echo -e "\033[33m$text\033[0m"
}

# Prompt for network details
read -r -e -p "Container Address IP (CIDR format) [$DEFAULT_IP_ADDR]: " input_ip_addr
IP_ADDR=${input_ip_addr:-$DEFAULT_IP_ADDR}
read -r -e -p "Container Gateway IP [$DEFAULT_GATEWAY]: " input_gateway
GATEWAY=${input_gateway:-$DEFAULT_GATEWAY}

# Get filename from the URLs
GITHUB_RUNNER_FILE=$(basename $GITHUB_RUNNER_URL)

# Get the next available ID from Proxmox
DEFAULT_PCTID=$(pvesh get /cluster/nextid)
read -r -e -p "pve ID [$DEFAULT_PCTID]: " input_pve_id
PCTID=${input_pve_id:-$DEFAULT_PCTID}

# Download Ubuntu template
# Create LXC container
log "-- Creating LXC container with ID:$PCTID"
pct create "$PCTID" "$DISTRO" \
   -arch $PCT_ARCH \
   -ostype ubuntu \
   -hostname github-runner-proxmox-$(openssl rand -hex 3) \
   -cores $PCT_CORES \
   -memory $PCT_MEMORY \
   -swap $PCT_SWAP \
   -storage $PCT_STORAGE \
   -features nesting=1,keyctl=1 \
   -net0 name=eth0,bridge=vmbr0,gw="$GATEWAY",ip="$IP_ADDR",type=veth

# Resize the container
log "-- Resizing container to $PCTSIZE"
pct resize "$PCTID" rootfs $PCTSIZE

# Start the container & run updates inside it
log "-- Starting container"
pct start "$PCTID"
sleep 10
log "-- Running updates"
pct exec "$PCTID" -- bash -c "apt update -y && apt install -y git curl zip && passwd -d root"

# Install Docker inside the container
log "-- Installing docker"
pct exec "$PCTID" -- bash -c "curl -qfsSL https://get.docker.com | sh"

# Get runner installation token
log "-- Getting runner installation token"
RES=$(curl -q -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN"  \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/$OWNERREPO/actions/runners/registration-token)

RUNNER_TOKEN=$(echo $RES | grep -o '"token": "[^"]*' | grep -o '[^"]*$')

# Install and start the runner
log "-- Installing runner"
pct exec "$PCTID" -- bash -c "mkdir actions-runner && cd actions-runner &&\
    curl -o $GITHUB_RUNNER_FILE -L $GITHUB_RUNNER_URL &&\
    tar xzf $GITHUB_RUNNER_FILE &&\
    RUNNER_ALLOW_RUNASROOT=1 ./config.sh --unattended --url https://github.com/$OWNERREPO --token $RUNNER_TOKEN &&\
    ./svc.sh install root &&\
    ./svc.sh start"

# disable apparmor
echo "
lxc.apparmor.raw: mount,
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop:
" >> /etc/pve/lxc/$PCTID.conf