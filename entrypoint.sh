#!/bin/bash
set -e

# Start Xvfb
echo "Starting Xvfb..."
Xvfb :1 -screen 0 1366x768x24 &
sleep 2

# Start Window Manager
echo "Starting Openbox..."
openbox-session &

# Setup VNC Password
mkdir -p ~/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" ~/.vnc/passwd

# Start x11vnc
echo "Starting x11vnc..."
x11vnc -display :1 -rfbauth ~/.vnc/passwd -forever -shared -bg &

# Start Websockify
echo "Starting Websockify..."
/opt/websockify/run --web=/opt/noVNC 8080 localhost:5900 &

# Start MT4
echo "Starting MetaTrader 4..."
cd "$MT4DIR"
wine terminal.exe /portable

# Keep container alive if MT4 exits (optional, or just let it exit)
# tail -f /dev/null
