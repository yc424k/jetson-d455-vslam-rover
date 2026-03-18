# Nav2 준비 - 맵 생성 모드

이 문서는 **RealSense만으로 2D 점유맵(`.yaml`, `.pgm`)을 만드는 단계**를 설명합니다.

## 목적

- `/scan`(depth 변환) 기반으로 `slam_toolbox` 맵 생성
- 최종 결과로 `~/maps/my_map.yaml`, `~/maps/my_map.pgm` 저장

## 핵심 개념

- 여기서 말하는 "2D 정적 맵 파일"은 **지금 이 모드에서 직접 만든 결과물**입니다.
- 즉, 미리 준비된 파일이 아니라 맵 생성 후 저장되는 출력입니다.

## 권장 실행 환경

- RealSense/SLAM/Foxglove Bridge: Docker 컨테이너(`~/workspaces/isaac_ros-dev`)
- 모터 구동/teleop: Host(`~/ros2_ws`)

빠른 시작(컨테이너 내부):

```bash
source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
```

## 사전 설치 (컨테이너 내부 1회)

> `source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh`를 실행했다면
> 아래 설치는 대부분 자동으로 처리되므로 생략할 수 있습니다.

```bash
# apt update를 막는 불필요 저장소(yarn) 제거
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*

sudo apt update
sudo apt install -y \
  ros-humble-librealsense2 \
  ros-humble-depthimage-to-laserscan \
  ros-humble-slam-toolbox \
  ros-humble-nav2-map-server \
  ros-humble-foxglove-bridge
```

## 실행 순서

### 터미널 A: RealSense

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 launch realsense2_camera rs_launch.py \
  enable_color:=true \
  enable_gyro:=true \
  enable_accel:=true \
  depth_module.depth_profile:=640x360x10 \
  unite_imu_method:=2
```

### 터미널 B: Depth -> LaserScan (`/scan`)

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 run depthimage_to_laserscan depthimage_to_laserscan_node --ros-args \
  -r depth:=/camera/camera/depth/image_rect_raw \
  -r depth_camera_info:=/camera/camera/depth/camera_info \
  -r scan:=/scan \
  -p range_min:=0.25 \
  -p range_max:=6.0
```

### 터미널 C: SLAM Toolbox

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 run slam_toolbox async_slam_toolbox_node --ros-args \
  -r scan:=/scan \
  -p base_frame:=base_link \
  -p odom_frame:=odom \
  -p map_frame:=map \
  -p throttle_scans:=5 \
  -p minimum_time_interval:=0.25 \
  -p scan_queue_size:=1000 \
  -p transform_timeout:=1.0 \
  -p tf_buffer_duration:=120.0 \
  -p minimum_laser_range:=0.25 \
  -p max_laser_range:=4.0
```

### 터미널 D: Foxglove Bridge (선택)

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765 address:=0.0.0.0
```

Mac Foxglove 연결:

- `ws://<jetson_ip>:8765`
- 확인 토픽: `/map`, `/scan`, `/tf`

### 터미널 E(Host): 저속 수동 주행

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

다른 Host 터미널:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

## 맵 저장

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
mkdir -p ~/maps
ros2 run nav2_map_server map_saver_cli -f ~/maps/my_map
```

생성 결과:

- `~/maps/my_map.yaml`
- `~/maps/my_map.pgm`

## 중요 주의사항

- 맵 생성 모드에서는 `isaac_ros_visual_slam_realsense.launch.py`를 **동시에 실행하지 않습니다**.
- 이유: RealSense 장치 중복 점유로 `No such device`류 에러가 발생할 수 있습니다.
- 줄바꿈용 `\` 뒤에 공백이 들어가면 인자 파싱이 깨질 수 있습니다.
  - 잘못된 예: `-p tf_buffer_duration:=120.0 \ `

## 자주 발생하는 로그와 대응

아래 로그가 반복되면 매핑 품질이 떨어질 수 있습니다.

- `discarding message because the queue is full`
- `the timestamp on the message is earlier than all the data in the transform cache`

확인 명령:

```bash
ros2 topic hz /scan
ros2 run tf2_ros tf2_echo odom base_link
ros2 topic echo /map --once --qos-durability transient_local
```

점검 기준:

- `/scan`은 대체로 8~15Hz면 충분합니다.
- `odom -> base_link` TF가 안정적으로 이어져야 합니다.
