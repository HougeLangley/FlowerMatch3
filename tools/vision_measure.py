#!/usr/bin/env python3
"""用 DeepSeek 视觉模型测量游戏截图布局，辅助棋盘扩展决策。"""
import base64
import json
import os
import sys
import urllib.request

key = None
for line in open(os.path.expanduser("~/.hermes/.env")):
    if line.startswith("DEEPSEEK_API_KEY="):
        key = line.strip().split("=", 1)[1]
assert key, "no key"

img_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/board_grid.png"
b64 = base64.b64encode(open(img_path, "rb").read()).decode()

body = {
    "model": "deepseek-v4-flash-vision-exp",
    "messages": [{
        "role": "user",
        "content": [
            {"type": "text", "text": """这是一张手机竖屏游戏截图（1200x2670），叠加了红色标尺线（每100px一条，标注y坐标）。画面上方是"Score: 0"文字，中部是白底圆角卡片上的7列x9行花朵棋盘，下方是大片空白。请精确回答：
1. 棋盘卡片的上边缘y坐标和下边缘y坐标（读标尺估值）
2. Score文字的下边缘y坐标
3. 如果棋盘要向下方扩展，考虑到底部要预留手势导航安全区（屏幕底部约5%），棋盘上缘不动，棋盘下边缘最大可以到哪个y坐标？
4. 按每行高度约167px计算，棋盘最多能增加到多少行？
只返回JSON：{"board_top":int,"board_bottom":int,"score_bottom":int,"max_board_bottom":int,"max_rows":int,"reasoning":"简述"}"""},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}}
        ]
    }],
    "max_tokens": 4000,
}
req = urllib.request.Request(
    "https://api.deepseek.com/chat/completions",
    data=json.dumps(body).encode(),
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
resp = json.load(urllib.request.urlopen(req, timeout=180))
choice = resp["choices"][0]
print("finish_reason:", choice.get("finish_reason"))
print("usage:", resp.get("usage"))
print("--- content ---")
print(choice["message"].get("content") or "(空)")
rc = choice["message"].get("reasoning_content") or ""
print("--- reasoning 尾部 ---")
print(rc[-800:])
