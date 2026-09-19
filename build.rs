// build.rs
fn main() {
    // 1. Hardware source dependency alteration detection trigger
    // Monitors the target_hardware_cuda directory specifications for static FFI rebuilding routines.
    println!("cargo:rerun-if-changed=../target_hardware_cuda/skewness_kernel.cu");

    // 2. NVIDIA NVCC host accelerator compiler pipeline build configuration
    cc::Build::new()
        // Maps the explicit physical path binding of the targeted CUDA source asset
        .file("../target_hardware_cuda/skewness_kernel.cu")
        // Enforces the native NVIDIA compilation compiler toolchain path
        .cuda(true)
        // [Hardware Architecture Optimization Flag Chain]
        // -O3             : Maximizes global compression optimization levels for the GPU register pipeline
        // --use_fast_math : Enforces high-speed hardware intrinsic machine code operations (SFU execution, fast reciprocal square roots rsqrtf, etc.)
        .flag("-O3")
        .flag("--use_fast_math")
        // sm_80           : Target system architecture optimized bin generation (NVIDIA A100 Ampere core hardware layout tuning)
        .flag("-gencode=arch=compute_80,code=sm_80")
        // Compiles the static library payload
        .compile("skewness_kernel");

    // 3. Configure linking search paths for the low-level NVIDIA CUDA hardware accelerator drivers
    // Maps the interface layer to bind compiled NVCC outputs with native Rust machine code memory boundaries.
    println!("cargo:rustc-link-search=native=/usr/local/cuda/lib64");
    
    // 4. Declare dynamic linking bindings for the CUDA Runtime (cudart) shared memory bus interface
    // Fuses hardware-level core memory APIs (cudaStream_t, cudaMalloc, etc.) directly into native Rust registers.
    println!("cargo:rustc-link-lib=dylib=cudart");
}
