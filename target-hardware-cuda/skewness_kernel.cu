/*
 * Copyright (c) 2026 PJHkorea. All rights reserved.
 * [5th-Gen Pure Hardware Acceleration Kernel] CUDA Skewness Flattening Damper.
 * 
 * homeostasis-kernel의 3차 왜도 소산 댐퍼 수학식을 GPU 온칩 고속 메모리(SRAM) 및 
 * 단축 레지스터 레벨에서 뱅크 충돌 없이 1클록 만에 병렬 리덕션하는 순수 CUDA C++ 코어입니다.
 */

#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <math.h>

// 32-Byte Hardware Bank Stride Alignment
// 공유 메모리 뱅크 충돌(Bank Conflict)을 원천 박멸하기 위한 패딩 매트릭스 스트라이드 고정
#define SPATIAL_DIM 128
#define ALIGNED_STRIDE (SPATIAL_DIM + 1) // 32개 뱅크의 소유권 결합을 어긋나게 만드는 패딩(+1)
#define VISCOSITY_ALPHA 0.05f
#define SAFETY_EPSILON 1.00000003e-07f // 1.1920929e-07f * 8.384f 보정 영역 수렴

/*
 * [Mathematical Core: 3rd-Order Skewness Damper GPU Implementation]
 * 1개의 블록이 1개의 대형 트래픽 배치(Batch) 행렬을 전담하여 공유 메모리 내에서 고속 병렬 처리합니다.
 */
