#!/usr/bin/env python3
# -*- encoding: utf-8 -*-
"""
FunASR HTTP Server with Speaker Diarization Support
支持说话人识别的 HTTP API 服务
CPU 模式运行，无需 SSL
"""

import argparse
import logging
import os
import uuid

import aiofiles
import ffmpeg
import uvicorn
from fastapi import FastAPI, File, UploadFile
from modelscope.utils.logger import get_logger

from funasr import AutoModel

logger = get_logger(log_level=logging.INFO)
logger.setLevel(logging.INFO)

parser = argparse.ArgumentParser(description="FunASR HTTP Server with Speaker Diarization")
parser.add_argument(
    "--host", type=str, default="0.0.0.0", required=False, help="host ip, localhost, 0.0.0.0"
)
parser.add_argument("--port", type=int, default=8000, required=False, help="server port")

# ASR 模型参数
parser.add_argument(
    "--asr_model",
    type=str,
    default="paraformer-zh",
    help="asr model from https://github.com/alibaba-damo-academy/FunASR?tab=readme-ov-file#model-zoo",
)
parser.add_argument("--asr_model_revision", type=str, default="v2.0.4", help="")

# VAD 模型参数 (说话人识别需要 VAD)
parser.add_argument(
    "--vad_model",
    type=str,
    default="fsmn-vad",
    help="vad model from https://github.com/alibaba-damo-academy/FunASR?tab=readme-ov-file#model-zoo",
)
parser.add_argument("--vad_model_revision", type=str, default="v2.0.4", help="")

# 标点模型参数 (说话人识别需要标点模型)
parser.add_argument(
    "--punc_model",
    type=str,
    default="ct-punc-c",
    help="model from https://github.com/alibaba-damo-academy/FunASR?tab=readme-ov-file#model-zoo",
)
parser.add_argument("--punc_model_revision", type=str, default="v2.0.4", help="")

# 说话人识别模型参数
parser.add_argument(
    "--spk_model",
    type=str,
    default="cam++",
    help="speaker model, e.g., cam++",
)
parser.add_argument("--spk_model_revision", type=str, default="v2.0.2", help="")
parser.add_argument(
    "--spk_mode",
    type=str,
    default="punc_segment",
    choices=["default", "vad_segment", "punc_segment"],
    help="speaker diarization mode: default, vad_segment, punc_segment",
)

# 设备参数 - 默认 CPU
parser.add_argument("--device", type=str, default="cpu", help="cuda, cpu")
parser.add_argument("--ngpu", type=int, default=0, help="0 for cpu, 1 for gpu")
parser.add_argument("--ncpu", type=int, default=4, help="cpu cores")

# 热词和其他参数
parser.add_argument(
    "--hotword_path",
    type=str,
    default="hotwords.txt",
    help="hot word txt path, only the hot word model works",
)
parser.add_argument("--temp_dir", type=str, default="temp_dir/", required=False, help="temp dir")

# SSL 参数 - 默认不启用
parser.add_argument("--certfile", type=str, default=None, required=False, help="certfile for ssl")
parser.add_argument("--keyfile", type=str, default=None, required=False, help="keyfile for ssl")

args = parser.parse_args()

logger.info("-----------  Configuration Arguments -----------")
for arg, value in vars(args).items():
    logger.info("%s: %s" % (arg, value))
logger.info("------------------------------------------------")

os.makedirs(args.temp_dir, exist_ok=True)

logger.info("Loading models...")
# 加载 FunASR 模型，包含说话人识别
model = AutoModel(
    model=args.asr_model,
    model_revision=args.asr_model_revision,
    vad_model=args.vad_model,
    vad_model_revision=args.vad_model_revision,
    punc_model=args.punc_model,
    punc_model_revision=args.punc_model_revision,
    spk_model=args.spk_model,
    spk_model_revision=args.spk_model_revision,
    spk_mode=args.spk_mode,
    ngpu=args.ngpu,
    ncpu=args.ncpu,
    device=args.device,
    disable_pbar=True,
    disable_log=True,
)
logger.info("Models loaded successfully!")

