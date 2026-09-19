# ========================================================================
# Copyright (c) 2026 PJHkorea. All rights reserved.
# Refer to the original file for license and copyright declarations.
# [Pure Ingress Hardware Controller] Master Integrated Makefile.
# ========================================================================

# [Compiler and Hardware Toolchain Definitions]
CC := clang
CARGO := cargo
PYTHON := python3
BPFTOOL := bpftool

BUILD_DIR := ./build
XDP_SRC_DIR := ./target_kernel_xdp
RUST_SRC_DIR := ./target_proxy_rust
HARDWARE_DIR := ./target_hardware_cuda

# [CO-RE Injection Target] Local vmlinux.h target binding for dynamic runtime kernel offset extraction
VMLINUX_H := $(XDP_SRC_DIR)/vmlinux.h

# [Hardware eBPF CO-RE Standard Architecture Target Compilation Flags]
BPF_CFLAGS := -target bpf -g -O2 -Wall \
              -D__TARGET_ARCH_x86 \
              -I/usr/include/x86_64-linux-gnu \
              -I$(XDP_SRC_DIR)

# [Primary Master Target Configuration (Enforces vmlinux_gen at the front of the dependency chain)]
.PHONY: all
all: directories vmlinux_gen xdp_core bitwise_mux rust_proxy

# 0. Automate build directory allocation for static artifact retention
.PHONY: directories
directories:
	@mkdir -p $(BUILD_DIR)

# [CO-RE Core Mechanism] Automatically dumps vmlinux.h structure specs from the active host Linux kernel
.PHONY: vmlinux_gen
vmlinux_gen: $(VMLINUX_H)

$(VMLINUX_H):
	@echo "[CO-RE] Extracting running kernel BTF and generating local vmlinux.h..."
	@if [ -f /sys/kernel/btf/vmlinux ]; then \
		$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $(VMLINUX_H); \
	else \
		echo "[Fatal] /sys/kernel/btf/vmlinux not found. Host kernel must support BTF compilation configs."; \
		exit 1; \
	fi

# 1. Compile Linux Kernel Data Plane XDP Ingress Filter (GPLv2 Domain)
# Statically binds dependencies to ensure compilation executes after vmlinux.h generation.
.PHONY: xdp_core
xdp_core: $(XDP_SRC_DIR)/xdp_ingress.c $(VMLINUX_H)
	@echo "[BUILD] Compiling Linux Kernel Low-Level XDP Ingress Homeostasis Filter (GPLv2)..."
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/xdp_ingress.o

# 2. Compile Branchless Machine-Code MUX Integration Layer (GPLv2 Domain)
.PHONY: bitwise_mux
bitwise_mux: $(XDP_SRC_DIR)/bitwise_mux.c $(VMLINUX_H)
	@echo "[BUILD] Compiling Silicon-Level Bitwise MUX Branchless Filter (GPLv2)..."
	$(CC) $(BPF_CFLAGS) -c $< -o $(BUILD_DIR)/bitwise_mux.o

# 3. Compile High-Performance Zero-Copy Orchestrator Proxy (AGPLv3 Domain)
# [libbpf-rs Native Interlock] Injects RUSTFLAGS to dynamically link the low-level host system shared library (-lbpf) 
# during cargo linking phase, supporting the main.rs native kernel map system call integration blueprint.
.PHONY: rust_proxy
rust_proxy:
	@echo "[BUILD] Packing and Compiling High-Performance Rust Master Hub (AGPLv3)..."
	@cd $(RUST_SRC_DIR) && RUSTFLAGS="-C link-arg=-lbpf" $(CARGO) build --release
	@cp $(RUST_SRC_DIR)/target/release/homeostasis-ingress-proxy $(BUILD_DIR)/

# 4. Integrate Asynchronous Mathematical Integrity Sandbox Verification and 100Gbps Physical Stress Benchmarks
.PHONY: test
test:
	@echo "[INTEGRITY-TEST] Initiating Pure Functional Mathematical Sandbox Verification..."
	# [PYTHONPATH=. Environment Variable Injection and Wildcard Mapping]
	# Expands pattern matching logic into a unified execution track, allowing legacy test_*.py test cases 
	# and the newly integrated 100Gbps test2_homeostasis_core.py benchmark suite to execute sequentially in a single pass.
	PYTHONPATH=. $(PYTHON) -m unittest discover -s tests -p "test*.py"

# 5. Purge Build Artifacts and Volatile Compilation Buffers
.PHONY: clean
clean:
	@echo "[CLEAN] Purging compiled hardware object binaries and target buffers..."
	rm -rf $(BUILD_DIR)
	rm -f $(VMLINUX_H)
	@cd $(RUST_SRC_DIR) && $(CARGO) clean
	# [Triton Accelerator Kernel Runtime Cache Purge]
	# Completely flushes the local compiled graphics cache directories down to a zero-baseline format 
	# to eradicate obsolete SASS binaries, memory compilation artifacts, and transient hardware latching anomalies.
	rm -rf ~/.triton/cache
	@echo "Clean operation finished completely."
