# build_local.ps1 - RTX 5060 Ti + i5-13400 本地极速编译脚本
# 注：cudart / cublasLt 可以做到零 DLL，cublas64_*.dll 在 Windows 上没有静态版可选，
#     会被自动拷贝到 exe 同目录，这是 NVIDIA 的平台限制，不是配置错误。
$ErrorActionPreference = "Stop"
Write-Host "=== 正在启动本地极速编译 (RTX 5060 Ti + i5-13400) ===" -ForegroundColor Green

# 0. 强制本次会话使用 CUDA 12.8 编译（不改动系统级 CUDA_PATH，只影响本脚本进程）
#    原因：CUDA 13.x 在 Blackwell(sm_120) 上会让 MMQ 量化矩阵乘 kernel 崩溃/回退到更慢的 cuBLAS 路径，
#    NVIDIA 官方也建议用 12.8 编译 sm_120。你系统变量 CUDA_PATH 指向的是 v13.2，这里临时覆盖。
$cuda128Root = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
if (Test-Path $cuda128Root) {
    $env:CUDA_PATH = $cuda128Root
    $env:PATH = "$cuda128Root\bin;$env:PATH"
    Write-Host "0/5 已将本次编译临时切换到 CUDA 12.8 ($cuda128Root)" -ForegroundColor Cyan
} else {
    Write-Host "0/5 警告：未找到 $cuda128Root，本次将回退使用系统默认 CUDA_PATH ($env:CUDA_PATH)。" -ForegroundColor Yellow
    Write-Host "        已知 CUDA 13.x 在 Blackwell(sm_120) 上 MMQ kernel 可能崩溃回退到更慢的 cuBLAS，建议单独安装 CUDA 12.8。" -ForegroundColor Yellow
}
$nvccVersion = & nvcc --version 2>&1 | Select-String "release"
Write-Host "        当前 nvcc: $nvccVersion" -ForegroundColor Cyan

# 1. 检查或更新 llama.cpp 源码
if (-not (Test-Path "llama-source")) {
    Write-Host "1/5 正在克隆 llama.cpp 官方最新源码..." -ForegroundColor Cyan
    git clone --depth 50 https://github.com/ggml-org/llama.cpp.git llama-source
    if ($LASTEXITCODE -ne 0) { throw "git clone 失败，退出码 $LASTEXITCODE，请检查网络" }
} else {
    Write-Host "1/5 llama-source 目录已存在，自动同步官方最新代码 (git pull)..." -ForegroundColor Cyan
    Set-Location llama-source
    $pulled = $false
    git pull origin master
    if ($LASTEXITCODE -eq 0) { $pulled = $true }
    if (-not $pulled) {
        git pull origin main
        if ($LASTEXITCODE -eq 0) { $pulled = $true }
    }
    if (-not $pulled) {
        Write-Warning "git pull 失败（两个分支都没拉成功），本次将使用本地已有的旧代码继续编译，请检查网络！"
    }
    Set-Location ..
}
Set-Location llama-source

# 2. 提取真实构建号（浅克隆下 git describe 基本取不到 tag，改用 GitHub API 查最新 release）
$tagRaw = ""
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
    $tagRaw = $release.tag_name
} catch { $tagRaw = "" }
$tagNum = [regex]::Match($tagRaw, '\d+').Value
if (-not $tagNum) { $tagNum = "0" }
$commitHash = (git rev-parse --short HEAD 2>$null)
if (-not $commitHash) { $commitHash = "custom" }
Write-Host "2/5 提取版本信息: Build #$tagNum ($commitHash)" -ForegroundColor Cyan