app = FastAPI(title="FunASR with Speaker Diarization")

# 配置参数
param_dict = {
    "sentence_timestamp": True,  # 需要句子时间戳用于说话人识别
    "batch_size_s": 300,
    "return_spk_res": True,  # 返回说话人识别结果
}

# 加载热词
if args.hotword_path is not None and os.path.exists(args.hotword_path):
    with open(args.hotword_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        lines = [line.strip() for line in lines]
    hotword = " ".join(lines)
    logger.info(f"Hotwords: {hotword}")
    param_dict["hotword"] = hotword


@app.post("/recognition")
async def api_recognition(audio: UploadFile = File(..., description="audio file")):
    """
    语音识别 + 说话人识别接口
    
    返回格式:
    {
        "text": "完整识别文本",
        "sentences": [
            {"text": "第一句", "start": 0, "end": 2000, "spk": 0},
            {"text": "第二句", "start": 2100, "end": 5000, "spk": 1}
        ],
        "code": 0
    }
    """
    suffix = audio.filename.split(".")[-1]
    audio_path = f"{args.temp_dir}/{str(uuid.uuid1())}.{suffix}"
    
    # 保存上传的音频文件
    async with aiofiles.open(audio_path, "wb") as out_file:
        content = await audio.read()
        await out_file.write(content)
    
    # 转换为 PCM 格式
    try:
        audio_bytes, _ = (
            ffmpeg.input(audio_path, threads=0)
            .output("-", format="s16le", acodec="pcm_s16le", ac=1, ar=16000)
            .run(cmd=["ffmpeg", "-nostdin"], capture_stdout=True, capture_stderr=True)
        )
    except Exception as e:
        logger.error(f"Error reading audio file: {e}")
        return {"msg": "Error reading audio file", "code": 1}
    
    # 执行识别（包含说话人识别）
    rec_results = model.generate(input=audio_bytes, is_final=True, **param_dict)
    
    # 处理结果
    if len(rec_results[0]["text"]) == 0:
        return {"text": "", "sentences": [], "code": 0}
    
    elif len(rec_results[0]["text"]) > 0:
        rec_result = rec_results[0]
        text = rec_result["text"]
        sentences = []
        
        # 解析带说话人信息的句子
        if "sentence_info" in rec_result:
            for sentence in rec_result["sentence_info"]:
                sent_info = {
                    "text": sentence.get("text", ""),
                    "start": sentence.get("start", 0),
                    "end": sentence.get("end", 0),
                    "spk": sentence.get("spk", -1)  # 说话人 ID
                }
                sentences.append(sent_info)
        else:
            # 回退到普通句子解析
            for sentence in rec_result.get("sentence_info", []):
                sentences.append({
                    "text": sentence.get("text", ""),
                    "start": sentence.get("start", 0),
                    "end": sentence.get("end", 0)
                })
        
        # 统计说话人数量
        spk_set = set([s.get("spk", -1) for s in sentences if s.get("spk", -1) >= 0])
        spk_count = len(spk_set)
        
        ret = {
            "text": text,
            "sentences": sentences,
            "spk_count": spk_count,  # 检测到的说话人数量
            "code": 0
        }
        logger.info(f"Recognition result: {ret}")
        return ret
    else:
        logger.error(f"Unknown error: {rec_results}")
        return {"msg": "Unknown error", "code": -1}


@app.get("/health")
async def health_check():
    """健康检查接口"""
    return {"status": "ok", "service": "funasr-speaker"}


if __name__ == "__main__":
    # 启动服务，不带 SSL
    ssl_config = {}
    if args.certfile and args.keyfile:
        ssl_config = {
            "ssl_keyfile": args.keyfile,
            "ssl_certfile": args.certfile
        }
    
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        **ssl_config
    )
