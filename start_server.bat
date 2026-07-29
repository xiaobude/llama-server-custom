@echo off
rem Tailored llama-server launch script for Windows 11 (Intel i5-13400 + NVIDIA RTX 5060 Ti 16GB)

set SERVER_BIN=llama-server.exe
set MODEL_PATH=%~1
if "%MODEL_PATH%"=="" set MODEL_PATH=models\qwen2.5-7b-instruct-q4_k_m.gguf
set PORT=8080

if not exist "%SERVER_BIN%" (
    echo [!] llama-server.exe 不存在，请解压 GitHub Releases 下载的 zip 包到当前目录。
    pause
    exit /b 1
)

echo =========================================================
echo  启动 Windows 11 硬件定制版 llama-server
echo  GPU: NVIDIA RTX 5060 Ti (16GB VRAM) -^> 全层 GPU Offload (-ngl 99)
echo  CPU: Intel i5-13400 (性能核 6，线程 12) -^> (-t 6 --flash-attn)
echo  服务端口: http://127.0.0.1:%PORT%
echo =========================================================

%SERVER_BIN% -m "%MODEL_PATH%" --host 0.0.0.0 --port %PORT% -ngl 99 -t 6 --flash-attn -c 8192 --alias "custom-llama-server"
pause
