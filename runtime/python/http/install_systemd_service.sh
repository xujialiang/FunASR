#!/bin/bash
# 安装 FunASR Speaker Server 为 systemd 服务
# 提供自动重启、开机自启等功能（推荐用于生产环境）

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取当前目录
WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="funasr-speaker"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 获取当前用户和 Python 路径
CURRENT_USER=$(whoami)
PYTHON_PATH=$(which python3 || which python)

if [ -z "$PYTHON_PATH" ]; then
    echo -e "${RED}错误: 未找到 Python 解释器${NC}"
    exit 1
fi

echo "=================================================="
echo "FunASR Speaker Server - Systemd 服务安装"
echo "=================================================="
echo ""
echo "配置信息:"
echo "  服务名称:   $SERVICE_NAME"
echo "  工作目录:   $WORKING_DIR"
echo "  运行用户:   $CURRENT_USER"
echo "  Python路径: $PYTHON_PATH"
echo ""
echo "服务特性:"
echo "  ✓ 意外退出自动重启"
echo "  ✓ 开机自动启动"
echo "  ✓ 日志记录到 journald"
echo "=================================================="
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}注意: 需要 root 权限来安装 systemd 服务${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 读取服务文件模板
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=FunASR HTTP Server with Speaker Diarization
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$WORKING_DIR
Environment="PYTHONUNBUFFERED=1"
Environment="MODELSCOPE_CACHE=/tmp/modelscope"

# 启动命令
ExecStart=$PYTHON_PATH $WORKING_DIR/server_with_speaker.py --host 0.0.0.0 --port 8000 --asr_model paraformer-zh --vad_model fsmn-vad --punc_model ct-punc-c --spk_model cam++ --spk_mode punc_segment --device cpu --ngpu 0 --ncpu 4

# 自动重启配置
Restart=always
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

# 标准输出和错误日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=funasr-speaker

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ 服务文件已创建: $SERVICE_FILE${NC}"

# 重载 systemd
systemctl daemon-reload
echo -e "${GREEN}✓ systemd 配置已重载${NC}"

# 启用服务（开机自启）
systemctl enable "$SERVICE_NAME"
echo -e "${GREEN}✓ 服务已设置为开机自启${NC}"

echo ""
echo "=================================================="
echo -e "${GREEN}安装完成！${NC}"
echo "=================================================="
echo ""
echo "常用命令:"
echo "  启动服务:   sudo systemctl start $SERVICE_NAME"
echo "  停止服务:   sudo systemctl stop $SERVICE_NAME"
echo "  重启服务:   sudo systemctl restart $SERVICE_NAME"
echo "  查看状态:   sudo systemctl status $SERVICE_NAME"
echo "  查看日志:   sudo journalctl -u $SERVICE_NAME -f"
echo "  禁用自启:   sudo systemctl disable $SERVICE_NAME"
echo ""
echo "是否立即启动服务? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    systemctl start "$SERVICE_NAME"
    echo -e "${GREEN}✓ 服务已启动${NC}"
    sleep 2
    systemctl status "$SERVICE_NAME" --no-pager
fi
