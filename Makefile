# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# This program is free software: you can redistribute it and/or modify it under 
# the terms of the GNU Affero General Public License as published by the Free Software Foundation.
#
# [5th-Gen Pure Ingress Hardware Controller] Master Integrated Makefile.
# ========================================================================

# 컴파일러 및 도구 세트
CC := clang
CARGO := cargo
PYTHON := python3
BPFTOOL := bpftool

BUILD_DIR := ./build
XDP_SRC_DIR := ./target_kernel_xdp
RUST_SRC_DIR := ./target_proxy_rust
HARDWARE_DIR := ./target_hardware_cuda

VMLINUX_H := $(XDP_SRC_DIR)/vmlinux.h

BPF_CFLAGS := -target bpf -g -O2 -Wall \
              -D__TARGET_ARCH_x86 \
              -I/usr/include/x86_64-linux-gnu \
              -I$(XDP_SRC_DIR)

.PHONY: all
all: directories vmlinux_gen xdp_core bitwise_mux rust_proxy

.PHONY: directories
directories:
	@mkdir -p $(BUILD_DIR)

.PHONY: vmlinux_gen
vmlinux_gen: $(VMLINUX_H)

$(VMLINUX_H):
	@if [ -f /sys/kernel/btf/vmlinux ]; then \
		$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $(VMLINUX_H); \
	else \
		exit 1; \
	fi

.PHONY: xdp_core
xdp_core: $(XDP_SRC_DIR)/xdp_ingress.c $(VMLINUX_H)
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/xdp_ingress.o

.PHONY: bitwise_mux
bitwise_mux: $(XDP_SRC_DIR)/bitwise_mux.c $(VMLINUX_H)
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/bitwise_mux.o

.PHONY: rust_proxy
rust_proxy:
	@cd $(RUST_SRC_DIR) && RUSTFLAGS="-C link-arg=-lbpf" $(CARGO) build --release
	@cp $(RUST_SRC_DIR)/target/release/homeostasis-ingress-proxy $(BUILD_DIR)/

.PHONY: test
test:
	PYTHONPATH=. $(PYTHON) -m unittest discover -s tests -p "test*.py"

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VMLINUX_H)
	@cd $(RUST_SRC_DIR) && $(CARGO) clean
	rm -rf ~/.triton/cache

