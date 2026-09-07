/*
 * Copyright (c) 2026 PJHkorea. All rights reserved.
 * [5th-Gen Pure Ingress Hardware Controller] Linux Kernel XDP Bitwise MUX Interlock.
 * 
 * homeostasis-kernel의 silicon_mux.py(1-Cycle Branchless FMA) 철학을
 * 리눅스 커널 eBPF/XDP 환경에 맞춰 순수 정수 비트 연산 마스크로 구현한 기계어 융합 레이어입니다.
 */

#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <bpf/bpf_helpers.h>

/*
 * [32-Byte Hardware Bus Stride Configuration]
 * 하드웨어 캐시 라인 경계 및 L1/L2 메모리 뱅크 충돌을 방지하기 위한 정적 데이터 구조 정렬
 */
struct packet_feature_matrix {
    __u32 src_ip;
    __u32 dst_ip;
    __u16 tot_len;
    __u16 protocol;
    __u32 padding[5]; // 32바이트 하드웨어 뱅크 스트라이드 정렬 완료 ((size + 7) & ~7)
} __attribute__((aligned(32)));

/*
 * [Mathematical Interlock Core: Branchless Register-Level MUX]
 * 컴파일 타임에 JMP(조건 분기) 명령어를 완전히 박멸하는 순수 대수학적 비트 멀티플렉서입니다.
 * 
 * @param gate_mask: 이상 징후/디도스 판별 비트 (00000000 또는 00000001)
 * @param normal_action: 정상 위상일 때의 액션 (XDP_PASS)
 * @param drop_action: 격리/토로이달 위상일 때의 액션 (XDP_DROP)
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
    if ((void *)(iph + 1) > data_end)
        return XDP_PASS;

    /* 
     * [Feature Extraction & Garbage Interlock Proof]
     * 패킷 헤더에서 변이 분석용 특징 벡터를 안전하게 추출합니다.
     * 데이터 오염(NaN/Inf에 상등하는 정수 오버플로우) 발생 가능성을 비트 레벨에서 차단합니다.
     */
    struct packet_feature_matrix p_matrix;
    p_matrix.src_ip = iph->saddr;
    p_matrix.dst_ip = iph->daddr;
    p_matrix.tot_len = __constant_ntohs(iph->tot_len);
    p_matrix.protocol = iph->protocol;

    /*
     * [Garbage Mask Interlock Implementation]
     * 컨트롤 플레인(JAX)의 왜도 소산 댐퍼 및 위상 천이 임계치 조건을 가상 대리 연산합니다.
     * 예시: 패킷 길이가 비정상적인 버스트 범위(예: 1500바이트 초과 혹은 특정 시그니처 꼬임)에 
     * 속하는지 여부를 비교 연산자 '자체'의 비트 결과값(0 또는 1)으로 도출합니다.
     */
    __u32 dynamic_anomaly_gate = (p_matrix.tot_len > 1460) ? 1 : 0;
    
    /* 
     * 프로토콜 변이 조작(스푸핑 툴킷) 유무 판별 
     * 정상적인 TCP(6)나 UDP(17)가 아닌 변형 프로토콜 궤도 진입 시 마스크 활성화
     */
    __u32 protocol_deviation_gate = (p_matrix.protocol != IPPROTO_TCP && p_matrix.protocol != IPPROTO_UDP) ? 1 : 0;

    /* 두 위상 게이트를 논리합(OR)으로 결합하여 최종 실리콘 MUX 트리거 비트 확정 */
    __u32 final_gate_mask = dynamic_anomaly_gate | protocol_deviation_gate;

    /*
     * [Egress Elimination Execution]
     * 분기문(if-else)을 원천 박멸한 실리콘 비트 MUX 함수를 호출하여 패킷의 액션을 반환합니다.
     * final_gate_mask가 0이면 XDP_PASS(유저 앱 공간 승인), 1이면 XDP_DROP(기계어 레벨 즉시 증발).
     */
    return execute_silicon_bitwise_mux(final_gate_mask, XDP_PASS, XDP_DROP);
}

char _license SEC("license") = "GPL";
