# Tailored llama-server for Hardware (RTX 5060 Ti 16GB + Intel i5-13400)

本仓库提供针对 **NVIDIA GeForce RTX 5060 Ti (16GB VRAM)** + **Intel Core i5-13400 CPU** 极致定制的 `llama-server` 远程 GitHub Actions 自动编译工作流。

## 硬件优化定制说明

1. **GPU 硬件加速**:
   - 开启 `-DGGML_CUDA=ON`
   - 目标 Compute Architecture 涵盖 Ampere/Ada/Blackwell (`75;80;86;89;90`)
   - 开启 FlashAttention (`-DGGML_CUDA_FA_ALL_QUANTS=ON`)
2. **CPU 指令集与精简**:
   - 开启 `AVX2` / `FMA` / `F16C` 指令支持
   - 剥离所有未使用的异构后端 (Vulkan, SYCL, Kompute)
   - 剥离所有 30+ 冗余测试工具与示例程序，仅生成与保留单一极简可执行二进制 `llama-server`
3. **极简体积与发布**:
   - `strip` 符号表剔除调试冗余
   - 自动打包为 `llama-server-rtx5060ti-linux-x64.tar.gz` 供一键下载

## 使用方法

1. 触发 GitHub Actions 远程编译:
   ```bash
   gh workflow run build-llama-server.yml
   ```
2. 查看编译状态:
   ```bash
   gh run watch
   ```
3. 下载编译完成的 Artifact:
   ```bash
   gh run download
   ```
4. 运行服务:
   ```bash
   ./start_server.sh /path/to/your/model.gguf
   ```
## 关于本地编译
   build_local_cuda_v12.8.ps1 、build_local_cuda_v13.2.ps1 两个文件分别使用cuda v12.8 /cuda v13.2在本地极速编译出llama-server.exe单文件
