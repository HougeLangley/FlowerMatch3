#!/usr/bin/env python3
"""生成循环背景视频：MiniMax 图像 → H3 图生视频 → 回文循环 → Theora ogv
用法: python3 tools/gen_bg_videos.py <theme>   # theme: garden | sakura
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

HOST = "https://api.minimaxi.com"
KEY = [l.strip().split("=", 1)[1] for l in open(os.path.expanduser("~/.hermes/.env"))
       if l.startswith("MINIMAX_API_KEY=")][0]
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

THEMES = {
    "garden": {
        "image_prompt": ("Cute cartoon mobile game background art, portrait: soft blue sky "
                         "with fluffy white clouds, rolling green grass hills at the bottom, "
                         "colorful small flowers, butterflies, sparkles and bokeh, bright "
                         "pastel colors, clean simple composition, no text, no characters"),
        "video_prompt": ("Gentle ambient background loop: clouds drifting slowly across the "
                         "sky, sparkles twinkling, butterflies fluttering softly, static "
                         "camera, subtle calm motion only, no text, no characters"),
    },
    "sakura": {
        "image_prompt": ("Cute cartoon mobile game background art, portrait: dreamy pink "
                         "cherry blossom sky, sakura branches in the corners, soft gradient "
                         "pastel colors, falling petals, sparkles bokeh, clean simple "
                         "composition, no text, no characters"),
        "video_prompt": ("Gentle ambient background loop: cherry blossom petals floating and "
                         "drifting down softly, sparkles twinkling, branches swaying slightly, "
                         "static camera, subtle calm motion only, no text, no characters"),
    },
}


def post(path, payload):
    req = urllib.request.Request(HOST + path, data=json.dumps(payload).encode(),
                                 headers={"Authorization": f"Bearer {KEY}",
                                          "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=90))


def get(path, timeout=60):
    req = urllib.request.Request(HOST + path, headers={"Authorization": f"Bearer {KEY}"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def gen_image(prompt, out_path):
    resp = post("/v1/image_generation", {
        "model": "image-01", "prompt": prompt, "aspect_ratio": "9:16",
        "response_format": "url", "n": 1})
    url = resp["data"]["image_urls"][0]
    urllib.request.urlretrieve(url, out_path)
    print(f"  [image] {out_path} ok")


def gen_video(prompt, img_path, out_path):
    b64 = base64.b64encode(open(img_path, "rb").read()).decode()
    resp = post("/v2/video_generation", {
        "model": "MiniMax-H3", "duration": 6, "resolution": "768P", "ratio": "9:16",
        "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ]})
    task_id = resp.get("task_id") or resp.get("id")
    assert task_id, f"no task_id: {resp}"
    print(f"  [video] task {task_id}")
    for i in range(90):
        time.sleep(10)
        st = get(f"/v1/query/video_generation?task_id={task_id}")
        status = st.get("status")
        if status == "Success":
            info = get(f"/v1/files/retrieve?file_id={st['file_id']}")
            urllib.request.urlretrieve(info["file"]["download_url"], out_path)
            print(f"  [video] {out_path} ok")
            return
        if status in ("Fail", "Failed"):
            raise RuntimeError(f"video failed: {st}")
    raise TimeoutError("video timeout")


def make_loop_ogv(src, dst, scale="540:1170"):
    # 回文循环（正放+倒放拼接）→ 无缝 loop；去音轨；缩到竖屏目标尺寸
    tmp = src + ".palindrome.mp4"
    subprocess.run([
        "ffmpeg", "-y", "-v", "error", "-i", src,
        "-filter_complex", f"[0:v]reverse[r];[0:v][r]concat=n=2:v=1[a];[a]scale={scale}[v]",
        "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "20", tmp],
        check=True)
    subprocess.run([
        "ffmpeg", "-y", "-v", "error", "-i", tmp,
        "-c:v", "libtheora", "-q:v", "6", "-an", dst], check=True)
    os.remove(tmp)
    print(f"  [loop] {dst} ok")


def main():
    theme = sys.argv[1] if len(sys.argv) > 1 else "garden"
    cfg = THEMES[theme]
    out_dir = os.path.join(BASE, "assets", "video")
    os.makedirs(out_dir, exist_ok=True)
    img = f"/tmp/bg_{theme}.png"
    raw = f"/tmp/bg_{theme}_raw.mp4"
    ogv = os.path.join(out_dir, f"bg_{theme}.ogv")
    gen_image(cfg["image_prompt"], img)
    gen_video(cfg["video_prompt"], img, raw)
    make_loop_ogv(raw, ogv)
    print(f"✅ {ogv}")


if __name__ == "__main__":
    main()
