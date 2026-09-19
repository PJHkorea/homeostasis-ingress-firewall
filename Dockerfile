# ========================================================================
# [STAGE 1: High-Performance Hardware-Kernel Builder Blueprint]
# ========================================================================
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS builder

# Prevent interactive prompts during package installations
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install toolchains and static libbpf libraries required for low-level data plane compilation
RUN apt-get update && apt-get install -y \
    clang \
    llvm \
    libbpf-dev \
    linux-tools-common \
    linux-tools-generic \
    build-essential \
    curl \
    pkg-config \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Rust toolchain to build the control plane hub orchestrator
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 3. Establish working directory and copy source assets mapped to the 32-byte hardware alignment layout
WORKDIR /usr/src/homeostasis-ingress-firewall
COPY . .

# 4. Invoke the master Makefile to compile heterogeneous language accelerator kernels (AOT Compilation)
# Finalizes build.rs configurations including dylib=cudart and sm_80 static link bindings.
RUN make clean && make all

# ========================================================================
# [STAGE 2: Ultra-Slim Static Runtime Production Image]
# ========================================================================
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

WORKDIR /app

# 1. Embed minimal kernel communication utilities required for active driver loading and telemetry ingestion
RUN apt-get update && apt-get install -y \
    iproute2 \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 2. Install high-speed Python libraries designated for the asynchronous telemetry filters
RUN pip3 install --no-cache-dir numpy pynvml

# 3. Selectively extract the finalized master build artifacts verified in the builder phase
# Aligns package path structures and maintains the output binary naming convention as homeostasis-ingress-proxy.
COPY --from=builder /usr/src/homeostasis-ingress-firewall/build/ /app/build/
COPY --from=builder /usr/src/homeostasis-ingress-firewall/target_proxy_rust/target/release/homeostasis-ingress-proxy /app/build/homeostasis-ingress-proxy
COPY --from=builder /usr/src/homeostasis-ingress-firewall/deploy.sh /app/deploy.sh
COPY --from=builder /usr/src/homeostasis-ingress-firewall/telemetry/ /app/telemetry/
COPY --from=builder /usr/src/homeostasis-ingress-firewall/core_formula/ /app/core_formula/

# 4. Enforce runtime execution permissions for the primary deployment shell script
RUN chmod +x /app/deploy.sh

# 5. Fix the container entrypoint to automatically attach the branchless bitwise MUX XDP filters onto the designated network driver interfaces
ENTRYPOINT ["./deploy.sh"]
CMD ["load", "eth0"]

