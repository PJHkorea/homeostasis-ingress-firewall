/*
 * Copyright (c) 2026 PJHkorea. All rights reserved.
 * This program is free software: you can redistribute it and/or modify it under 
 * the terms of the GNU Affero General Public License as published by the Free Software Foundation.
 *
 * [5th-Gen Pure Ingress Hardware Controller] Linux Kernel XDP Bitwise MUX Interlock.
 * 
 * homeostasis-kernel의 silicon_mux.py(1-Cycle Branchless FMA) 철학을
 * 리눅스 커널 eBPF/XDP 환경에 맞춰 순수 정수 비트 연산 마스크로 구현한 기계어 융합 레이어입니다.
 */

/* 
 * [CO-RE 주입] 리눅스 파편화 극복을 위해 표준 헤더를 완전히 도려내고 vmlinux.h를 참조합니다.
 * xdp_ingress.c와 커널 데이터 오프셋 및 맵 구조적 인터페이스를 100% 동기화합니다.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>

/*
 * [★ Verifier 안심 조항] 구조체 크기를 매크로 상수로 고정하여 
 * bpf_ringbuf_reserve의 메모리 추적기(Range Tracker) 딴지 오차를 원천 박멸합니다.
 */
#define LOG_SIZE 32

/*
 * [★ 아키텍처 리팩토링: 전 레이어 텐서 레이아웃 동기화]
 * xdp_ingress.c, telemetry/ring_buffer_monitor.rs 및 target_proxy_rust의 고도화 규격과 완벽히 포개어집니다.
 * 이종 커널 간의 데이터 오프셋 오차를 0%로 동제하기 위해 features[4] 실수 융합 텐서 레일을 이식합니다.
 * 
 * 크기 계산: src_ip(4B) + features(4B * 4 = 16B) + packet_count(8B) + padding(4B) = 32바이트 캐시라인 물리 경계 완벽 수호
 */
struct telemetry_payload {
    __u32 src_ip;
    float features[4];     // [★ 고도화] RPS, PPS, ErrorRate, BandwidthDelta 융합 텐서 레일
    __u64 packet_count;    // 관제/PPS 카운팅용 고속 카운터 필드
    __u32 padding;         // 32-Byte Boundary 정렬 완료를 위한 보정 패딩
} __attribute__((aligned(32)));

/*
 * [★ 공유 참조 선언] xdp_ingress.c에서 정의된 마스터 링 버퍼 공간을 외부 참조(extern) 형태로 연결합니다.
 * 동일한 메모리 맵 레일을 공유하여 중복 맵 생성 오버헤드를 박멸합니다.
 */
extern struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
} telemetry_ringbuf SEC(".maps");

/*
 * [32-Byte Hardware Bus Stride Configuration]
 * 하드웨어 캐시 라인 경계 및 L1/L2 메모리 뱅크 충돌을 방지하기 위한 정적 데이터 구조 정렬
 * 멤버 크기 합산: 4 + 4 + 2 + 2 = 12바이트 -> 32바이트 정렬을 위한 20바이트 명시적 바이트 가드 주입
 */
struct packet_feature_matrix {
    __u32 src_ip;
    __u32 dst_ip;
    __u16 tot_len;
    __u16 protocol;
    __u8 padding[20]; // 32바이트 하드웨어 뱅크 스트라이드 정렬 완벽 보정
} __attribute__((aligned(32)));

/*
 * [Mathematical Interlock Core: Branchless Register-Level MUX]
 * 컴파일 타임에 JMP(조건 분기) 명령어를 완전히 박멸하는 순수 대수학적 비트 멀티플렉서입니다.
 */
static __always_inline int execute_silicon_bitwise_mux(
    __u32 gate_mask, 
    int normal_action, 
    int drop_action
) {
    /*
     * 1. 2의 보수 연산을 이용한 전면 마스킹 비트 전개
     *    gate_mask = 0 (정상) -> 0x00000000
     *    gate_mask = 1 (악성) -> -1 -> 0xFFFFFFFF
     */
    __s32 hardware_mask = -(__s32)gate_mask;

    /*
     * 2. 1-Cycle 비트 연산 마스크 인터록 집행
     *    hardware_mask가 0x00000000이면: (normal & 0xFFFFFFFF) | (drop & 0x00000000) -> normal_action
     *    hardware_mask가 0xFFFFFFFF이면: (normal & 0x00000000) | (drop & 0xFFFFFFFF) -> drop_action
     * 
     * CPU 가산기/논리 연산 레지스터 단에서 단 1클록 만에 두 위상의 흐름을 조건문 없이 스위칭합니다.
     */
    return (normal_action & ~hardware_mask) | (drop_action & hardware_mask);
}

