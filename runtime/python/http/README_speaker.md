# FunASR HTTP Server with Speaker Diarization

支持**说话人识别**的 HTTP API 服务，基于 FunASR 和 FastAPI 构建。

## 特性

- ✅ HTTP REST API 接口
- ✅ 语音识别 (ASR)
- ✅ 说话人识别/声纹分割 (Speaker Diarization)
- ✅ CPU 运行（无需 GPU）
- ✅ 无需 SSL（默认 HTTP）
- ✅ 支持热词
- ✅ 返回带时间戳和说话人 ID 的句子

## 快速开始

### 1. 环境准备

```bash
cd runtime/python/http
pip install -r requirements.txt
```

### 2. 启动服务（CPU 模式 + 说话人识别）

```bash
python server_with_speaker.py --port 8000
```

完整参数启动：

```bash
python server_with_speaker.py \
  --host 0.0.0.0 \
  --port 8000 \
  --asr_model paraformer-zh \
  --vad_model fsmn-vad \
  --punc_model ct-punc-c \
  --spk_model cam++ \
  --spk_mode punc_segment \
  --device cpu \
  --ngpu 0 \
  --ncpu 4
```

### 3. 测试服务

```bash
# 下载测试音频
wget https://isv-data.oss-cn-hangzhou.aliyuncs.com/ics/MaaS/ASR/test_audio/asr_example_zh.wav

# 使用客户端测试
python client_speaker.py --host=127.0.0.1 --port=8000 --audio_path=asr_example_zh.wav
```

## 参数说明

### 服务器参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--host` | 服务监听地址 | `0.0.0.0` |
| `--port` | 服务端口 | `8000` |
| `--device` | 运行设备 (`cpu` 或 `cuda`) | `cpu` |
| `--ngpu` | GPU 数量 (`0` 表示 CPU) | `0` |
| `--ncpu` | CPU 线程数 | `4` |

### 模型参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--asr_model` | 语音识别模型 | `paraformer-zh` |
| `--vad_model` | 语音活动检测模型 | `fsmn-vad` |
| `--punc_model` | 标点恢复模型 | `ct-punc-c` |
| `--spk_model` | 说话人识别模型 | `cam++` |
| `--spk_mode` | 说话人分割模式 (`punc_segment`/`vad_segment`/`default`) | `punc_segment` |

### 说话人分割模式说明

- `punc_segment`: 基于标点分割句子后进行说话人识别（推荐，效果更好）
- `vad_segment`: 基于 VAD 分割后进行说话人识别
- `default`: 默认模式

## API 接口

### 1. 语音识别 + 说话人识别

**URL**: `POST http://{host}:{port}/recognition`

**请求方式**: `multipart/form-data`

**参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `audio` | File | 音频文件（支持 wav, mp3, m4a 等格式） |

**返回格式**:

```json
{
  "text": "完整识别文本",
  "sentences": [
    {
      "text": "第一句话",
      "start": 0,
      "end": 2500,
      "spk": 0
    },
    {
      "text": "第二句话",
      "start": 2800,
      "end": 5000,
      "spk": 1
    }
  ],
  "spk_count": 2,
  "code": 0
}
```

### 2. 健康检查

**URL**: `GET http://{host}:{port}/health`

**返回**:

```json
{
  "status": "ok",
  "service": "funasr-speaker"
}
```

## 客户端使用

### Python 调用示例

```python
import requests

url = "http://127.0.0.1:8000/recognition"

files = [
    ("audio", ("test.wav", open("test.wav", "rb"), "application/octet-stream"))
]

response = requests.post(url, files=files)
result = response.json()

print(f"识别文本: {result['text']}")
print(f"说话人数量: {result['spk_count']}")

for sent in result['sentences']:
    print(f"[Speaker {sent['spk']}] {sent['text']}")
```

### 命令行客户端

```bash
# 文本格式输出
python client_speaker.py --audio_path=test.wav

# JSON 格式输出
python client_speaker.py --audio_path=test.wav --output_format=json

# SRT 字幕格式输出
python client_speaker.py --audio_path=test.wav --output_format=srt
```

### cURL 调用示例

```bash
curl -X POST \
  http://127.0.0.1:8000/recognition \
  -F "audio=@test.wav" \
  | jq .
```

## 支持的模型

### ASR 模型

- `paraformer-zh`: 中文 Paraformer 模型（推荐）
- `paraformer-zh-spark`: 中文流式模型
- `sensevoice-small`: 多语言模型

### VAD 模型

- `fsmn-vad`: FSMN VAD 模型（推荐）

### 说话人识别模型

- `cam++`: CAM++ 说话人模型（推荐）

更多模型请参考: https://github.com/alibaba-damo-academy/FunASR?tab=readme-ov-file#model-zoo

## 注意事项

1. **说话人识别需要 VAD 和标点模型**: 请确保 `--vad_model` 和 `--punc_model` 参数正确设置
2. **CPU 模式**: 使用 `--device cpu --ngpu 0` 启用 CPU 模式
3. **内存占用**: 首次运行会自动下载模型，需要较好的网络连接
4. **音频格式**: 服务自动将各种格式转换为 16kHz 单声道 PCM
5. **说话人数量**: `spk_count` 表示检测到的说话人数量，不是预设值

## 多进程部署（生产环境）

使用 Nginx 负载均衡部署多个服务实例：

```bash
# 配置 Nginx
sudo cp -f asr_nginx.conf /etc/nginx/nginx.conf
sudo service nginx reload

# 启动多个服务实例
sudo chmod +x start_server.sh
./start_server.sh
```

## 故障排查

### 模型下载失败

设置 ModelScope 镜像：

```bash
export MODELSCOPE_CACHE=/path/to/cache
```

### 内存不足

减少 CPU 线程数：

```bash
python server_with_speaker.py --ncpu 2
```

### 说话人识别不生效

检查日志是否显示 `Building SPK model`，确保：
1. 有 VAD 模型
2. 有标点模型
3. 模型版本正确
