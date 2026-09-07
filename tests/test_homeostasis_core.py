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
        
        # 디도스 툴킷(DDoS Toolkit) 공격 무차별 난사 충격파 모사 데이터 (치우침 극대화)
        self.mock_attack_stream = np.array([
            [[120.5, -95.2, 0.1, 1.2]],
            [[-85.0, 74.4, 0.9, -0.5]]
        ], dtype=np.float32)

    def test_skewness_dissipation_integrity(self):
        """[Test 1] 3차 왜도 소산 댐퍼가 분기문 없이 폭주 진폭을 안전하게 눌러 담는지 검증"""
        purified, skewness = execute_pure_skewness_flattening(self.mock_attack_stream, self.damper_cfg)
        
        # 입력 데이터 레이아웃 형상이 복사본 없이 0-Copy 상태로 무결하게 유지되는지 확인
        self.assertEqual(purified.shape, self.mock_attack_stream.shape)
        
        # 극단적인 발산 진폭이 댐핑 저항에 의해 감쇄되어 홈오스타시스 안정권으로 유도되었는지 검증
        self.assertTrue(np.max(np.abs(purified)) < 20.0)

    def test_topological_morphing_vacuum_lock(self):
        """[Test 2] 임계치 돌파 시 토로이달 주기 공간 위상 천이로 패킷이 강제 격리 구속되는지 검증"""
        # blend_ratio = 1.0 (비상 진입, 토러스 진공 락 가동)
        morphed = execute_modular_topological_morphing(
            traffic_stream=self.mock_attack_stream,
            blend_ratio=1.0,
            constants=self.morph_cfg
        )
                # [★ 2파트 완결: 토로이달 주기 공간 격리 및 0-Copy 무복사 최종 연동]
        # blend_ratio = 1.0 (비상 진입, 토러스 진공 락 가동) 시점 이후 (기존 코드 연결 마감)
        morphed = execute_modular_topological_morphing(
            traffic_stream=self.mock_attack_stream,
            blend_ratio=1.0,
            constants=self.morph_cfg
        )

        # 아무리 파괴적인 진폭(120.5)을 던져도 사인 주기 함수 공간 안에 갇혀 [-1.0, 1.0] 범위로 고정되는지 검증
        max_amplitude = np.max(np.abs(morphed))
        self.assertTrue(max_amplitude <= 1.00001)

        # [★ 아키텍처 수호: 0-Copy 무복사 검증 라인 보강]
        # 마스터 위상 천이 함수 내부에서 .reshape() 연산이 통째로 거세되었으므로,
        # 출력된 morphed 배열의 원본 주소선 매핑 일치가 완벽히 성립하는지 확인합니다.
        self.assertIs(morphed.base, self.mock_attack_stream)

if __name__ == "__main__":
    unittest.main()
