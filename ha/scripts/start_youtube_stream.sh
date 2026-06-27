#!/bin/sh
# Start the camera -> YouTube live stream (go2rtc RTSP -> YouTube RTMP).
#
# ffmpeg runs in the background, so a naive script would always exit 0 even when
# the stream failed. Here we check ffmpeg actually came up, so failures surface
# as a non-zero exit that the Home Assistant automation can react to.
set -eu

LOG_ARCHIVE_DIR=/tmp/youtube_stream_logs
RTMP_URL_BASE="rtmp://a.rtmp.youtube.com/live2"   # also matched by stop_youtube_stream.sh
RTSP_SOURCE="rtsp://127.0.0.1:8554/tapo_c200"

# Missing vars fail with a clear message instead of a cryptic `set -u` abort.
: "${YOUTUBE_STREAM_KEY:?YOUTUBE_STREAM_KEY not set}"
: "${YOUTUBE_STREAM_LOG_FILE:?YOUTUBE_STREAM_LOG_FILE not set}"

# Never push two encoders to the same key.
if pgrep -f "$RTMP_URL_BASE" > /dev/null 2>&1; then
    echo "Stream already running (PID: $(pgrep -f "$RTMP_URL_BASE" | tr '\n' ' '))"
    exit 0
fi

# Keep the previous run's log around.
if [ -f "$YOUTUBE_STREAM_LOG_FILE" ]; then
    mkdir -p "$LOG_ARCHIVE_DIR"
    mv "$YOUTUBE_STREAM_LOG_FILE" "$LOG_ARCHIVE_DIR/stream_$(date +%Y%m%d_%H%M%S).log"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stream started" > "$YOUTUBE_STREAM_LOG_FILE"

# -timeout             fail fast if go2rtc has no source (RTSP option; -rw_timeout is rejected)
# -c:v copy            forward the camera H264 as-is (no re-encode, lowest latency)
# -af aresample=async  keep the PCMA->AAC audio timestamps monotonic; YouTube rejects
#                      the jumpy DTS the camera audio produces otherwise
# setsid + </dev/null  detach from HA's shell_command so the stream outlives this script
setsid ffmpeg \
  -hide_banner -loglevel verbose \
  -rtsp_transport tcp \
  -timeout 10000000 \
  -i "$RTSP_SOURCE" \
  -c:v copy \
  -af aresample=async=1 \
  -c:a aac -ar 44100 -ac 2 -b:a 128k \
  -max_muxing_queue_size 1024 \
  -f flv "${RTMP_URL_BASE}/${YOUTUBE_STREAM_KEY}" \
  </dev/null >> "$YOUTUBE_STREAM_LOG_FILE" 2>&1 &

# In a script (no job control) setsid isn't a group leader, so it execs ffmpeg
# in place instead of forking -- $! is therefore ffmpeg's own PID.
FFMPEG_PID=$!

# Report a startup failure (dead source, bad key...) instead of faking success.
sleep 2
if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
    echo "ERROR: ffmpeg exited immediately, stream did not start" >&2
    tail -n 8 "$YOUTUBE_STREAM_LOG_FILE" >&2
    exit 1
fi

echo "Stream started (PID: $FFMPEG_PID). Log: $YOUTUBE_STREAM_LOG_FILE"