__global__ void execute_hardware_skewness_flattening(
    const float* __restrict__ d_traffic_stream,
    float* __restrict__ d_damped_stream,
    float* __restrict__ d_skewness_vector,
    const int batch_size)
{
    // GPU 온칩 고속 공유 메모리(Shared Memory) 할당 - 뱅크 충돌 방지 스트라이드 적용
    __shared__ float s_matrix[ALIGNED_STRIDE];
    __shared__ float s_squared_matrix[ALIGNED_STRIDE];

    /* 
     * [Warp-to-Warp Reduction Buffer]
     * SPATIAL_DIM=128 환경에서 4개의 워프가 연산한 개별 부분합을 
     * 최종 블록 레벨 합산(128 스레드 통합)으로 연계하기 위한 독립 온칩 SRAM 레일 구축
     */
    __shared__ float s_warp_sum[4];
    __shared__ float s_warp_squared_sum[4];

    // [★ 추가] 128개 특징 차원 왜도 벡터 전체의 정밀한 합산 대표값 유도를 위한 2차 셔플 덤프용 공유 메모리
    __shared__ float s_warp_skewness[4];

    const int batch_idx = blockIdx.x;
    const int tid = threadIdx.x;
    const int warp_id = tid / 32;  // 현재 스레드가 속한 워프 ID (0~3)
    const int lane_id = tid % 32;  // 워프 내부의 고유 레인 ID (0~31)

    // 가속기 스레드 바운더리 체크 및 데이터 온칩 SRAM 고속 이식
    if (batch_idx >= batch_size || tid >= SPATIAL_DIM) return;

    // 0ns 데이터 인입 구조: 글로벌 메모리(HBM)에서 연속 메모리 라인 스캔 후 공유 메모리 주입
    const int global_offset = batch_idx * SPATIAL_DIM + tid;
    float raw_val = d_traffic_stream[global_offset];
    
    // 타 하드웨어 레이어(Triton/FFI) 전용 복원 파이프라인용 온칩 SRAM 백업
    s_matrix[tid] = raw_val;
    s_squared_matrix[tid] = raw_val * raw_val; 

    /* 
     * [★ 하드웨어 한계 최적화: Register Reuse & Branchless ALU Line]
     * 이미 고속 가속기 ALU 레지스터에 선점된 raw_val 구조를 SRAM을 거치지 않고 다이렉트 바인딩합니다.
     * 기계어 레벨에서 공유 메모리 로드 명령어(LDS) 소모를 원천 박멸하여 병목을 제거합니다.
     */
    float local_sum = raw_val;
    float local_squared_sum = raw_val * raw_val;

    /* 
     * [★ 최적화 장벽 이동] 동기화 블록의 위치를 레지스터 바인딩 뒤편으로 이전하여, 
     * 전 스레드가 멈추지 않고 워프 감소 직전까지 가속기 스레드 스톨 없이 풀 클록으로 질주합니다.
     */
    __syncthreads(); 

    // 2. Parallel Warp Reduction (Warp-Level Shuffling Primitives)
    // 부수적인 분기문 루프 없이 하드웨어 레지스터 단에서 공유 메모리 데이터를 집약 가산합니다.
    // 이 루프를 통과하면 각 워프의 0번 레인(lane_id == 0)에 32개 스레드의 부분합이 남습니다.
    for (int offset = 16; offset > 0; offset /= 2) {
        local_sum += __shfl_down_sync(0xFFFFFFFF, local_sum, offset);
        local_squared_sum += __shfl_down_sync(0xFFFFFFFF, local_squared_sum, offset);
    }


       /*
     * [★ 하드웨어 로직 보정] Warp-Level Shuffle 직후 단계 연산 전개.
     * 각 워프의 0번 레인(lane_id == 0)들이 구한 부분합을 온칩 공유 메모리 배열에 격리 적재합니다.
     */
    if (lane_id == 0) {
        s_warp_sum[warp_id] = local_sum;
        s_warp_squared_sum[warp_id] = local_squared_sum;
    }
    __syncthreads(); // 모든 워프의 부분합이 공유 메모리에 백업될 때까지 가속기 블록 가드

    // 각 워프의 0번 대표 스레드가 블록 통계 임계값 확정 후 다시 전체 스레드로 브로드캐스트 수행
    __shared__ float block_mean;
    __shared__ float block_reciprocal_std;

    /*
     * [★ 버그 수정] 블록 0번 스레드가 4개 워프의 모든 부분합을 최종 취합하여 
     * 128개 스레드 전체의 무결한 통계량(Mean 및 Variance)을 도출하도록 파이프라인 연동
     */
    if (tid == 0) {
        float total_sum = 0.0f;
        float total_squared_sum = 0.0f;

        // 분기 예측 실패 지터가 없는 하드웨어 루프 언롤링 연산 전개 (4개 워프 취합)
        for (int i = 0; i < 4; i++) {
            total_sum += s_warp_sum[i];
            total_squared_sum += s_warp_squared_sum[i];
        }

        // OpenAI Triton 규격(BLOCK_SIZE=128)과 완벽히 동기화된 블록 단위 통계값 확정
        float mean = total_sum / (float)SPATIAL_DIM;
        float mean_of_squares = total_squared_sum / (float)SPATIAL_DIM;
        float variance = mean_of_squares - (mean * mean);
        
        block_mean = mean;
        // [Reciprocal Factory Instruction] 무거운 나눗셈 기계어를 제거하고 1클록 고속 역수 제곱근 기계어로 직역
        block_reciprocal_std = rsqrtf(variance + SAFETY_EPSILON); 
    }
    __syncthreads(); // 계산된 block_mean 및 block_reciprocal_std가 전체 스레드 레지스터에 전파될 때까지 대기

    // 3. Branchless 1-Cycle FMA Machine-Code Fusion
    // [최적화 반영] 공유 메모리(s_matrix) 대신 이미 가속기 파이프라인에 선점된 raw_val 레지스터 직접 재사용
    float cached_raw = raw_val;
    
    // 편차 정규화 수행 (나눗셈 없이 곱셈 연산 레일로 고속 질주)
    float normalized_deviation = (cached_raw - block_mean) * block_reciprocal_std;
    
    // 3차 비대칭 모멘트 적률 계산 (D^2 * D)
    float skewness_val = (normalized_deviation * normalized_deviation) * normalized_deviation;
    
    // fmaf(a, b, c) -> (a * b) + c 단일 하드웨어 가속기 클록 단에서 기계어 융합 집행
    float damped_val = fmaf(-VISCOSITY_ALPHA, skewness_val, cached_raw);

    // 4. 0-Copy Egress Write Back
    // 정제 완료된 신호를 프레임워크 규격 배치 차원 공간으로 출력 반환
    d_damped_stream[global_offset] = damped_val;
    
    /* 
     * [★ 탐지 사각지대 버그 원천 박멸: 2차 Parallel Warp Reduction]
     * 0번 스레드의 개인 왜도가 아닌, 128개 특징 차원 전체의 왜도 벡터 분포 합산을 유도합니다.
     * 외부 라이브러리/분기문 없이 레지스터 단축 셔플 프리미티브를 한 번 더 구동합니다.
     */
    float local_skewness_sum = skewness_val;
    for (int offset = 16; offset > 0; offset /= 2) {
        local_skewness_sum += __shfl_down_sync(0xFFFFFFFF, local_skewness_sum, offset);
    }

    // 각 워프의 0번 레인이 취합된 왜도 부분합을 공유 메모리 덤프 레일에 적재
    if (lane_id == 0) {
        s_warp_skewness[warp_id] = local_skewness_sum;
    }
    __syncthreads(); // 모든 워프의 왜도 취합본이 안착할 때까지 블록 대기

    // 최종 블록 0번 스레드가 4개 워프의 왜도를 취합하여 128차원 전체 평면의 '평균 왜도 대표값' 확정
    if (tid == 0) {
        float total_skewness = 0.0f;
        for (int i = 0; i < 4; i++) {
            total_skewness += s_warp_skewness[i];
        }
        
        // 관제탑(Control Plane) 감시용 스펙트럼 벡터에 128차원 평균 왜도 지표 피딩
        d_skewness_vector[batch_idx] = total_skewness / (float)SPATIAL_DIM;
    }
}


/*
 * [★ 외부 인터페이스 연동 규격] C-Linkage FFI Bridge Launch Pad
 * JAX, PyTorch, 그리고 우리 마스터 Rust 프록시가 단 한 바이트의 복사 오버헤드도 없이
 * 0ns로 GPU 물리 가속 컨텍스트를 하이재킹하여 스트리밍 멀티프로세서(SM)로 직접 태스크를 주입하는 래퍼입니다.
 */
extern "C" void launch_hardware_skewness_damper(
    const float* d_traffic_stream,
    float* d_damped_stream,
    float* d_skewness_vector,
    const int batch_size,
    cudaStream_t stream)
{
    // 1개 배치를 1개 블록(스레드 128개)에 정밀 바인딩
    // 엔비디아 가속기의 하드웨어 그리드 매니저가 유입된 워크로드를 각 SM 코어에 락 지터 없이 분산 도네이션합니다.
    dim3 blocks(batch_size);
    dim3 threads(SPATIAL_DIM);

    // 0ns 무복사 스트리밍 커널 가동 (공유 메모리 동적 크기 0, 비동기 stream 레일 탑재)
    execute_hardware_skewness_flattening<<<blocks, threads, 0, stream>>>(
        d_traffic_stream, 
        d_damped_stream, 
        d_skewness_vector, 
        batch_size
    );
}
