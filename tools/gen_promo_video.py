#!/usr/bin/env python3
"""用 MiniMax H3 图生视频制作宣传短片（/v2 接口）：首帧=游戏截图，短视频不影响游玩。"""
import base64
import json
import os
import sys
import time
import urllib.request
import urllib.error

HOST = "https://api.minimaxi.com"
KEY = [l.strip().split("=", 1)[1] for l in open(os.path.expanduser("~/.hermes/.env"))
       if l.startswith("MINIMAX_API_KEY=")][0]

IMG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/game_v4.png"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/项目/FlowerMatch3/promo/promo.mp4")

PROMPT = ("竖屏手机消消乐游戏宣传短片：棋盘上可爱的卡通花朵轻轻摇曳，三朵相同的"
          "花朵连成一线后绽放成花瓣粒子和闪亮特效，新花朵从上方轻盈落下，画面明亮"
          "清新、节奏轻快流畅，保持原游戏的 UI 布局与配色风格")


def post(path, payload):
    req = urllib.request.Request(HOST + path, data=json.dumps(payload).encode(),
                                 headers={"Authorization": f"Bearer {KEY}",
                                          "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=90))


def get(path):
    req = urllib.request.Request(HOST + path,
                                 headers={"Authorization": f"Bearer {KEY}"})
    return json.load(urllib.request.urlopen(req, timeout=60))


def main():
    b64 = base64.b64encode(open(IMG, "rb").read()).decode()
    body = {
        "model": "MiniMax-H3",
        "duration": 6,
        "resolution": "768P",
        "ratio": "9:16",
        "content": [
            {"type": "text", "text": PROMPT},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ],
    }
    try:
        resp = post("/v2/video_generation", body)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:400]}")
    print("创建响应:", json.dumps(resp, ensure_ascii=False)[:300])
    task_id = resp.get("task_id") or resp.get("id")
    if not task_id:
        sys.exit("未返回 task_id")

    for i in range(60):
        time.sleep(10)
        for qp in ("/v1/query/video_generation", "/v2/query/video_generation"):
            try:
                st = get(f"{qp}?task_id={task_id}")
            except Exception:
                continue
            if st.get("status"):
                break
        status = st.get("status")
        print(f"  轮询 {i + 1}: {status}")
        if status == "Success":
            file_id = st.get("file_id")
            info = get(f"/v1/files/retrieve?file_id={file_id}")
            url = info.get("file", {}).get("download_url")
            os.makedirs(os.path.dirname(OUT), exist_ok=True)
            urllib.request.urlretrieve(url, OUT)
            print(f"✅ 视频已保存: {OUT} ({os.path.getsize(OUT) / 1048576:.1f} MB)")
            return
        if status in ("Fail", "Failed"):
            sys.exit(f"生成失败: {json.dumps(st, ensure_ascii=False)[:300]}")
    sys.exit("超时")


if __name__ == "__main__":
    main()
