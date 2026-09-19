# Kernel Data Plane & Branchless MUX Specification

본 문서는 `homeostasis-ingress-firewall`의 최하단 패킷 가속 및 필터링을 담당하는 eBPF/XDP 커널 데이터 플레인(`target_kernel_xdp`)의 구조와 지터 프리(Jitter-Free) 아키텍처 명세를 다룹니다.

---

## 1. 제어-데이터 플레인 디커플링 (Decoupling)

본 시스템은 네트워크 카드(NIC) 드라이버 레이어에서 패킷을 처리하는 **eBPF/XDP(eXpress Data Path)** 기술을 채택하여, 
고성능 가속기(GPU/Triton) 연산 시 필연적으로 발생하는 PCIe 버스 레이턴시 및 호스트-디바이스 통신 병목을 격리합니다.

### 1) 실시간 데이터 패스의 독립성 (Hot Path)
- **Zero-GPU Intervention:** 패킷이 수신될 때마다 GPU나 유저 레벨(Rust 데몬)로 패킷 데이터를 라우팅하거나 대기하지 않습니다. XDP 프로그램은 패킷이 유입되는 순간 고유의 커널 맵만 참조하여 독립적으로 통과(`XDP_PASS`) 또는 차단(`XDP_DROP`)을 결정합니다.
- **Asynchronous Telemetry:** 패킷 바디를 카피하는 오버헤드 대신, 패킷 헤더의 고정 오프셋에서 추출한 최소한의 통계 지표(RPS, PPS, Error Rate, Bandwidth Delta)만 `BPF_MAP_TYPE_RINGBUF`를 통해 밀리초(ms) 단위의 비동기 스트림으로 상위 레이어에 투척(Fire-and-Forget)합니다.

---

## 2. Q16.16 고정소수점 연산 및 eBPF 검증기(Verifier) 최적화

리눅스 커널 내부(eBPF)에서는 소수점(Floating Point) 하드웨어 연산이 금지되어 있습니다. 
본 시스템은 이를 우회하고 커널 내에서 고속으로 3차 적률(왜도) 초기 완충 연산을 수행하기 위해 정수형 고정소수점 연산을 구현합니다.

### 1) Q16.16 고정소수점 (Fixed-Point) 산술 레일
`target_kernel_xdp/xdp_ingress.c`는 `FIXED_ONE (65536)` 상수를 기저로 하는 고정소수점 연산을 적용하여 커널 내 연산 속도를 보장합니다.

```c
#define FIXED_SHIFT 16
#define FIXED_ONE (1 << FIXED_SHIFT)

// 고정소수점 역산 및 상위 레이어 스케일링 예시
__u32 damped_signal = (variance_q16 * viscosity_alpha) >> FIXED_SHIFT;
```
- 하드웨어 가속기(GPU)로 원원시 텐서가 넘어가기 전, 커널 레벨에서 1차적인 트래픽 충격파 감쇄를 정수 곱셈/시프트 연산만으로 처리하여 원격 제어 평면의 부담을 경감시킵니다.

> BPF_MAP_TYPE_RINGBUF 포화 및 텔레메트리 유실 방어는 어떻게 할 수 있을까요?

초당 1,488만 패킷(Line-Rate)이 인입되는 최악의 상황에서 `bpf_ringbuf_reserve` 공간이 가득 차 페이로드가 유실되면 상위 가속기 플레인의 위상 역산이 마비될 위험이 있습니다. 

이를 방지하기 위해 본 데이터 플레인은 링버퍼 예약 실패 시(log == NULL) 단순 패킷 드롭이 아닌, 직전 프레임의 가속기 차단 마스크(gate_mask)를 원자적으로 강제 상속(Fallback Defend)하여 유지하도록 설계되었습니다. 텔레메트리 채널의 순간적인 포화 상태가 전체 방어선의 붕괴로 이어지지 않도록 유도합니다.

### 2) `LOG_SIZE` 정적 매크로를 통한 검증기(Verifier) 통과
리눅스 eBPF 검증기는 메모리 런타임 가변 크기를 추적할 때 컴파일러의 해석 오류로 인해 실행을 거부(Reject)할 수 있습니다. 이를 방지하기 위해 링 버퍼 예약 공간의 크기를 고정된 상수로 강제합니다.

```c
#define LOG_SIZE 32 // struct telemetry_payload의 물리 크기 고정

// 구조체 포인터 대신 정적 리터럴 상수를 직접 주입
struct telemetry_payload *log = bpf_ringbuf_reserve(&telemetry_queue, LOG_SIZE, 0);
```

---

## 3. 무분기 비트 융합 MUX (Branchless MUX) 메커니즘

대량의 트래픽을 처리하는 환경에서 `if (is_anomaly) return XDP_DROP;`과 같은 조건문은 CPU 파이프라인의 분기 예측 실패(Branch Misprediction)를 유발하여 심각한 성능 저하(Stall)를 초래합니다. 
`target_kernel_xdp/bitwise_mux.c`는 이를 해결하기 위해 수학적 무분기 스위칭을 수행합니다.

### 1) 2의 보수 마스킹을 통한 1클록 패킷 증발
가속기 및 제어 플레인에서 판단한 공격 차단 여부 신호(`gate_mask`: 0 또는 1)를 기반으로 비트 마스크를 동적으로 생성합니다.

```c
// target_kernel_xdp/bitwise_mux.c 중 일부
__s32 mask = -(__s32)gate_mask; // gate_mask가 1이면 0xFFFFFFFF, 0이면 0x00000000

// 분기문 없이 비트 연산만으로 action 결정
__u32 action = (XDP_DROP & mask) | (XDP_PASS & ~mask);
return action;
```

- 이 연산은 컴파일 시 조건 분기 점프 명령어(`JMP`, `JE` 등) 대신 논리 연산 명령어(`AND`, `NOT`, `OR`) 및 조건부 이동 명령어(`CMOV`)로 변환됩니다. 결과적으로 하드웨어 파이프라인 레벨에서 1~2클록 내 패킷 드롭을 유도합니다.

---

## 4. 32바이트 하드웨어 캐시 라인 정렬 (ABI Alignment)

이종 언어 간(eBPF C -> Rust -> Python) 데이터 직렬화 오버헤드를 제로화하기 위해, 커널 버퍼와 호스트 메모리의 레이아웃을 바이트 단위로 일치시킵니다.

```c
struct telemetry_payload {
    __u32 src_ip;
    __u32 features[4]; // rps, pps, error_rate, bandwidth_delta
    __u64 packet_count;
    __u32 padding;
} __attribute__((aligned(32)));
```

- 총 크기를 32바이트 및 `aligned(32)` 구조로 패딩 마감하여 CPU의 L1/L2 캐시 라인 스트라이드 경계면과 정렬시킵니다.
- `telemetry/ring_buffer_monitor.rs`의 `#[repr(C, align(32))]` 구조체와 메모리가 메모리 복사 없이 그대로 중첩(Overlap)되어 가상 메모리 매핑만으로 최상위 대수학 엔진까지 제로카피 인터록 됩니다.
