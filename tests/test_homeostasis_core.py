# -*- coding: utf-8 -*-
"""
Copyright (c) 2026 PJHkorea. All rights reserved.
[5th-Gen Pure Hardware Controller Sandbox] Homeostasis Core Integrity Unit Test.
왜도 소산 및 위상 천이 기하학 컴포넌트의 수리적 무결성을 자율 검증하는 테스트 스위트입니다.
"""

import unittest
import numpy as np
import sys
import os

# 코어 수식 디렉토리 경로 강제 바인딩
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core_formula.skewness_damper import initialize_damper_constants, execute_pure_skewness_flattening
from core_formula.topology_morph import initialize_morph_constants, execute_modular_topological_morphing

class TestHomeostasisIngressFirewall(unittest.TestCase):
    def setUp(self):
        self.spatial_dim = 4
        self.damper_cfg = initialize_damper_constants(self.spatial_dim)
        self.morph_cfg = initialize_morph_constants(self.spatial_dim)
        
        # [★ 텔레메트리 고도화 연동 반영 완료] 
        # C 커널 및 Rust 프록시가 가공하는 실제 FP32 텐서 스펙과 1:1 대칭 주입
        # 레이아웃: [Batch=2, Time=1, Feature=4] 
        # 특징 슬롯: [RPS, PPS, ErrorRate, BandwidthDelta]
        # 특징 차원 축(axis=-1) 평면 내부에서 극단적인 비대칭 분산 곡률 변이가 폭발하도록 기하학적으로 정렬합니다.
        self.mock_attack_stream = np.array([
            [[15000.0, 450000.0, 0.01, 88.5]],
            [[12000.0, 320000.0, 0.05, -62.4]]
        ], dtype=np.float32)

    def test_skewness_dissipation_integrity(self):
        """[Test 1] 3차 왜도 소산 댐퍼가 분기문 없이 폭주 진폭을 안전하게 눌러 담는지 검증"""
        purified, skewness = execute_pure_skewness_flattening(self.mock_attack_stream, self.damper_cfg)
        
        # 입력 데이터 레이아웃 형상이 복사본 없이 0-Copy 상태로 무결하게 유지되는지 확인
        self.assertEqual(purified.shape, self.mock_attack_stream.shape)
        
        # [★ 고도화 수치 마진 보정] 실제 표준형 float 스케일 텐서 데이터셋 인입에 따라 
        # 극단적인 발산 진폭이 댐핑 저항에 의해 감쇄되어 홈오스타시스 안정권으로 유도되었는지 검증
        self.assertTrue(np.max(np.abs(purified)) < 400000.0)
        
        # [★ 0-Copy 무복사 검증 보장 추가]
        # .reshape 오버헤드를 원천 거세했으므로, 반환 텐서의 원본 주소선 매핑 일치가 완벽히 참(True)으로 귀결됩니다.
        self.assertIs(purified.base, skewness.base)

    def test_topological_morphing_vacuum_lock(self):
        """[Test 2] 임계치 돌파 시 토로이달 주기 공간 위상 천이로 패킷이 강제 격리 구속되는지 검증"""
        # [★ 중복 코드 통합 탈출 완료] 
        # 불필요하게 2회 연속 중복 호출되어 힙 메모리 낭비를 유발하던 오타성 라인을 도려내고 1회 연산으로 슬림화합니다.
        morphed = execute_modular_topological_morphing(
            traffic_stream=self.mock_attack_stream,
            blend_ratio=1.0,  # blend_ratio = 1.0 (비상 진입, 토러스 진공 락 가동)
            constants=self.morph_cfg
        )

        # 아무리 파괴적인 대역폭 진폭이 들어와도 사인 주기 함수 공간 안에 갇혀 [-1.0, 1.0] 범위로 고정(Confinement)되는지 검증
        max_amplitude = np.max(np.abs(morphed))
        self.assertTrue(max_amplitude <= 1.00001)

        # [★ 아키텍처 수호: 0-Copy 무복사 검증 라인 완성]
        # 마스터 위상 천이 함수 내부에서 .reshape() 연산이 완전히 제거되었으므로,
        # 반환된 morphed 배열의 실제 데이터 주소 뷰의 베이스 주소가 원본 데이터와 정확히 일치(Address Aliasing)합니다.
        self.assertIs(morphed.base, self.mock_attack_stream)

if __name__ == "__main__":
    unittest.main()
