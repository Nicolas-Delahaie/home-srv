#!/bin/sh
# Stop the YouTube live stream started by start_youtube_stream.sh.
set -eu

RTMP_URL_BASE="rtmp://a.rtmp.youtube.com/live2"   # must match start_youtube_stream.sh

# `|| true`: pgrep exits 1 when nothing matches, which would abort under `set -e`
# before the check and report a false failure to HA.
PIDS=$(pgrep -f "$RTMP_URL_BASE" || true)
if [ -z "$PIDS" ]; then
    echo "Stream not running"
    exit 0
fi

kill $PIDS   # SIGTERM lets ffmpeg flush/close cleanly; unquoted for multiple PIDs
echo "Stream stopped (PID: $(echo "$PIDS" | tr '\n' ' ')). Log: ${YOUTUBE_STREAM_LOG_FILE:-<unset>}"
