"""
Copyright (c) 2026 PJHkorea. All rights reserved.
[Pure Hardware Controller Sandbox] Homeostasis Core Integrity Unit Test.
A test suite that autonomously verifies the mathematical integrity of skewness dissipation and phase shift geometric components.
"""

import unittest
import numpy as np
import sys
import os

# Enforce binding of the core formula directory path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core_formula.skewness_damper import initialize_damper_constants, execute_pure_skewness_flattening
from core_formula.topology_morph import initialize_morph_constants, execute_modular_topological_morphing

class TestHomeostasisIngressFirewall(unittest.TestCase):
    def setUp(self):
        self.spatial_dim = 4
        self.damper_cfg = initialize_damper_constants(self.spatial_dim)
        self.morph_cfg = initialize_morph_constants(self.spatial_dim)
        
        # [Telemetry Synchronization Complete]
        # Injects a 1:1 symmetric matrix matching the active FP32 tensor specifications processed by the C kernel and Rust proxy.
        # Layout: [Batch=2, Time=1, Feature=4] 
        # Feature Slots: [RPS, PPS, ErrorRate, BandwidthDelta]
        # Geometrically aligns data to introduce extreme asymmetric variance curves within the feature dimension plane (axis=-1).
        self.mock_attack_stream = np.array([
            [[15000.0, 450000.0, 0.01, 88.5]],
            [[12000.0, 320000.0, 0.05, -62.4]]
        ], dtype=np.float32)

    def test_skewness_dissipation_integrity(self):
        """[Test 1] Verifies whether the 3rd-order skewness damper safely attenuates anomalous peaks without branch instructions"""
        purified, skewness = execute_pure_skewness_flattening(self.mock_attack_stream, self.damper_cfg)
        
        # Verifies if the input data layout shape remains intact under a zero-copy state without transient allocations
        self.assertEqual(purified.shape, self.mock_attack_stream.shape)
        
        # [Numerical Margin Calibration] Verifies if extreme divergence amplitudes are attenuated 
        # by the damping resistance to guide the stream back within the homeostasis threshold boundary.
        self.assertTrue(np.max(np.abs(purified)) < 400000.0)
        
        # [Zero-Copy Validation]
        # Eliminates .reshape overhead inside the master function, ensuring that return tensor memory address mappings match exactly.
        self.assertIs(purified.base, skewness.base)

    def test_topological_morphing_vacuum_lock(self):
        """[Test 2] Verifies whether packets are strictly isolated and confined via toroidal periodic space phase shifts upon threshold breaches"""
        # [Redundant Code Elimination]
        # Removes consecutive duplicate calls that induced unnecessary heap allocations and optimizes it into a single execution path.
        morphed = execute_modular_topological_morphing(
            traffic_stream=self.mock_attack_stream,
            blend_ratio=1.0,  # blend_ratio = 1.0 (Emergency state activation, Toroidal vacuum lock deployed)
            constants=self.morph_cfg
        )

        # Verifies if destructive packet amplitudes are permanently confined within the trigonometric domain [-1.0, 1.0] under toroidal morphing
        max_amplitude = np.max(np.abs(morphed))
        self.assertTrue(max_amplitude <= 1.00001)

        # [Zero-Copy Architecture Verification]
        # Since .reshape() operations are completely eliminated from the master function, 
        # the base address of the returned morphed array view strictly matches the original input data layer (Address Aliasing).
        self.assertIs(morphed.base, self.mock_attack_stream)

if __name__ == "__main__":
    unittest.main()
