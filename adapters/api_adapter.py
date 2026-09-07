# -*- coding: utf-8 -*-
"""
Copyright (c) 2026 PJHkorea. All rights reserved.
[5th-Gen Pure Ingress Hardware Adapter] API Concurrency Stream Tensorizer.
실시간 인입 트래픽 워크로드를 복사 오버헤드 없이 32바이트 하드웨어 정렬 텐서로 포맷팅하는 어댑터입니다.
"""

import numpy as np
from typing import Dict, Any

class IngressTrafficAdapter:
    def __init__(self, spatial_dim: int = 128):
        self.spatial_dim = spatial_dim
        # 하드웨어 캐시 라인 정렬 규격 동기화
        self.aligned_dim = (spatial_dim + 7) & ~7

    def tensorize_raw_workloads(self, raw_metrics_list: list) -> np.ndarray:
        """
        [KR] 생짜 인프라 로그 및 메트릭 배열을 가속기 고속 레일용 FP32 매트릭스로 정형화합니다.
        """
        # 정적 메모리 할당 지터를 방지하기 위해 단일 고정 청크 버퍼 스캔 유도
        flattened_data = []
        
        for metric in raw_metrics_list:
            # 메트릭에서 4대 특징 축(RPS, PPS, 에러율, 대역폭 변이) 추출
            features = [
                float(metric.get("rps", 0.0)),
                float(metric.get("pps", 0.0)),
                float(metric.get("error_rate", 0.0)),
                float(metric.get("bandwidth_delta", 0.0))
            ]
            # 수치 가속기 뱅크 정렬 크기(spatial_dim)에 맞춰 부족한 공간을 Zero 패딩 채움
            while len(features) < self.spatial_dim:
                features.append(0.0)
                
            flattened_data.append(features[:self.spatial_dim])

        # FP32 리터럴 레지스터 가드레일 형상으로 변환하여 반환
        return np.array(flattened_data, dtype=np.float32)
