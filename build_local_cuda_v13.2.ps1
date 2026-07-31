# build_local.ps1 - RTX 5060 Ti + i5-13400 本地极速编译脚本
$ErrorActionPreference = "Stop"

Write-Host "=== 正在启动本地极速编译 (RTX 5060 Ti + i5-13400) ===" -ForegroundColor Green

# 1. 检查或更新 llama.cpp 源码
if (-not (Test-Path "llama-source")) {
    Write-Host "1/4 正在克隆 llama.cpp 官方最新源码..." -ForegroundColor Cyan
    git clone --depth 50 https://github.com/ggml-org/llama.cpp.git llama-source
} else {
    Write-Host "1/4 llama-source 目录已存在，自动拉取最新 Release 标签与代码..." -ForegroundColor Cyan
    Set-Location llama-source
    git fetch --tags --force origin 2>$null
    git pull origin master 2>$null
    git pull origin main 2>$null
    Set-Location ..
}

Set-Location llama-source

# 2. 提取纯数字构建号 (如 10195)
$tagRaw = (git describe --tags --abbrev=0 2>$null)
if (-not $tagRaw) { $tagRaw = "b10195" }
$tagNum = [regex]::Match($tagRaw, '\d+').Value
if (-not $tagNum) { $tagNum = "10195" }
$commitHash = (git rev-parse --short HEAD 2>$null)
if (-not $commitHash) { $commitHash = "custom" }

Write-Host "2/4 提取最新版本信息: Build #$tagNum ($commitHash)" -ForegroundColor Cyan

# 3. 自动修补 CMakeLists.txt 实现 100% 静态 CUDA 绑定 (Zero DLL)
Get-ChildItem -Path . -Recurse -Filter "CMakeLists.txt" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace 'CUDA::cudart\b', 'CUDA::cudart_static'
    Set-Content $_.FullName $content
}

# 4. 清理并重建 build 目录以彻底排除上一次配置缓存
if (Test-Path "build") {
    Remove-Item -Path "build" -Recurse -Force
}
New-Item -ItemType Directory -Name "build" | Out-Null
Set-Location build

Write-Host "3/4 正在配置 CMake 参数 (针对 Blackwell sm_120 精确加速)..." -ForegroundColor Cyan
cmake .. -DCMAKE_BUILD_TYPE=Release `
  "-DLLAMA_BUILD_NUMBER=$tagNum" `
  "-DLLAMA_BUILD_COMMIT=$commitHash" `
  -DCMAKE_CUDA_RUNTIME_LIBRARY=Static `
  -DBUILD_SHARED_LIBS=OFF `
  -DGGML_CUDA=ON `
  -DGGML_CUDA_FORCE_CUBLAS=OFF `
  -DCMAKE_CUDA_ARCHITECTURES="120" `
  -DGGML_CUDA_FA_ALL_QUANTS=ON `
  -DLLAMA_BUILD_EXAMPLES=OFF `
  -DLLAMA_BUILD_TESTS=OFF `
  -DLLAMA_BUILD_SERVER=ON `
  -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON

# 5. 调用 MSVC 16 线程全速并行编译
Write-Host "4/4 正在进行多核并行编译 (-j 16)..." -ForegroundColor Cyan
cmake --build . --config Release --target llama-server -j 16

Set-Location ..\..

# 6. 复制生成的二进制到当前目录
$exe = Get-ChildItem -Path "llama-source\build" -Recurse -Filter "llama-server.exe" | Select-Object -First 1
if ($exe) {
    Copy-Item $exe.FullName -Destination ".\llama-server.exe" -Force
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "恭喜！最新 Build #$tagNum 编译成功！" -ForegroundColor Green
    Write-Host "已将最新 llama-server.exe 生成至本地目录。" -ForegroundColor Green
    Write-Host "版本验证: .\llama-server.exe --version" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Green
}
