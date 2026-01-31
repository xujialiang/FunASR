# FunASR HTTP API 接口文档

## 基础信息

| 项目 | 说明 |
|------|------|
| 基础URL | `http://{host}:{port}` |
| 默认地址 | `http://127.0.0.1:8000` |
| 数据格式 | `multipart/form-data` |

---

## 1. 语音识别 + 说话人识别

### 接口信息

```
POST /recognition
```

### 功能说明
上传音频文件，返回语音识别结果和说话人分割信息。

### 请求参数

#### Headers
| 参数 | 值 | 说明 |
|------|-----|------|
| `Content-Type` | `multipart/form-data` | 必需 |

#### Body (form-data)
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `audio` | File | 是 | 音频文件 (wav, mp3, m4a, flac 等) |

### 返回参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | Integer | 状态码 (0=成功, 1=音频错误, -1=未知错误) |
| `text` | String | 完整识别文本 |
| `sentences` | Array | 句子列表（含说话人信息） |
| `spk_count` | Integer | 检测到的说话人数量 |

#### sentences 结构
| 字段 | 类型 | 说明 |
|------|------|------|
| `text` | String | 句子文本 |
| `start` | Integer | 开始时间 (毫秒) |
| `end` | Integer | 结束时间 (毫秒) |
| `spk` | Integer | 说话人 ID (0, 1, 2...) |

### 返回示例

#### 成功响应
```json
{
  "code": 0,
  "text": "今天天气真不错我们出去走走吧好啊那我们去公园",
  "sentences": [
    {
      "text": "今天天气真不错。",
      "start": 0,
      "end": 2450,
      "spk": 0
    },
    {
      "text": "我们出去走走吧。",
      "start": 2680,
      "end": 4820,
      "spk": 1
    },
    {
      "text": "好啊，那我们去公园。",
      "start": 5120,
      "end": 7650,
      "spk": 0
    }
  ],
  "spk_count": 2
}
```

#### 空音频响应
```json
{
  "code": 0,
  "text": "",
  "sentences": [],
  "spk_count": 0
}
```

#### 错误响应
```json
{
  "code": 1,
  "msg": "Error reading audio file"
}
```

---

## 2. 健康检查

### 接口信息

```
GET /health
```

### 功能说明
检查服务是否正常运行。

### 请求参数
无

### 返回示例
```json
{
  "status": "ok",
  "service": "funasr-speaker"
}
```

---

## Postman 调用指南

### 步骤 1：创建请求

1. 打开 Postman
2. 点击 `+` 新建请求
3. 选择请求方法为 `POST`
4. 输入 URL: `http://127.0.0.1:8000/recognition`

### 步骤 2：设置 Headers

| KEY | VALUE |
|-----|-------|
| Content-Type | multipart/form-data |

> 注：Postman 通常会自动设置，无需手动添加

### 步骤 3：设置 Body

1. 选择 `Body` 标签
2. 选择 `form-data`
3. 添加参数：

| KEY | VALUE | 类型 |
|-----|-------|------|
| audio | [点击选择文件] | File |

### 步骤 4：发送请求

点击 `Send` 按钮发送请求

### 步骤 5：查看结果

在 `Response` 区域查看返回的 JSON 数据

---

## cURL 调用示例

### 语音识别 + 说话人识别
```bash
curl -X POST \
  http://127.0.0.1:8000/recognition \
  -F "audio=@/path/to/your/audio.wav" \
  -H "Content-Type: multipart/form-data"
```

### 健康检查
```bash
curl http://127.0.0.1:8000/health
```

### 带美观输出的 JSON
```bash
curl -X POST \
  http://127.0.0.1:8000/recognition \
  -F "audio=@test.wav" | jq .
```

---

## Python 调用示例

