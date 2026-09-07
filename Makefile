# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# This program is free software: you can redistribute it and/or modify it under 
# the terms of the GNU Affero General Public License as published by the Free Software Foundation.
#
# [5th-Gen Pure Ingress Hardware Controller] Master Integrated Makefile.
# ========================================================================

# 컴파일러 및 도구 세트 정의
CC := clang
CARGO := cargo
PYTHON := python3
BPFTOOL := bpftool

# 출력 디렉토리 및 소스 래티스 경로 지정
BUILD_DIR := ./build
XDP_SRC_DIR := ./target-kernel-xdp
RUST_SRC_DIR := ./target-proxy-rust
HARDWARE_DIR := ./target-hardware-cuda

# [★ CO-RE 핵심 주입] 실시간 시스템 구조체 추출을 위한 vmlinux.h 타겟 정의
VMLINUX_H := $(XDP_SRC_DIR)/vmlinux.h

# 하드웨어 eBPF CO-RE 표준 아키텍처 타겟 컴파일 플래그
# 로컬 디렉토리 내부로 실시간 추출된 vmlinux.h를 우선 참조하도록 헤더 인클루드 레일 설정
BPF_CFLAGS := -target bpf -g -O2 -Wall \
              -D__TARGET_ARCH_x86 \
              -I/usr/include/x86_64-linux-gnu \
              -I$(XDP_SRC_DIR)

# 기본 매스터 타겟 설정 (의존성 체인 맨 앞에 vmlinux_gen 주입)
.PHONY: all
all: directories vmlinux_gen xdp_core bitwise_mux rust_proxy

# 0. 빌드 아티팩트 정적 저장을 위한 디렉토리 자동 개설
.PHONY: directories
directories:
	@mkdir -p $(BUILD_DIR)

# [★ 추가] 현재 가동 중인 리눅스 커널 커버리지로부터 vmlinux.h 자동 덤프 생성 레일
.PHONY: vmlinux_gen
vmlinux_gen: $(VMLINUX_H)

$(VMLINUX_H):
	@echo "🧬 [CO-RE] Extracting running kernel BTF and generating local vmlinux.h..."
	@if [ -f /sys/kernel/btf/vmlinux ]; then \
		$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $(VMLINUX_H); \
	else \
		echo "❌ [Fatal] /sys/kernel/btf/vmlinux가 존재하지 않습니다. 커널이 BTF 빌드 설정을 지원해야 합니다."; \
		exit 1; \
	fi

# 1. Linux Kernel 데이터 플레인 XDP 잉그레스 필터 컴파일 (GPLv2 영역)
# vmlinux.h가 생성된 이후에 컴파일이 수행되도록 정적 의존성 바인딩
.PHONY: xdp_core
xdp_core: $(XDP_SRC_DIR)/xdp_ingress.c $(VMLINUX_H)
	@echo "🛰️  [BUILD] Compiling Linux Kernel 최하단 XDP Ingress Homeostasis Filter (GPLv2)..."
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/xdp_ingress.o

# 2. 분기문 제로화 기계어 MUX 융합 레이어 컴파일 (GPLv2 영역)
.PHONY: bitwise_mux
bitwise_mux: $(XDP_SRC_DIR)/bitwise_mux.c $(VMLINUX_H)
	@echo "🛡️  [BUILD] Compiling Silicon-Level Bitwise MUX Branchless Filter (GPLv2)..."
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/bitwise_mux.o

# 3. 고성능 0ns 제로카피 오케스트레이터 프록시 컴파일 (AGPLv3 영역)
.PHONY: rust_proxy
rust_proxy:
	@echo "🦀 [BUILD] Packing and Compiling High-Performance Rust Master Hub (AGPLv3)..."
	@cd $(RUST_SRC_DIR) && $(CARGO) build --release
	@cp $(RUST_SRC_DIR)/target/release/homeostasis-ingress-proxy $(BUILD_DIR)/

# 4. 수리 물리적 위상 무결성 샌드박스 유닛 테스트 자동 구동
.PHONY: test
test:
	@echo "🧪 [INTEGRITY-TEST] Initiating Pure Functional Mathematical Sandbox Verification..."
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

# 5. 빌드 사본 및 임시 컴파일 오브젝트 클린 오퍼레이션
.PHONY: clean
clean:
	@echo "🧼 [CLEAN] Purging compiled hardware object binaries and target buffers..."
	rm -rf $(BUILD_DIR)
	rm -f $(VMLINUX_H)
	@cd $(RUST_SRC_DIR) && $(CARGO) clean
	@echo "✨ Clean operation finished completely."

