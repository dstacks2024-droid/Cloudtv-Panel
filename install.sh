#!/bin/bash

set -e

echo "=== Updating system and installing dependencies ==="
apt update && apt upgrade -y
apt install -y ffmpeg curl git build-essential nginx

echo "=== Installing Node.js 18.x ==="
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

echo "=== Installing yarn (optional, fallback to npm if fails) ==="
npm install -g yarn || echo "yarn install failed, fallback to npm"

# Set base dir
BASE_DIR="/var/www/cloud-tv"
mkdir -p "$BASE_DIR/backend/routes" "$BASE_DIR/backend/scripts" "$BASE_DIR/frontend/src/components" "$BASE_DIR/hls"

echo "=== Creating backend proxy middleware: streamProxy.js ==="
cat << 'EOF' > "$BASE_DIR/backend/routes/streamProxy.js"
const express = require('express');
const axios = require('axios');
const LRU = require('lru-cache');

const router = express.Router();
const HLS_BASE_URL = "http://localhost:8080/hls"; // Change if your media server differs

const cache = new LRU({
  max: 100,
  maxAge: 1000 * 60 * 5 // 5 minutes
});

router.get('/stream/:file', async (req, res) => {
  const file = req.params.file;

  if (cache.has(file)) {
    const cached = cache.get(file);
    res.set(cached.headers);
    return res.send(cached.data);
  }

  try {
    const response = await axios.get(`${HLS_BASE_URL}/${file}`, { responseType: 'arraybuffer' });
    cache.set(file, { data: response.data, headers: response.headers });
    res.set(response.headers);
    res.send(response.data);
  } catch (error) {
    res.status(500).send("Error fetching stream segment");
  }
});

module.exports = router;
EOF

echo "=== Creating transcoding script: transcode.sh ==="
cat << 'EOF' > "$BASE_DIR/backend/scripts/transcode.sh"
#!/bin/bash

INPUT_STREAM=$1
OUTPUT_DIR=$2

mkdir -p "$OUTPUT_DIR"

ffmpeg -i "$INPUT_STREAM" \
  -c:v libx264 -c:a aac \
  -preset veryfast -g 48 -keyint_min 48 \
  -sc_threshold 0 \
  -f hls \
  -hls_time 2 \
  -hls_list_size 10 \
  -hls_flags delete_segments+program_date_time \
  -hls_segment_type mpegts \
  "$OUTPUT_DIR/playlist.m3u8"
EOF
chmod +x "$BASE_DIR/backend/scripts/transcode.sh"

echo "=== Adding React AdaptivePlayer component ==="
cat << 'EOF' > "$BASE_DIR/frontend/src/components/AdaptivePlayer.jsx"
import React, { useEffect, useRef, useState } from "react";
import Hls from "hls.js";

const AdaptivePlayer = ({ streamUrl }) => {
  const videoRef = useRef(null);
  const [error, setError] = useState(null);
  const [buffering, setBuffering] = useState(false);

  useEffect(() => {
    let hls;

    if (Hls.isSupported()) {
      hls = new Hls({
        maxBufferLength: 10,
        maxMaxBufferLength: 30,
        liveSyncDurationCount: 3,
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(videoRef.current);

      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        videoRef.current.play();
      });

      hls.on(Hls.Events.ERROR, (event, data) => {
        if (data.fatal) {
          switch(data.type) {
            case Hls.ErrorTypes.NETWORK_ERROR:
              console.warn("Network error, retrying...");
              hls.startLoad();
              break;
            case Hls.ErrorTypes.MEDIA_ERROR:
              console.warn("Media error, recovering...");
              hls.recoverMediaError();
              break;
            default:
              hls.destroy();
              setError("Fatal error in playback");
              break;
          }
        }
      });

      hls.on(Hls.Events.BUFFER_STALLED, () => setBuffering(true));
      hls.on(Hls.Events.BUFFER_APPENDED, () => setBuffering(false));
    } else if (videoRef.current.canPlayType("application/vnd.apple.mpegurl")) {
      videoRef.current.src = streamUrl;
      videoRef.current.addEventListener("loadedmetadata", () => {
        videoRef.current.play();
      });
    } else {
      setError("HLS not supported in this browser");
    }

    return () => {
      if (hls) hls.destroy();
    };
  }, [streamUrl]);

  return (
    <div>
      {error && <div style={{color: "red", marginBottom: 8}}>{error}</div>}
      {buffering && <div style={{color: "orange", marginBottom: 8}}>Buffering...</div>}
      <video ref={videoRef} controls style={{ width: "100%" }} />
    </div>
  );
};

export default AdaptivePlayer;
EOF

echo "=== Creating WebSocket server: websocketServer.js ==="
cat << 'EOF' > "$BASE_DIR/backend/websocketServer.js"
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8081 });

wss.on('connection', ws => {
  console.log('WebSocket client connected');
});

function notifyClients(message) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
    }
  });
}

module.exports = { notifyClients };
EOF

echo "=== Installing backend Node.js modules ==="
cd "$BASE_DIR/backend"
npm init -y
npm install express axios lru-cache ws

echo "=== Installing frontend dependencies ==="
cd "$BASE_DIR/frontend"
if [ -f yarn.lock ]; then
  yarn install
else
  npm install
fi

echo "=== Setup complete ===
- Add this line to your backend server.js to mount stream proxy route:
  
  const streamProxy = require('./routes/streamProxy');
  app.use('/api', streamProxy);

- To start transcoding a stream:

  ./backend/scripts/transcode.sh <input_stream_url> $BASE_DIR/hls/<channel_name>

- Start your backend (using pm2 recommended):

  pm2 start backend/server.js --name cloud-tv-backend

- Start your frontend dev server:

  cd frontend && yarn start  # or npm start

- Use the AdaptivePlayer component in your React app:

  <AdaptivePlayer streamUrl=\"/api/stream/playlist.m3u8\" />

- WebSocket server is running on port 8081 for stream restart notifications.

You’re ready to go! 🚀
"

