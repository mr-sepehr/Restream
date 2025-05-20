#!/bin/bash

set -e

echo "🎥 نصب Restream RTMP چندکاربره"
echo "----------------------------------------"

read -p "🔑 Stream Key دلخواه برای OBS (مثلاً user1key): " STREAM_KEY
read -p "🎯 Twitch Stream Key واقعی: " TWITCH_KEY
read -p "📺 YouTube Stream Key واقعی: " YOUTUBE_KEY

echo "✅ نصب وابستگی‌ها..."
apt update
apt install -y nginx libnginx-mod-rtmp ffmpeg python3 curl

echo "✅ پیکربندی nginx..."

# اضافه کردن پیکربندی RTMP به nginx.conf
if ! grep -q "rtmp {" /etc/nginx/nginx.conf; then
cat << 'EOF' >> /etc/nginx/nginx.conf

rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        application live {
            live on;
            record off;
            exec_publish /usr/local/bin/rtmp_restream.py $name;
        }
    }
}
EOF
else
  echo "⚠️ بلاک RTMP از قبل در nginx.conf وجود دارد. رد شد."
fi

echo "✅ ساخت stream_keys.json..."

cat << EOF > /etc/nginx/stream_keys.json
{
  "$STREAM_KEY": {
    "youtube": "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY",
    "twitch": "rtmp://live.twitch.tv/app/$TWITCH_KEY"
  }
}
EOF

echo "✅ ساخت اسکریپت Python اجرای ffmpeg..."

cat << 'EOF' > /usr/local/bin/rtmp_restream.py
#!/usr/bin/env python3
import sys
import json
import subprocess
import datetime

stream_key = sys.argv[1]
config_path = "/etc/nginx/stream_keys.json"
log_path = "/tmp/rtmp_debug.log"

def log(msg):
    with open(log_path, "a") as f:
        f.write(f"[{datetime.datetime.now()}] {msg}\n")

log(f"Incoming stream key: {stream_key}")

try:
    with open(config_path) as f:
        data = json.load(f)
except Exception as e:
    log(f"Error reading config: {e}")
    sys.exit(1)

if stream_key in data:
    youtube_url = data[stream_key]["youtube"]
    twitch_url = data[stream_key]["twitch"]

    log(f"Starting FFmpeg for YouTube: {youtube_url}")
    subprocess.Popen([
        "ffmpeg", "-re", "-i", f"rtmp://127.0.0.1/live/{stream_key}",
        "-c:v", "libx264", "-preset", "veryfast", "-b:v", "2500k",
        "-c:a", "aac", "-b:a", "128k",
        "-f", "flv", youtube_url
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    log(f"Starting FFmpeg for Twitch: {twitch_url}")
    subprocess.Popen([
        "ffmpeg", "-re", "-i", f"rtmp://127.0.0.1/live/{stream_key}",
        "-c:v", "libx264", "-preset", "veryfast", "-b:v", "2500k",
        "-c:a", "aac", "-b:a", "128k",
        "-f", "flv", twitch_url
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    log("FFmpeg processes started successfully.")
else:
    log("Unauthorized stream key.")
    sys.exit(1)
EOF

chmod +x /usr/local/bin/rtmp_restream.py

echo "✅ باز کردن پورت RTMP..."
ufw allow 1935/tcp || true

echo "✅ بررسی و راه‌اندازی nginx..."
nginx -t && systemctl restart nginx

IP=$(curl -s ifconfig.me)

echo ""
echo "🎉 نصب کامل شد! حالا می‌تونی در OBS این تنظیمات رو بزنی:"
echo "----------------------------------------"
echo "📡 Server:    rtmp://$IP/live"
echo "🔑 Stream Key: $STREAM_KEY"
echo ""
echo "✅ اگه خواستی Stream Key جدید اضافه کنی، فایل زیر رو ویرایش کن:"
echo "/etc/nginx/stream_keys.json"
