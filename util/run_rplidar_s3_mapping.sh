#!/usr/bin/env bash

# Launch RPLIDAR S3M1 + SLAM Toolbox for 2D map generation.
# Prerequisites:
# 1) odom -> base_link TF from md_controller
# 2) base_link -> laser TF from URDF or static_transform_publisher

set -euo pipefail

SERIAL_PORT="${SERIAL_PORT:-/dev/ttyLidar}"
SERIAL_BAUDRATE="${SERIAL_BAUDRATE:-1000000}"
FRAME_ID="${FRAME_ID:-laser}"
SCAN_MODE="${SCAN_MODE:-DenseBoost}"
MIN_LASER_RANGE="${MIN_LASER_RANGE:-0.20}"
MAX_LASER_RANGE="${MAX_LASER_RANGE:-25.0}"

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
if [[ -f "${HOME}/ros2_ws/install/setup.bash" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/ros2_ws/install/setup.bash"
fi

for pkg in rplidar_ros slam_toolbox; do
  if ! ros2 pkg prefix "${pkg}" >/dev/null 2>&1; then
    echo "[ERROR] Required package not found: ${pkg}"
    echo "[HINT] sudo apt install -y ros-humble-rplidar-ros ros-humble-slam-toolbox"
    exit 1
  fi
done

cleanup() {
  if [[ -n "${RPLIDAR_PID:-}" ]] && kill -0 "${RPLIDAR_PID}" >/dev/null 2>&1; then
    kill "${RPLIDAR_PID}" >/dev/null 2>&1 || true
    wait "${RPLIDAR_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "[INFO] Starting RPLIDAR node (port=${SERIAL_PORT}, baud=${SERIAL_BAUDRATE}, mode=${SCAN_MODE})"
ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:="${SERIAL_PORT}" \
  -p serial_baudrate:="${SERIAL_BAUDRATE}" \
  -p frame_id:="${FRAME_ID}" \
  -p inverted:=false \
  -p angle_compensate:=true \
  -p scan_mode:="${SCAN_MODE}" \
  -r scan:=/scan &
RPLIDAR_PID=$!

sleep 2

echo "[INFO] Starting slam_toolbox (scan=/scan, frame=${FRAME_ID})"
ros2 run slam_toolbox async_slam_toolbox_node --ros-args \
  -r scan:=/scan \
  -p base_frame:=base_link \
  -p odom_frame:=odom \
  -p map_frame:=map \
  -p throttle_scans:=2 \
  -p minimum_time_interval:=0.1 \
  -p scan_queue_size:=2000 \
  -p transform_timeout:=1.0 \
  -p tf_buffer_duration:=120.0 \
  -p minimum_laser_range:="${MIN_LASER_RANGE}" \
  -p max_laser_range:="${MAX_LASER_RANGE}"
