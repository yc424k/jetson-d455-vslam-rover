# Nav2 기반 자율주행 가이드

이 문서는 맵 생성부터 Nav2 목표 전송까지 자율주행 절차를 설명합니다.

## Nav2 기반 자율주행 실행

현재 README 절차로는 `SLAM + 모터 구동 + /cmd_vel 수동 입력`까지 완료됩니다.  
완전 자율주행을 하려면 **Nav2가 `/cmd_vel`을 자동 생성**하도록 추가해야 합니다.

### 사전 조건

- `/visual_slam/status` 정상(`vo_state: 1`)
- `/visual_slam/tracking/odometry` 정상 발행
- `md_controller`가 `/cmd_vel`을 받아 실제 주행 가능
- 2D 정적 맵 파일 준비 (`<map>.yaml`, `<map>.pgm`)

> Nav2 글로벌 경로 계획은 2D occupancy map을 사용하므로, 맵 파일이 없으면 완전 자율주행을 시작할 수 없습니다.

### 1) 맵 파일 생성 (`my_map.yaml`, `my_map.pgm`)

아직 맵이 없다면 아래 순서로 먼저 생성합니다.

1. 패키지 설치:

```bash
sudo apt update
sudo apt install -y \
  ros-humble-slam-toolbox \
  ros-humble-depthimage-to-laserscan \
  ros-humble-nav2-map-server
mkdir -p ~/maps
```

2. RealSense 실행:

```bash
source ~/ros2_ws/install/setup.bash
ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
```

3. Depth -> LaserScan 변환(`/scan` 생성):

```bash
source /opt/ros/humble/setup.bash
ros2 run depthimage_to_laserscan depthimage_to_laserscan_node --ros-args \
  -r depth:=/camera/camera/depth/image_rect_raw \
  -r depth_camera_info:=/camera/camera/depth/camera_info \
  -r scan:=/scan \
  -p range_min:=0.25 \
  -p range_max:=6.0
```

4. SLAM 실행(`/map` 생성):

```bash
source /opt/ros/humble/setup.bash
ros2 run slam_toolbox async_slam_toolbox_node --ros-args -r scan:=/scan
```

5. 저속 수동 주행으로 맵 커버리지 확보:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

6. 맵 저장:

```bash
source /opt/ros/humble/setup.bash
ros2 run nav2_map_server map_saver_cli -f ~/maps/my_map
```

생성 결과:

- `~/maps/my_map.yaml`
- `~/maps/my_map.pgm`

#### tmux 3분할 실행 예시 (맵 생성용)

아래 예시는 Jetson에서 `tmux` 한 세션에 매핑 필수 노드 3개를 동시에 올리는 방법입니다.

```bash
# 1) tmux 세션 생성 (detached)
tmux new-session -d -s mapping \
"bash -lc 'source ~/ros2_ws/install/setup.bash; ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true'"

# 2) 오른쪽 pane: depth -> scan
tmux split-window -h -t mapping \
"bash -lc 'source /opt/ros/humble/setup.bash; ros2 run depthimage_to_laserscan depthimage_to_laserscan_node --ros-args -r depth:=/camera/camera/depth/image_rect_raw -r depth_camera_info:=/camera/camera/depth/camera_info -r scan:=/scan -p range_min:=0.25 -p range_max:=6.0'"

# 3) 아래 pane: slam_toolbox
tmux split-window -v -t mapping:0.1 \
"bash -lc 'source /opt/ros/humble/setup.bash; ros2 run slam_toolbox async_slam_toolbox_node --ros-args -r scan:=/scan'"

# 4) 보기 좋게 정렬 후 attach
tmux select-layout -t mapping tiled
tmux attach -t mapping
```

별도 터미널(또는 tmux 새 window)에서 주행/저장:

```bash
# 수동 주행
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard

# 맵 저장
source /opt/ros/humble/setup.bash
ros2 run nav2_map_server map_saver_cli -f ~/maps/my_map
```

### 2) Nav2 패키지 설치 (Jetson)

```bash
sudo apt update
sudo apt install -y \
  ros-humble-navigation2 \
  ros-humble-nav2-bringup
```

### 3) 기본 Bring-up (터미널 분리 권장)

터미널 A: Visual SLAM

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
ros2 launch isaac_ros_visual_slam isaac_ros_visual_slam_realsense.launch.py
```

터미널 B: 모터 드라이버

```bash
source ~/ros2_ws/install/setup.bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

터미널 C: Nav2

```bash
source /opt/ros/humble/setup.bash
ros2 launch nav2_bringup navigation_launch.py \
  use_sim_time:=False \
  autostart:=True \
  map:=/home/<user>/maps/my_map.yaml
```

### 4) 자율주행 목표 전송 (SSH/CLI)

```bash
source /opt/ros/humble/setup.bash
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: map}, pose: {position: {x: 1.0, y: 0.0, z: 0.0}, orientation: {z: 0.0, w: 1.0}}}}"
```

### 5) 동작 확인 체크

- `ros2 topic hz /cmd_vel` 값이 목표 전송 후 발행되는지
- `/visual_slam/tracking/odometry`가 주행 중 끊기지 않는지
- 목표점 근처에서 감속/정지가 정상인지

### 6) 권장 안전 조건

- 초기 최대 속도는 매우 낮게 시작(예: `linear.x <= 0.10 m/s`)
- 장애물 회피 파라미터 튜닝 전에는 넓은 공간에서만 테스트
- 항상 E-stop 활성 상태에서 시험
