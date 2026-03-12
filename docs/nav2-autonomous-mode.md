# Nav2 자율주행 모드

이 문서는 이미 만들어진 2D 맵(`.yaml`, `.pgm`)을 사용해 Nav2 자율주행을 실행하는 절차를 설명합니다.

## 사전 조건

- 맵 파일 존재: `~/maps/my_map.yaml`, `~/maps/my_map.pgm`
- 모터 드라이버(`/cmd_vel`) 정상 구동
- Visual SLAM 정상 동작 (`/visual_slam/status`에서 `vo_state: 1`)

맵이 없으면 먼저:

- [Nav2 준비 - 맵 생성 모드](nav2-mapping-mode.md)

## 패키지 설치 (Host 1회)

```bash
sudo apt update
sudo apt install -y \
  ros-humble-navigation2 \
  ros-humble-nav2-bringup
```

## 실행 순서

### 터미널 A(컨테이너): Visual SLAM + RealSense

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 launch isaac_ros_visual_slam isaac_ros_visual_slam_realsense.launch.py
```

### 터미널 B(Host): 모터 드라이버

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

### 터미널 C(Host): Nav2

```bash
source /opt/ros/humble/setup.bash
ros2 launch nav2_bringup navigation_launch.py \
  use_sim_time:=False \
  autostart:=True \
  map:=/home/<user>/maps/my_map.yaml
```

## 목표 전송

```bash
source /opt/ros/humble/setup.bash
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: map}, pose: {position: {x: 1.0, y: 0.0, z: 0.0}, orientation: {z: 0.0, w: 1.0}}}}"
```

## 확인 포인트

- `ros2 topic hz /cmd_vel`가 목표 전송 후 발행되는지
- `/visual_slam/tracking/odometry`가 주행 중 안정적인지
- 목표점 근처에서 감속/정지가 정상인지

## 중요 주의사항

- 자율주행 모드에서 `ros2 launch realsense2_camera ...`를 별도로 켜지 않습니다.
- 이유: `isaac_ros_visual_slam_realsense.launch.py`가 카메라 노드를 포함하므로 중복 실행 시 장치 충돌이 날 수 있습니다.