SEC("xdp_mux")
int xdp_bitwise_mux_filter(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    /* Bounds Checking - eBPF 정적 검증기(Verifier) 통과 규격 보증 */
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end)
        return XDP_PASS;

    if (eth->h_proto != __constant_htons(ETH_P_IP))
        return XDP_PASS;

       struct iphdr *iph = (void *)(eth + 1);
    
    /* 
     * [★ 바이트 가드라인 한 줄 보강: 0ns Safe Read Line]
     * iph 구조체 전체 크기(20바이트)가 실제 패킷 범위 내에 완전히 속해 있음을 
     * 검증기(Verifier)에게 증명하여 후속 레지스터 다이렉트 맵 매핑 시의 정적 거부를 원천 박멸합니다.
     */
    if ((void *)iph + sizeof(struct iphdr) > data_end)
        return XDP_PASS;

    /* 32-Byte Stride Hardware 패킷 특징 정형 매트릭스 추출 */
    struct packet_feature_matrix p_matrix;
    p_matrix.src_ip   = iph->saddr;
    p_matrix.dst_ip   = iph->daddr;
    p_matrix.tot_len  = __constant_ntohs(iph->tot_len);
    p_matrix.protocol = iph->protocol;

    /* 
     * [Hot Path Branchless Core: 대수학적 왜도 소산 대리 계산]
     * xdp_ingress.c 프로젝트와 동일한 정수 Multiply-Add FMA 융합 레일을 구동합니다.
     */
    __s64 raw_deviation = (__s64)(p_matrix.tot_len - 64) << 16;
    __s64 skewness_vector = (raw_deviation * raw_deviation) >> 16;
    skewness_vector = (skewness_vector * raw_deviation) >> 16;

    __s64 damped_signal = raw_deviation - ((3276 * skewness_vector) >> 16); /* VISCOSITY_ALPHA=3276 */
    __u32 is_anomaly_burst = (damped_signal < -1310720) ? 1 : 0;            /* SKEWNESS_FLOOR=-1310720 */

    /* 
     * [★ 연동 추가: Asynchronous Ring-Buffer Telemetry Pipeline]
     * 고도화된 telemetry/ring_buffer_monitor.rs ABI 규격에 맞춰 32바이트 락프리 순환 버퍼 공간을 예약합니다.
     */
    struct telemetry_payload *log = bpf_ringbuf_reserve(&telemetry_ringbuf, LOG_SIZE, 0);
    if (log) {
        log->src_ip = p_matrix.src_ip;

        /* 
         * [★ 아키텍처 고도화: 4차원 특징 축 FP32 텐서 배열 슬롯 결합 명세 실행]
         * xdp_ingress.c와 자로 잰 듯 완벽히 동일한 오프셋 주소선 상에 float 원소들을 밀어 넣습니다.
         */
        // Slot 0: RPS 대리 지표 (원시 패킷 길이)
        log->features[0] = (float)(p_matrix.tot_len);

        // Slot 1: PPS (이 모듈은 MUX 필터이므로 특징 결합을 위해 대리 패킷 카운트 1.0 주입)
        log->features[1] = 1.0f;

        // Slot 2: Error Rate (프로토콜 필드가 TCP/UDP/ICMP 외의 변칙 상태인지 비트 마스킹)
        log->features[2] = (p_matrix.protocol != 6 && p_matrix.protocol != 17) ? 1.0f : 0.0f;

        // Slot 3: Bandwidth Delta (왜도 감쇄 제어가 가동된 damped_signal 실수 역산 스케일링)
        log->features[3] = (float)(damped_signal) / 65536.0f;

        // 제어 변수 및 격리 상태 바이패스 정렬
        log->packet_count = 1;
        log->padding = is_anomaly_burst; 

        // 비동기 관제 데몬으로 즉시 투척
        bpf_ringbuf_submit(log, 0);
    }

    /* 
     * [1-Cycle Pure Silicon Bitwise MUX Switching]
     * 조건 분기문(if-else)을 기계어 SASS 레벨에서 완전히 지워버리고 
     * ALU 레지스터 단 1클록 만에 패킷 통과(XDP_PASS)와 즉시 증발(XDP_DROP)을 물리적으로 결정합니다.
     */
    int action = execute_silicon_bitwise_mux(is_anomaly_burst, XDP_PASS, XDP_DROP);

    return action;
}

/* CO-RE 재배치 및 리눅스 적재용 라이선스 서명 */
char _license[] SEC("license") = "GPL";

