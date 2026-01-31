#!/bin/bash
# FunASR HTTP Server with Speaker Diarization - 自动重启启动脚本
# 当服务意外退出时，会自动重启
#
# 用法:
#   ./start_server_with_restart.sh [command]
#
# 命令:
#   start     后台启动服务（带自动重启）
#   stop      停止服务
#   status    查看服务状态
#   log       实时查看日志
#   restart   重启服务
#   (无参数)  前台运行（Ctrl+C 停止）
#

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
MONITOR_PID_FILE="${SCRIPT_DIR}/monitor.pid"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 启动服务（内部函数，用于前台或后台运行）
run_server() {
    local restart_count=0

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

    while true; do
        if [ "$MAX_RESTARTS" -gt 0 ] && [ "$restart_count" -ge "$MAX_RESTARTS" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 已达到最大重启次数 ($MAX_RESTARTS)，停止服务"
            break
        fi

        restart_count=$((restart_count + 1))
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动服务 (第 $restart_count 次)..."

        # 启动服务
        cd "$SCRIPT_DIR"
        python server_with_speaker.py \
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
    rm -f "$MONITOR_PID_FILE"
}

# 后台启动
do_start() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid
        monitor_pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 "$monitor_pid" 2>/dev/null; then
            echo -e "${YELLOW}服务已经在运行中 (monitor PID: $monitor_pid)${NC}"
            return 1
        fi
        rm -f "$MONITOR_PID_FILE"
    fi

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}FunASR Speaker Server - 后台启动${NC}"
    echo -e "${BLUE}==================================================${NC}"
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
    echo -e "${BLUE}==================================================${NC}"

    # 在后台运行监控循环
    (
        exec >> "$LOG_FILE" 2>&1
        run_server
    ) &

    local monitor_pid=$!
    echo $monitor_pid > "$MONITOR_PID_FILE"

    sleep 1

    if kill -0 "$monitor_pid" 2>/dev/null; then
        echo -e "${GREEN}✓ 服务已在后台启动${NC}"
        echo -e "  监控进程 PID: $monitor_pid"
        echo -e "  日志文件: $LOG_FILE"
        echo ""
        echo -e "查看日志: ${YELLOW}./start_server_with_restart.sh log${NC}"
        echo -e "停止服务: ${YELLOW}./start_server_with_restart.sh stop${NC}"
        return 0
    else
        echo -e "${RED}✗ 服务启动失败，请检查日志${NC}"
        rm -f "$MONITOR_PID_FILE"
        return 1
    fi
}

# 停止服务
do_stop() {
    echo -e "${BLUE}正在停止服务...${NC}"

    local killed=false

    # 停止监控进程
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid
        monitor_pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        if [ -n "$monitor_pid" ] && kill -0 "$monitor_pid" 2>/dev/null; then
            kill -TERM "$monitor_pid" 2>/dev/null
            sleep 1
            # 强制结束
            kill -KILL "$monitor_pid" 2>/dev/null
            echo -e "${GREEN}✓ 监控进程已停止 (PID: $monitor_pid)${NC}"
            killed=true
        fi
        rm -f "$MONITOR_PID_FILE"
    fi

    # 停止 Python 服务进程
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            # 强制结束
            kill -KILL "$pid" 2>/dev/null
            echo -e "${GREEN}✓ 服务进程已停止 (PID: $pid)${NC}"
            killed=true
        fi
        rm -f "$PID_FILE"
    fi

    # 尝试通过端口查找并结束进程
    local port_pids
    port_pids=$(lsof -t -i:$PORT 2>/dev/null || netstat -tlnp 2>/dev/null | grep ":$PORT " | awk '{print $NF}' | cut -d'/' -f1 | grep -o '[0-9]*')
    if [ -n "$port_pids" ]; then
        for p in $port_pids; do
            if kill -0 "$p" 2>/dev/null; then
                kill -TERM "$p" 2>/dev/null
                sleep 1
                kill -KILL "$p" 2>/dev/null
                echo -e "${GREEN}✓ 端口 $PORT 进程已停止 (PID: $p)${NC}"
                killed=true
            fi
        done
    fi

    if [ "$killed" = false ]; then
        echo -e "${YELLOW}服务未运行${NC}"
    else
        echo -e "${GREEN}✓ 服务已完全停止${NC}"
    fi
}

# 查看状态
do_status() {
    local running=false
    local monitor_pid=""
    local server_pid=""

    if [ -f "$MONITOR_PID_FILE" ]; then
        monitor_pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 "$monitor_pid" 2>/dev/null; then
            running=true
        fi
    fi

    if [ -f "$PID_FILE" ]; then
        server_pid=$(cat "$PID_FILE" 2>/dev/null)
    fi

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}FunASR Speaker Server - 状态${NC}"
    echo -e "${BLUE}==================================================${NC}"

    if [ "$running" = true ]; then
        echo -e "状态: ${GREEN}运行中${NC}"
        echo "监控进程 PID: $monitor_pid"
        echo "服务进程 PID: ${server_pid:-未知}"
        echo "监听端口: $PORT"
        echo "日志文件: $LOG_FILE"
    else
        echo -e "状态: ${RED}未运行${NC}"
    fi

    echo -e "${BLUE}==================================================${NC}"
}

# 查看日志
do_log() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}日志文件不存在: $LOG_FILE${NC}"
        return 1
    fi

    echo -e "${BLUE}正在监控日志 (按 Ctrl+C 退出)...${NC}"
    echo ""
    tail -f "$LOG_FILE"
}

# 重启服务
do_restart() {
    do_stop
    sleep 1
    do_start
}

# 前台运行
do_foreground() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}FunASR Speaker Server - 前台运行${NC}"
    echo -e "${BLUE}==================================================${NC}"
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
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    echo -e "${YELLOW}按 Ctrl+C 停止服务${NC}"
    echo ""

    run_server
}

# 显示帮助
do_help() {
    echo "FunASR Speaker Server - 自动重启启动脚本"
    echo ""
    echo "用法: $0 [command]"
    echo ""
    echo "命令:"
    echo "  start     后台启动服务（带自动重启）"
    echo "  stop      停止服务"
    echo "  status    查看服务状态"
    echo "  log       实时查看日志"
    echo "  restart   重启服务"
    echo "  help      显示帮助信息"
    echo ""
    echo "无参数时，默认在前台运行服务。"
    echo ""
    echo "环境变量配置:"
    echo "  HOST          监听地址 (默认: 0.0.0.0)"
    echo "  PORT          监听端口 (默认: 8000)"
    echo "  NCPU          CPU线程数 (默认: 4)"
    echo "  RESTART_DELAY 重启间隔秒数 (默认: 5)"
    echo ""
    echo "示例:"
    echo "  PORT=9000 $0 start        # 后台启动，使用端口9000"
    echo "  $0 log                     # 查看日志"
    echo "  $0 stop                    # 停止服务"
}

# 主程序入口
case "${1:-}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    status)
        do_status
        ;;
    log)
        do_log
        ;;
    restart)
        do_restart
        ;;
    help|--help|-h)
        do_help
        ;;
    "")
        do_foreground
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo ""
        do_help
        exit 1
        ;;
esac
