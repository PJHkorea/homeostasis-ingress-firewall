#!/bin/bash
# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# [Pure Ingress Hardware Controller] Production One-Touch Deployer.
# ========================================================================

set -euo pipefail

# 1. Statically latch global infrastructure environment parameters
INTERFACE="${2:-eth0}" # Targeted network interface card (Defaults to eth0)
BUILD_DIR="./build"
XDP_OBJ="$BUILD_DIR/xdp_ingress.o"
PROXY_BIN="$BUILD_DIR/homeostasis-ingress-proxy"
LOG_FILE="/var/log/homeostasis_firewall.log"

# Enforce root privilege verification guard
if [ "$EUID" -ne 0 ]; then
    echo "[Fatal] This deployment system directly controls Linux kernel drivers and must be executed with root privileges (sudo)."
    exit 1
fi

case "${1:-}" in
    load)
        echo "========================================================================"
        echo "[DEPLOY] Initiating One-Touch Pure Hardware Ingress Firewall Loading"
        echo "========================================================================"
        
        # A. Trigger integrated master compilation
        if [ ! -f "$XDP_OBJ" ] || [ ! -f "$PROXY_BIN" ]; then
            echo "[BUILD] Build artifacts not detected; triggering master Makefile interlock..."
            make all
        fi

        # B. Load native XDP filter onto the low-level network interface card driver
        echo "[KERNEL] Injecting eBPF Object into [$INTERFACE] via Native XDP Mode..."
        ip link set dev "$INTERFACE" xdpdrv obj "$XDP_OBJ" section xdp
        
        # C. Launch upper-layer high-performance Rust orchestrator hub daemon asynchronously
        echo "[HOST] Launching Rust Enterprise Control-Plane Daemon Hub..."
        nohup "$PROXY_BIN" > "$LOG_FILE" 2>&1 &
        
        echo "------------------------------------------------------------------------"
        echo "[SUCCESS] Homeostasis Immunization Wall is now actively protecting [$INTERFACE]."
        echo "Real-time telemetry log tracking: tail -f $LOG_FILE"
        echo "========================================================================"
        ;;
        
    unload)
        echo "========================================================================"
        echo "[UNLOAD] Evacuating Ingress Firewall and Purging Kernel HBM Maps"
        echo "========================================================================"
        
        # A. Gracefully terminate the Rust orchestrator process via signal barriers
        echo "[HOST] Terminating Rust Master Control Daemon..."
        pkill -f homeostasis-ingress-proxy || true
        
        # B. Detach eBPF constraints from the network interface card driver
        echo "[KERNEL] Removing eBPF Filter from dev [$INTERFACE]..."
        ip link set dev "$INTERFACE" xdp off
        
        echo "Clean infrastructure restoration completed successfully."
        echo "========================================================================"
        ;;
        
    status)
        echo "[STATUS] Checking Homeostasis Firewall Infrastructure State..."
        echo "------------------------------------------------------------------------"
        ip link show dev "$INTERFACE" | grep -i xdp || echo "[STATUS] [$INTERFACE] No active XDP kernel filters detected. (Idle state)"
        pgrep -l -f homeostasis-ingress-proxy || echo "[STATUS] Rust monitoring daemon is not active."
        ;;
        
    *)
        echo "Usage: sudo ./deploy.sh {load|unload|status} [interface_name]"
        exit 1
        ;;
esac
