# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# [5th-Gen Pure Ingress Hardware Controller] Master Integrated Makefile.
# ========================================================================

# 컴파일러 및 도구 세트 정의
CC := clang
CARGO := cargo
PYTHON := python3

# 하드웨어 eBPF CO-RE 표준 아키텍처 타겟 컴파일 플래그
BPF_CFLAGS := -target bpf -g -O2 -Wall \
              -D__TARGET_ARCH_x86 \
              -I/usr/include/x86_64-linux-gnu \
              -I./target-kernel-xdp

# 출력 디렉토리 경로 지정
BUILD_DIR := ./build
XDP_SRC_DIR := ./target-kernel-xdp
RUST_SRC_DIR := ./target-proxy-rust
HARDWARE_DIR := ./target-hardware-cuda

# 기본 매스터 타겟 설정
.PHONY: all
all: directories xdp_core bitwise_mux rust_proxy

# 0. 빌드 아티팩트 정적 저장을 위한 디렉토리 자동 개설
.PHONY: directories
directories:
	@mkdir -p $(BUILD_DIR)

# 1. Linux Kernel 데이터 플레인 XDP 잉그레스 필터 컴파일 (GPLv2 영역)
.PHONY: xdp_core
xdp_core: $(XDP_SRC_DIR)/xdp_ingress.c
	@echo "🛰️  [BUILD] Compiling Linux Kernel 최하단 XDP Ingress Homeostasis Filter (GPLv2)..."
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/xdp_ingress.o

# 2. 분기문 제로화 기계어 MUX 융합 레이어 컴파일 (GPLv2 영역)
.PHONY: bitwise_mux
bitwise_mux: $(XDP_SRC_DIR)/bitwise_mux.c
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
	@cd $(RUST_SRC_DIR) && $(CARGO) clean
	@echo "✨ Clean operation finished completely."