### 使用 requests
```python
import requests

url = "http://127.0.0.1:8000/recognition"

# 准备文件
files = [
    ("audio", ("test.wav", open("test.wav", "rb"), "audio/wav"))
]

# 发送请求
response = requests.post(url, files=files)
result = response.json()

# 打印结果
print(f"识别文本: {result['text']}")
print(f"说话人数量: {result['spk_count']}")

for sent in result['sentences']:
    print(f"[{sent['start']}ms - {sent['end']}ms] "
          f"[Speaker {sent['spk']}] {sent['text']}")
```

### 异步调用 (aiohttp)
```python
import aiohttp
import asyncio

async def recognize():
    url = "http://127.0.0.1:8000/recognition"
    
    async with aiohttp.ClientSession() as session:
        data = aiohttp.FormData()
        data.add_field('audio',
                       open('test.wav', 'rb'),
                       filename='test.wav',
                       content_type='audio/wav')
        
        async with session.post(url, data=data) as resp:
            result = await resp.json()
            print(result)

asyncio.run(recognize())
```

---

## JavaScript/Node.js 调用示例

### 使用 fetch
```javascript
const formData = new FormData();
formData.append('audio', fs.createReadStream('test.wav'));

fetch('http://127.0.0.1:8000/recognition', {
  method: 'POST',
  body: formData
})
.then(response => response.json())
.then(data => {
  console.log('识别文本:', data.text);
  console.log('说话人数量:', data.spk_count);
  data.sentences.forEach(sent => {
    console.log(`[Speaker ${sent.spk}] ${sent.text}`);
  });
});
```

### 使用 axios
```javascript
const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');

const form = new FormData();
form.append('audio', fs.createReadStream('test.wav'));

axios.post('http://127.0.0.1:8000/recognition', form, {
  headers: form.getHeaders()
})
.then(response => {
  console.log(response.data);
});
```

---

## Java 调用示例

```java
import java.io.*;
import java.net.*;

public class FunASRClient {
    public static void main(String[] args) throws Exception {
        String url = "http://127.0.0.1:8000/recognition";
        String audioFile = "test.wav";
        
        URL obj = new URL(url);
        HttpURLConnection con = (HttpURLConnection) obj.openConnection();
        con.setRequestMethod("POST");
        con.setDoOutput(true);
        
        // 设置 boundary
        String boundary = "----WebKitFormBoundary" + System.currentTimeMillis();
        con.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
        
        try (DataOutputStream wr = new DataOutputStream(con.getOutputStream())) {
            // 写入文件
            wr.writeBytes("--" + boundary + "\r\n");
            wr.writeBytes("Content-Disposition: form-data; name=\"audio\"; filename=\"" + audioFile + "\"\r\n");
            wr.writeBytes("Content-Type: audio/wav\r\n\r\n");
            
            FileInputStream fis = new FileInputStream(audioFile);
            byte[] buffer = new byte[4096];
            int bytesRead;
            while ((bytesRead = fis.read(buffer)) != -1) {
                wr.write(buffer, 0, bytesRead);
            }
            fis.close();
            
            wr.writeBytes("\r\n--" + boundary + "--\r\n");
        }
        
        // 读取响应
        BufferedReader in = new BufferedReader(new InputStreamReader(con.getInputStream()));
        String inputLine;
        StringBuilder response = new StringBuilder();
        while ((inputLine = in.readLine()) != null) {
            response.append(inputLine);
        }
        in.close();
        
        System.out.println(response.toString());
    }
}
```

---

## 常见错误码

| 状态码 | 说明 | 解决方案 |
|--------|------|----------|
| 0 | 成功 | - |
| 1 | 音频文件读取错误 | 检查音频文件格式是否正确 |
| -1 | 未知错误 | 查看服务端日志 |
| 422 | 请求格式错误 | 检查 Content-Type 是否为 multipart/form-data |
| 404 | 接口不存在 | 检查 URL 是否正确 |

---

## 支持的音频格式

| 格式 | 说明 |
|------|------|
| WAV | 推荐格式 |
| MP3 | 支持 |
| M4A | 支持 |
| FLAC | 支持 |
| OGG | 支持 |
| AAC | 支持 |

> 注：服务会自动将所有格式转换为 16kHz 单声道 PCM 进行处理
