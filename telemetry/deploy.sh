#!/bin/bash
# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# [5th-Gen Pure Ingress Hardware Controller] Production One-Touch Deployer.
# ========================================================================

set -euo pipefail

# 1. 전역 인프라 환경 변수 고정 래칭
INTERFACE="${2:-eth0}" # 대상 NIC 카드 (기본값 eth0)
BUILD_DIR="./build"
XDP_OBJ="$BUILD_DIR/xdp_ingress.o"
PROXY_BIN="$BUILD_DIR/homeostasis-ingress-proxy"
LOG_FILE="/var/log/homeostasis_firewall.log"

# 루트 권한 강제 검증 가드
if [ "$EUID" -ne 0 ]; then
    echo "❌ [Fatal] 본 배포 시스템은 리눅스 커널 드라이버를 직접 통제하므로 반드시 root 권한(sudo)으로 실행해야 합니다."
    exit 1
fi

case "${1:-}" in
    load)
        echo "========================================================================"
        echo "🛰️  [DEPLOY] Initiating One-Touch Pure Hardware Ingress Firewall Loading"
        echo "========================================================================"
        
        # A. 통합 매스터 컴파일 기동
        if [ ! -f "$XDP_OBJ" ] || [ ! -f "$PROXY_BIN" ]; then
            echo "🧬 [BUILD] 빌드 산출물이 포착되지 않아 매스터 Makefile 인터록을 트리거합니다..."
            make all
        fi

        # B. 최하단 리눅스 드라이버 레벨에 Native XDP 하이재킹 적재
        echo "🛡️  [KERNEL] Injecting eBPF Object into [$INTERFACE] via Native XDP Mode..."
        ip link set dev "$INTERFACE" xdpdrv obj "$XDP_OBJ" section xdp
        
        # C. 상위 고성능 Rust 오케스트레이터 허브 비동기 백그라운드 질주 가동
        echo "🦀 [HOST] Launching Rust Enterprise Control-Plane Daemon Hub..."
        nohup "$PROXY_BIN" > "$LOG_FILE" 2>&1 &
        
        echo "------------------------------------------------------------------------"
        echo "✅ [SUCCESS] Homeostasis Immunization Wall is now actively protecting [$INTERFACE]."
        echo "📊 Real-time telemetry log tracking: tail -f $LOG_FILE"
        echo "========================================================================"
        ;;
        
    unload)
        echo "========================================================================"
        echo "🧼 [UNLOAD] Evacuating Ingress Firewall and Purging Kernel HBM Maps"
        echo "========================================================================"
        
        # A. Rust 오케스트레이터 프로세스 안전 종료 (시그널 배리어 가동)
        echo "🦀 [HOST] Terminating Rust Master Control Daemon..."
        pkill -f homeostasis-ingress-proxy || true
        
        # B. NIC 인터페이스 드라이버 구속 격리 해제
        echo "🛰️  [KERNEL] Removing eBPF Filter from dev [$INTERFACE]..."
        ip link set dev "$INTERFACE" xdp off
        
        echo "✨ Clean infrastructure restoration completed successfully."
        echo "========================================================================"
        ;;
        
    status)
        echo "📊 [STATUS] Checking Homeostasis Firewall Infrastructure State..."
        echo "------------------------------------------------------------------------"
        ip link show dev "$INTERFACE" | grep -i xdp || echo "🟢 [$INTERFACE] 현재 적재된 XDP 커널 필터가 없습니다. (정상 유휴)"
        pgrep -l -f homeostasis-ingress-proxy || echo "💤 Rust 관제 데몬이 구동 중이 아닙니다."
        ;;
        
    *)
        echo "💻 Usage: sudo ./deploy.sh {load|unload|status} [interface_name]"
        exit 1
        ;;
esac
