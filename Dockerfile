# ========================================================================
# [💎 STAGE 1: High-Performance Hardware-Kernel Builder Blueprint]
# 엔비디아 가속기 최적화 및 리눅스 eBPF/XDP 도구 체인이 통합된 공식 CUDA 베이스 가동
# ========================================================================
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS builder

# 인터랙티브 프롬프트 방지 가드레일
ENV DEBIAN_FRONTEND=noninteractive

# 1. 커널 최하단 데이터 플레인 컴파일을 위한 필수 도구 체인 및 libbpf 정적 패키지 인젝션
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

# 2. 제어 플레인 허브 빌드를 위한 소유권 기반 Rust 엔터프라이즈 컴파일러 설치
RUN curl --proto '=https' --tlsv1.2 -sSf https://rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 3. 작업 디렉토리 선점 및 32바이트 하드웨어 얼라인먼트 소스코드 일체 복제
WORKDIR /usr/src/homeostasis-ingress-firewall
COPY . .

# 4. 마스터 Makefile 호출을 통한 이종 언어 가속 커널 일괄 기계어 합성 (AOT Compilation)
# build.rs 내부의 dylib=cudart 및 sm_80 정적 링킹이 이 스테이지에서 완벽 완결됩니다.
RUN make clean && make all

# ========================================================================
# [🚀 STAGE 2: Ultra-Slim Static Runtime Production Image]
# 가벼운 런타임 환경 구성을 위해 빌드 환경의 노이즈를 걷어내고 바이너리만 추출
# ========================================================================
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

WORKDIR /app

# 1. 실전 드라이버 로드 및 텔레메트리를 위한 최소 커널 통신 유틸리티 이식
RUN apt-get update && apt-get install -y \
    iproute2 \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 2. 비동기 관제 수학 필터를 위한 상위 고속 파이썬 라이브러리 캐싱 설치
RUN pip3 install --no-cache-dir numpy pynvml

# 3. Builder 스테이지에서 수리 물리 검증이 끝난 최종 마스터 아티팩트들만 정밀 하이재킹 복사
# [★ 구조 명세 동기화] 패키지 경로를 언더바(_) 규격으로, 출력 파일명을 homeostasis-ingress-proxy로 칼정렬 반영
COPY --from=builder /usr/src/homeostasis-ingress-firewall/build/ /app/build/
COPY --from=builder /usr/src/homeostasis-ingress-firewall/target_proxy_rust/target/release/homeostasis-ingress-proxy /app/build/homeostasis-ingress-proxy
COPY --from=builder /usr/src/homeostasis-ingress-firewall/deploy.sh /app/deploy.sh
COPY --from=builder /usr/src/homeostasis-ingress-firewall/telemetry/ /app/telemetry/
COPY --from=builder /usr/src/homeostasis-ingress-firewall/core_formula/ /app/core_formula/

# 4. 원터치 집행기 셸 스크립트 실행 권한 물리 래칭
RUN chmod +x /app/deploy.sh

# 5. 컨테이너 구동 시 NIC 드라이버 레일 위로 비분기 비트 MUX XDP 필터를 즉각 로드 적재하도록 엔트리포인트 고정
# (실전 가동 시 환경변수 혹은 인자로 인터페이스명을 토스받아 구동 가능)
ENTRYPOINT ["./deploy.sh"]
CMD ["load", "eth0"]

