# High-Performance Hardware Accelerator Core Specification

본 문서는 `homeostasis-ingress-firewall`에서 대용량 트래픽 텐서의 고속 대수학 연산 및 양자 포텐셜 필터링을 처리하는 GPU 하드웨어 가속기 코어(`target_hardware_cuda`)의 아키텍처와 로우레벨 최적화 명세를 다룹니다.

---

## 1. 하드웨어 메모리 레이아웃 및 뱅크 충돌(Bank Conflict) 박멸

대규모 라인 레이트(Line-rate) 트래픽 처리에서 최상위 통계 매트릭스를 연산할 때 발생하는 가장 큰 병목은 GPU 온칩 공유 메모리(SRAM Shared Memory)의 뱅크 충돌입니다. 본 가속기 코어는 이를 물리적 레이아웃 조정을 통해 해결합니다.

### 1) `ALIGNED_STRIDE` 설계를 통한 공유 메모리 인터리빙
NVIDIA GPU의 공유 메모리는 32개의 독립적인 뱅크(Bank)로 분할되어 있으며, 동일한 뱅크에 여러 스레드가 동시에 접근할 경우 워프 직렬화(Warp Serialization)가 발생하여 레이턴시 저하를 유발합니다.

`target_hardware_cuda/skewness_kernel.cu`는 다음과 같이 메모리 레이아웃을 수정해 레이턴시를 회피합니다.

```cpp
#define SPATIAL_DIM 128
#define ALIGNED_STRIDE (SPATIAL_DIM + 1) // 129 차원 패딩 적용
```

- 고정 차원 `128`에 의도적으로 `+1` 패딩을 주어 스트라이드 크기를 `129`로 변환합니다. -> 
이 조치를 통해 2D 텐서 데이터를 하드웨어 메모리에 적재할 때, 각 행(Row)의 시작점이 32 뱅크 경계면을 기준으로 하나씩 밀려나며 나선형으로 정렬됩니다. -> 
이로써 32개 스레드가 종방향(Column-wise)으로 동시 접근하더라도 뱅크 충돌을 수학적으로 회피하며 메모리 가속을 유지합니다.

---

## 2. 워프 감소(Warp Reduction) 및 레지스터 최적화

트래픽 흐름의 3차 적률(Skewness, 왜도)을 구하기 위해 무거운 반복문(`for`)이나 동기화 장벽(`__syncthreads()`)을 사용하는 대신, 엔비디아 SM(Streaming Multiprocessor) 레벨의 하드웨어 프리미티브를 직접 활용합니다.

### 1) 레지스터 재사용 (Register Reuse)
글로벌 메모리(HBM)에서 데이터를 로드하여 공유 메모리에 쓰는 시점에, 가져온 레지스터 값(`raw_val`)을 소실시키지 않고 그대로 유지하여 1차 Sum 연산에 직결합니다. 
이를 통해 공유 메모리 읽기 명령어(`LDS`)의 총 호출 횟수를 절감합니다.

### 2) `__shfl_down_sync` 프리미티브 가속
Warp 내 스레드 간 초고속 데이터 집약을 위해 메모리 버스를 거치지 않고 레지스터 대 레지스터로 직접 통신하는 하드웨어 내장 함수를 사용합니다.

```cpp
// target_hardware_cuda/skewness_kernel.cu 중 일부
for (int offset = 16; offset > 0; offset /= 2) {
    val += __shfl_down_sync(0xFFFFFFFF, val, offset);
}
```
이 메커니즘을 통해 조건 분기(`if`)를 완전히 제거하여 CPU/GPU 파이프 스톨을 방지합니다.

---

## 3. OpenAI Triton 기반의 양자 장벽 가속 및 무분기 소산

최종적인 패킷 차단 여부의 경계장을 필터링하는 `target_hardware_cuda/schrodinger_filter.triton`은 컴파일 타임 상수를 통해 최적의 하드웨어 최적화 명령어(SASS)를 생성합니다.

### 1) SFU(Special Function Unit) 하드웨어 매핑
Triton 커널 내에서 계산되는 슈뢰딩거 포텐셜 장벽의 WKB 투과율 공식 $T = \exp(-2\sqrt{V})$ 은 일반적인 산술 연산 장치(ALU)가 아닌, 초고속 초월함수 연산 전용 하드웨어 유닛인 
SFU(Special Function Unit)에 다이렉트로 매핑됩니다.

- `tl.exp` 및 `tl.sqrt` 연산은 하드웨어 파이프라인에서 단 1~2클록 단위로 처리되도록 하여, 제어 평면의 지연 속도를 나노초 레벨로 유도합니다.

### 2) `BLOCK_SIZE = 128`과 Vectorized Load/Store
어댑터단(`api_adapter.py`)에서 고정한 `128`차원 정적 행렬은 Triton 커널의 정적 블록 크기(`BLOCK_SIZE = 128`)와 1:1로 결합합니다.

```python
# target_hardware_cuda/schrodinger_filter.triton 중 일부
@triton.jit
def schrodinger_filter_kernel(..., BLOCK_SIZE: tl.constexpr):
    offsets = tl.arange(0, BLOCK_SIZE) # 0..127 정적 스케줄링
```

이 규칙을 통해 컴파일러는 메모리 로드 및 저장을 대형 버스 규격에 맞춰 정렬된 벡터화 명령어(Vectorized Load/Store, `LDG.E.128` / `STG.E.128`)로 자동 변환합니다. 
HBM과 온칩 캐시 메모리 간의 대역폭을 100% 포화(Saturation)시켜 물리적 한계 성능을 이끌어냅니다.

### 3) 1클록 FMA(Fused Multiply-Add)를 통한 상태 에너지 소산
정제된 투과율 T를 트래픽 벡터에 적용할 때, 별도의 조건 제어문 없이 연산기 자체에서 곱셈과 덧셈을 한 사이클에 묶어 처리하는 `fmaf` 기계어로 집행되어, 
메모리 전송 레이턴시가 연산 파이프라인 속에 은닉(Latency Hiding)됩니다.

> Triton 컴파일러 최적화 예외 보증 및 SASS 직역 제어는 어떻게 할까요?

Triton 커널 내부에서 분모 제로 파산을 막기 위한 가드레일(`tl.maximum(d, 1e-6)`)이 컴파일러의 과도한 데드 코드 제거(DCE) 최적화 과정에서 왜곡되거나 누락되는 것을 차단합니다. 

이를 위해 `schrodinger_filter.triton`은 컴파일 타임 상수(`tl.constexpr`)와 하드웨어 내장 비교-선택 명령어(SASS 레벨의 `SEL` 또는 `MIN`/`MAX` 프리미티브)로 무분기 직역되도록 인라인 제어 구문을 강제합니다. 수치 해석적 예외 처리 코드 자체가 완벽한 무분기(Branchless) 기계어로 물리 칩셋에 유도하며 가속 파이프라인의 하드웨어 무한 록을 회피합니다.