# 3. 自动修补 CMakeLists.txt，静态化 cudart 和 cublasLt（Zero DLL 能做到的部分）
#    重要：NVIDIA 官方从未在 Windows 上提供 cuBLAS 的静态库（CUDA::cublas_static 这个 target
#    在 Windows 下压根不存在），只有 Linux/macOS 有。硬改会导致 CMake 配置直接报错
#    "Target ggml-cuda links to: CUDA::cublas_static but the target was not found"。
#    所以 cublas 这里必须保留动态链接，cublas64_*.dll 是 Windows 上唯一没法消灭、
#    必须跟 exe 一起分发的一个 DLL（后面第 6 步会自动帮你拷贝到输出目录）。
Get-ChildItem -Path . -Recurse -Filter "CMakeLists.txt" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace 'CUDA::cudart\b', 'CUDA::cudart_static'
    $content = $content -replace 'CUDA::cublasLt\b', 'CUDA::cublasLt_static'
    # 上游代码只要检测到 BUILD_SHARED_LIBS=OFF，自己就会切去引用 CUDA::cublas_static，
    # 这个 target 在 Windows 上从来没有提供过，直接把它改回可用的动态版本，不管上游是怎么触发到这里的。
    $content = $content -replace 'CUDA::cublas_static\b', 'CUDA::cublas'
    Set-Content $_.FullName $content
}

# 4. 清理并重建 build 目录以彻底排除上一次配置缓存
if (Test-Path "build") {
    Remove-Item -Path "build" -Recurse -Force
}
New-Item -ItemType Directory -Name "build" | Out-Null
Set-Location build
Write-Host "3/5 正在配置 CMake 参数 (针对 RTX 5060 Ti sm_120 精确加速)..." -ForegroundColor Cyan
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
  -DGGML_NATIVE=OFF `
  -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON
if ($LASTEXITCODE -ne 0) { throw "CMake 配置失败，退出码 $LASTEXITCODE" }

# 5. 调用 MSVC 并行编译（32GB 内存 + FA_ALL_QUANTS=ON 组合偏吃内存，如果编译中途卡死/报内存不足，把 -j 16 改成 -j 8 再试）
Write-Host "4/5 正在进行多核并行编译 (-j 16)..." -ForegroundColor Cyan
cmake --build . --config Release --target llama-server -j 16
if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码 $LASTEXITCODE" }
Set-Location ..\..

# 6. 复制生成的二进制到当前目录，自动补上唯一没法消灭的 cublas64_*.dll，并校验其余依赖
$exe = Get-ChildItem -Path "llama-source\build" -Recurse -Filter "llama-server.exe" | Select-Object -First 1
if ($exe) {
    Copy-Item $exe.FullName -Destination ".\llama-server.exe" -Force

    # cublas64_*.dll 在 Windows 上没有静态版可用，必须跟 exe 放一起才能跑；从当前用的 CUDA bin 目录里找出来拷过来
    $cublasDll = Get-ChildItem -Path "$env:CUDA_PATH\bin" -Filter "cublas64_*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cublasDll) {
        Copy-Item $cublasDll.FullName -Destination ".\$($cublasDll.Name)" -Force
        Write-Host "        已自动拷贝 $($cublasDll.Name)（Windows 上 cuBLAS 无静态版，这个 dll 必须跟 exe 放一起）" -ForegroundColor Cyan
    } else {
        Write-Warning "没能在 $env:CUDA_PATH\bin 下找到 cublas64_*.dll，请手动从 CUDA 安装目录拷贝到 exe 同目录"
    }

    Write-Host "5/5 正在校验静态链接是否生效 (dumpbin)..." -ForegroundColor Cyan
    $deps = & dumpbin /DEPENDENTS ".\llama-server.exe" 2>&1
    # cudart64 / cublasLt64 应该已经消失；cublas64 是预期中唯一还会出现的（Windows 平台限制，非 bug）
    if ($deps -match 'cudart64|cublasLt64') {
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "警告：cudart 或 cublasLt 仍然是动态依赖，静态化补丁没生效！" -ForegroundColor Red
        $deps | Select-String -Pattern 'cudart64|cublasLt64' | Write-Host
        Write-Host "==========================================" -ForegroundColor Red
    } else {
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "恭喜！编译成功，cudart/cublasLt 已确认静态化。" -ForegroundColor Green
        Write-Host "cublas64_*.dll 已自动拷到同目录（Windows 平台限制，这个 dll 没法消灭，正常现象）。" -ForegroundColor Green
        Write-Host "版本验证: .\llama-server.exe --version" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Green
    }
} else {
    Write-Error "编译似乎失败了：在 llama-source\build 下没有找到 llama-server.exe"
}