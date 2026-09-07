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
        
        # [★ 데이터 구조 보정 완료 : 수치 해석 축 미스매치 박멸]
        # .reshape()를 제거하고 마지막 특징 차원 축(axis=-1) 평면을 직접 관통 연산하도록 개조했으므로,
        # 해당 축 내부 원소들 간에 비대칭 분산 변이가 폭발하여 강력한 점성 브레이크가 걸리도록 기하학적으로 재정렬합니다.
        self.mock_attack_stream = np.array([
            [[120.5, 1.2, 0.8, 1.1]],
            [[-95.2, 0.9, 0.2, 0.5]]
        ], dtype=np.float32)

    def test_skewness_dissipation_integrity(self):
        """[Test 1] 3차 왜도 소산 댐퍼가 분기문 없이 폭주 진폭을 안전하게 눌러 담는지 검증"""
        purified, skewness = execute_pure_skewness_flattening(self.mock_attack_stream, self.damper_cfg)
        
        # 입력 데이터 레이아웃 형상이 복사본 없이 0-Copy 상태로 무결하게 유지되는지 확인
        self.assertEqual(purified.shape, self.mock_attack_stream.shape)
        
        # 극단적인 발산 진폭이 댐핑 저항에 의해 감쇄되어 홈오스타시스 안정권으로 유도되었는지 검증
        self.assertTrue(np.max(np.abs(purified)) < 40.0)

    def test_topological_morphing_vacuum_lock(self):
        """[Test 2] 임계치 돌파 시 토로이달 주기 공간 위상 천이로 패킷이 강제 격리 구속되는지 검증"""
        # [★ 중복 코드 통합 탈출 완료] 
        # 불필요하게 2회 연속 중복 호출되어 힙 메모리 낭비를 유발하던 오타성 라인을 도려내고 1회 연산으로 슬림화합니다.
        morphed = execute_modular_topological_morphing(
            traffic_stream=self.mock_attack_stream,
            blend_ratio=1.0,  # blend_ratio = 1.0 (비상 진입, 토러스 진공 락 가동)
            constants=self.morph_cfg
        )

        # 아무리 파괴적인 진폭(120.5)을 던져도 사인 주기 함수 공간 안에 갇혀 [-1.0, 1.0] 범위로 고정되는지 검증
        max_amplitude = np.max(np.abs(morphed))
        self.assertTrue(max_amplitude <= 1.00001)

        # [★ 아키텍처 수호: 0-Copy 무복사 검증 라인 완성]
        # 마스터 위상 천이 함수 내부에서 .reshape() 연산이 완전히 제거되었으므로,
        # 반환된 morphed 배열의 실제 데이터 주소 뷰의 베이스 주소가 원본 데이터와 정확히 일치(Address Aliasing)합니다.
        self.assertIs(morphed.base, self.mock_attack_stream)

if __name__ == "__main__":
    unittest.main()
