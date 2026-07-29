#!/bin/bash
# Tailored llama-server launch script for Intel i5-13400 + NVIDIA RTX 5060 Ti 16GB

SERVER_BIN="./llama-server"
MODEL_PATH="${1:-./models/qwen2.5-7b-instruct-q4_k_m.gguf}"
PORT=8080

if [ ! -f "$SERVER_BIN" ]; then
    echo "[!] llama-server 可执行文件不存在，请先从 GitHub Releases/Artifacts 下载解压到当前目录。"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "[!] 提示: 模型文件 $MODEL_PATH 未找到。"
    echo "[!] 请下载 GGUF 模型并传入模型路径，例如: ./start_server.sh /path/to/your/model.gguf"
fi

echo "========================================================="
echo " 启动硬件定制版 llama-server"
echo " GPU: NVIDIA RTX 5060 Ti (16GB VRAM) -> 全层 GPU Offload (-ngl 99)"
echo " CPU: Intel i5-13400 (性能核 6，线程 12) -> (-t 6 --flash-attn)"
echo " 服务端口: http://0.0.0.0:$PORT"
echo "========================================================="

$SERVER_BIN \
    -m "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port $PORT \
    -ngl 99 \
    -t 6 \
    --flash-attn \
    -c 8192 \
    --alias "custom-llama-server"
