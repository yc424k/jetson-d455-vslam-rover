#!/usr/bin/env bash

# Run this script inside isaac_ros_dev container:
#   source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
# It will:
# 1) source ROS environment
# 2) remove problematic yarn apt repo if present
# 3) install missing runtime packages for mapping/foxglove
# 4) source workspace overlay if available

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces/isaac_ros-dev}"
ROS_SETUP="/opt/ros/humble/setup.bash"
WS_SETUP="${WORKSPACE_DIR}/install/setup.bash"
YARN_LIST="/etc/apt/sources.list.d/yarn.list"

# Preserve caller shell options because this script is intended to be sourced.
__BOOTSTRAP_SAVED_OPTS="$(set +o)"
set -eo pipefail

if [[ -f "${ROS_SETUP}" ]]; then
  # ROS setup scripts can reference unset variables; avoid nounset failures.
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP}"
else
  echo "[ERROR] ROS setup not found: ${ROS_SETUP}"
  eval "${__BOOTSTRAP_SAVED_OPTS}"
  return 1 2>/dev/null || exit 1
fi

REQUIRED_PKGS=(
  ros-humble-librealsense2
  ros-humble-depthimage-to-laserscan
  ros-humble-slam-toolbox
  ros-humble-nav2-map-server
  ros-humble-foxglove-bridge
)

MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    MISSING_PKGS+=("${pkg}")
  fi
done

if [[ -f "${YARN_LIST}" ]]; then
  echo "[INFO] Removing stale yarn apt repo: ${YARN_LIST}"
  sudo rm -f "${YARN_LIST}"
fi

if (( ${#MISSING_PKGS[@]} > 0 )); then
  echo "[INFO] Installing missing packages: ${MISSING_PKGS[*]}"
  sudo apt clean
  sudo rm -rf /var/lib/apt/lists/*
  sudo apt update
  sudo apt install -y "${MISSING_PKGS[@]}"
else
  echo "[INFO] Required apt packages are already installed."
fi

if [[ -f "${WS_SETUP}" ]]; then
  # shellcheck disable=SC1090
  source "${WS_SETUP}"
  echo "[INFO] Workspace overlay loaded: ${WS_SETUP}"
else
  echo "[WARN] Workspace overlay not found: ${WS_SETUP}"
  echo "[WARN] Build once if needed:"
  echo "       cd ${WORKSPACE_DIR} && rosdep update && rosdep install --from-paths src --ignore-src -r -y"
  echo "       cd ${WORKSPACE_DIR} && colcon build --base-paths src --symlink-install --allow-overriding isaac_ros_common --packages-up-to realsense2_camera realsense2_description isaac_ros_visual_slam"
fi

echo "[DONE] Container bootstrap complete."
eval "${__BOOTSTRAP_SAVED_OPTS}"
