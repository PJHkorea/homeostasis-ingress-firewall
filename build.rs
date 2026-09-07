// build.rs
fn main() {
    // 1. 하드웨어 소스 의존성 변경 감지 트리거 (Jitter 없는 지능형 증분 컴파일)
    // skewness_kernel.cu 파일의 소스코드가 수정될 때만 nvcc 컴파일러를 재구동합니다.
    println!("cargo:rerun-if-changed=../target-hardware-cuda/skewness_kernel.cu");

    // 2. NVIDIA NVCC 호스트 가속 컴파일러 파이프라인 빌드업
    cc::Build::new()
        // 대상 CUDA 소스 파일 바인딩
        .file("../target-hardware-cuda/skewness_kernel.cu")
        // 엔비디아 컴파일러 레일 강제 지정
        .cuda(true)
        // [★ 하드웨어 아키텍처 최적화 플래그 체인]
        // -O3             : GPU 레지스터 파이프라인 연산 전역 압축 최적화 최대화
        // --use_fast_math : 하드웨어 내장 기계어(SFU 연산 및 나눗셈 역수 팩토리 rsqrtf 등) 강제 변환 가동
        .flag("-O3")
        .flag("--use_fast_math")
        // sm_80           : 타겟 하드웨어(NVIDIA A100 등) 암페어 아키텍처 코어 하드웨어 최적화 바이너리 유도
        .flag("-gencode=arch=compute_80,code=sm_80")
        // 정적 라이브러리 컴파일 집행
        .compile("skewness_kernel");

    // 3. 엔비디아 CUDA 물리 가속 하위 드라이버 링커 경로 세팅
    // NVCC 컴파일 산출물과 Rust 기계어가 결합할 때 물리 주소 공간을 찾을 수 있도록 버스선 매핑
    println!("cargo:rustc-link-search=native=/usr/local/cuda/lib64");
    
    // 4. CUDA 런타임(cudart) 공유 메모리 가속 버스 링킹 선언
    // 하드웨어 메모리 드라이버 API(cudaStream_t, cudaMalloc 등)를 Rust 레지스터 레벨에서 다이렉트 융합 링크
    println!("cargo:rustc-link-lib=dylib=cudart");
}
