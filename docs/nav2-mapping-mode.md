# Nav2 준비 - 맵 생성 모드 (RPLIDAR S3M1)

이 문서는 **RPLIDAR S3M1의 `/scan` 토픽으로 2D 점유맵(`.yaml`, `.pgm`)을 생성**하는 절차를 설명합니다.

## 목적

- `/scan`(RPLIDAR) 기반으로 `slam_toolbox` 맵 생성
- 최종 결과로 `~/maps/my_map.yaml`, `~/maps/my_map.pgm` 저장

## 핵심 개념

- 여기서 말하는 "2D 정적 맵 파일"은 **이 모드에서 직접 만든 결과물**입니다.
- 즉, 미리 준비된 파일이 아니라 맵 생성 후 저장되는 출력입니다.

## 사전 조건

- RPLIDAR S3M1이 Jetson에 USB로 연결되어 있고 포트가 확인됨 (`/dev/ttyUSB0` 등)
- `md_controller`가 `odom -> base_link` TF를 안정적으로 발행
- `base_link -> laser` TF가 준비됨
  - URDF가 없다면 `static_transform_publisher`로 임시 발행 가능

빠른 확인:

```bash
ls -l /dev/ttyUSB*
id -nG | grep dialout
```

## 사전 설치 (컨테이너 내부 1회)

> `source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh`를 실행했다면
> 아래 설치는 대부분 자동 처리되므로 생략할 수 있습니다.

```bash
# apt update를 막는 불필요 저장소(yarn) 제거
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*

sudo apt update
sudo apt install -y \
  ros-humble-rplidar-ros \
  ros-humble-slam-toolbox \
  ros-humble-nav2-map-server \
  ros-humble-foxglove-bridge
```

## 실행 순서

### 터미널 A: RPLIDAR S3M1 (`/scan`)

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash

ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:=/dev/ttyUSB0 \
  -p serial_baudrate:=1000000 \
  -p frame_id:=laser \
  -p inverted:=false \
  -p angle_compensate:=true \
  -p scan_mode:=DenseBoost \
  -r scan:=/scan
```

### 터미널 B: `base_link -> laser` TF (필요 시)

이미 URDF/robot_state_publisher에서 TF가 나오면 이 단계는 생략합니다.

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash

# 예시값(반드시 실제 장착 위치로 수정)
ros2 run tf2_ros static_transform_publisher \
  0.10 0.0 0.18 0.0 0.0 0.0 base_link laser
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
  -p throttle_scans:=2 \
  -p minimum_time_interval:=0.1 \
  -p scan_queue_size:=2000 \
  -p transform_timeout:=1.0 \
  -p tf_buffer_duration:=120.0 \
  -p minimum_laser_range:=0.20 \
  -p max_laser_range:=25.0
```

### 터미널 D (Host): 저속 수동 주행

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

### 터미널 E: Foxglove Bridge (선택)

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

## 원커맨드 실행 (선택)

아래 스크립트는 RPLIDAR + SLAM Toolbox를 한 번에 실행합니다.

```bash
cd <repo_root>
SERIAL_PORT=/dev/ttyUSB0 ./util/run_rplidar_s3_mapping.sh
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

## 자주 발생하는 로그와 대응

아래 로그가 반복되면 매핑 품질이 떨어질 수 있습니다.

- `discarding message because the queue is full`
- `Lookup would require extrapolation into the past`

확인 명령:

```bash
ros2 topic hz /scan
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo base_link laser
ros2 topic echo /map --once --qos-durability transient_local
```

점검 기준:

- `/scan`은 대체로 10Hz 이상이면 충분합니다.
- `odom -> base_link`, `base_link -> laser` TF가 끊기지 않아야 합니다.
- `minimum_laser_range`/`max_laser_range`는 실환경 노이즈에 맞게 조정합니다.
