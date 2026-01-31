#!/bin/bash
# FunASR HTTP Server with Speaker Diarization - 自动重启启动脚本
# 当服务意外退出时，会自动重启

# 配置参数
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
ASR_MODEL="${ASR_MODEL:-paraformer-zh}"
VAD_MODEL="${VAD_MODEL:-fsmn-vad}"
PUNC_MODEL="${PUNC_MODEL:-ct-punc-c}"
SPK_MODEL="${SPK_MODEL:-cam++}"
SPK_MODE="${SPK_MODE:-punc_segment}"
DEVICE="${DEVICE:-cpu}"
NGPU="${NGPU:-0}"
NCPU="${NCPU:-4}"

# 重启间隔（秒）
RESTART_DELAY="${RESTART_DELAY:-5}"
# 最大重启次数（0表示无限重启）
MAX_RESTARTS="${MAX_RESTARTS:-0}"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/server.log"
PID_FILE="${SCRIPT_DIR}/server.pid"

restart_count=0

# 清理函数
cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 正在停止服务..."
    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
    exit 0
}

# 捕获退出信号
trap cleanup SIGINT SIGTERM

echo "=================================================="
echo "FunASR Speaker Server - 自动重启模式"
echo "=================================================="
echo "配置信息:"
echo "  Host:      $HOST"
echo "  Port:      $PORT"
echo "  ASR Model: $ASR_MODEL"
echo "  VAD Model: $VAD_MODEL"
echo "  Punc Model:$PUNC_MODEL"
echo "  SPK Model: $SPK_MODEL"
echo "  SPK Mode:  $SPK_MODE"
echo "  Device:    $DEVICE"
echo "  NCPU:      $NCPU"
echo "  Log File:  $LOG_FILE"
echo "  Max Restarts: $MAX_RESTARTS (0=无限)"
echo "=================================================="

while true; do
    if [ "$MAX_RESTARTS" -gt 0 ] && [ "$restart_count" -ge "$MAX_RESTARTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 已达到最大重启次数 ($MAX_RESTARTS)，停止服务"
        break
    fi

    restart_count=$((restart_count + 1))
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动服务 (第 $restart_count 次)..."

    # 启动服务
    cd "$SCRIPT_DIR"
    nohup python server_with_speaker.py \
        --host "$HOST" \
        --port "$PORT" \
        --asr_model "$ASR_MODEL" \
        --vad_model "$VAD_MODEL" \
        --punc_model "$PUNC_MODEL" \
        --spk_model "$SPK_MODEL" \
        --spk_mode "$SPK_MODE" \
        --device "$DEVICE" \
        --ngpu "$NGPU" \
        --ncpu "$NCPU" \
        >> "$LOG_FILE" 2>&1 &

    PID=$!
    echo $PID > "$PID_FILE"

    # 等待进程结束
    wait $PID
    EXIT_CODE=$?

    rm -f "$PID_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 服务正常退出 (exit code: $EXIT_CODE)"
        break
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 服务异常退出 (exit code: $EXIT_CODE)，$RESTART_DELAY 秒后重启..."
        sleep $RESTART_DELAY
    fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动重启服务已停止"
