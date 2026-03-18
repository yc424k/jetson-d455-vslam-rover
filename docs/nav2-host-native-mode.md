# Nav2 Host Native 운영 가이드 (Docker 없이)

이 문서는 Jetson Host 환경(`~/ros2_ws`)만 사용해
`D455 + md_motor_driver_ros2 + Nav2`를 실행하는 절차를 정리합니다.

## 목적

- 매번 Docker 컨테이너에 진입하지 않고 Host에서 바로 실행
- RealSense Depth를 `/scan`으로 변환해 2D 맵 생성/자율주행 수행
- MacBook은 SSH/Foxglove 모니터링 용도로만 사용

## 동작 구조 (Host 전용)

- `realsense2_camera` -> `/camera/camera/depth/image_rect_raw`
- `depthimage_to_laserscan` -> `/scan`
- `md_controller` -> `/odom`, `odom -> base_link` TF, `/cmd_vel` 구독
- 맵 생성: `slam_toolbox`
- 자율주행: `Nav2 + AMCL`

> Host 전용 모드에서는 `isaac_ros_visual_slam`을 사용하지 않습니다.
> (즉, Docker/`run_dev.sh`가 필요 없습니다.)

## 사전 조건

- Jetson Orin Nano + JetPack 6.2.2
- ROS 2 Humble Native 설치 완료
- D455 USB 3.x 인식 정상
- 모터 드라이버 하드웨어 연결 및 E-stop 준비

빠른 확인:

```bash
lsusb | grep -i realsense
id -nG | grep -E "dialout|video"
```

## Host-only 운영 규칙

- 같은 부팅 세션에서 Docker 기반 카메라/SLAM 노드와 Host 기반 카메라 노드를 섞어 실행하지 않습니다.
- RealSense는 항상 단일 프로세스만 점유합니다.
- 최초 주행 테스트는 반드시 저속 + 바퀴 띄운 상태에서 수행합니다.

## 실행 전 정합 체크 (권장)

아래 4개가 통과되면 맵 생성/자율주행 성공률이 높아집니다.

점검 순서:

1. `realsense2_camera` 실행
2. `depthimage_to_laserscan` 실행
3. `md_controller` 실행
4. 아래 확인 명령 수행

1) D455 토픽 생성 확인:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic list | grep -E "/camera/camera/(color|depth|gyro|accel|imu)"
```

2) 모터 드라이버에서 odom/TF 확인:

```bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

다른 터미널:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic hz /odom
ros2 run tf2_ros tf2_echo odom base_link
```

3) `/scan` 생성 확인:

```bash
ros2 topic hz /scan
```

4) 저속 `/cmd_vel` 단발 테스트:

```bash
ros2 topic pub -1 /cmd_vel geometry_msgs/msg/Twist \
"{linear: {x: 0.05, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}"
```

## 1회 설치/빌드 (Host)

### 1) 패키지 설치

```bash
sudo apt update
sudo apt install -y \
  ros-humble-librealsense2 \
  ros-humble-depthimage-to-laserscan \
  ros-humble-slam-toolbox \
  ros-humble-navigation2 \
  ros-humble-nav2-bringup \
  ros-humble-nav2-map-server \
  ros-humble-foxglove-bridge \
  ros-humble-teleop-twist-keyboard \
  librealsense2-utils
```

### 2) 소스 준비 (`~/ros2_ws/src`)

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src

# RealSense ROS (JetPack 6.2.2 호환 태그 고정)
[ -d realsense-ros ] || git clone https://github.com/IntelRealSense/realsense-ros.git
cd realsense-ros
git fetch --tags
git checkout 4.56.4
cd ~/ros2_ws/src

# 모터 드라이버
[ -d md_motor_driver_ros2 ] || git clone https://github.com/yc424k/md_motor_driver_ros2.git

# serial 의존성
[ -d serial-ros2 ] || git clone https://github.com/RoverRobotics-forks/serial-ros2.git
```

### 3) 의존성 설치 + 빌드

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash

rosdep update
rosdep install --from-paths src --ignore-src -r -y

colcon build --symlink-install --packages-up-to \
  serial \
  realsense2_camera \
  realsense2_description \
  md_controller \
  md_teleop

source ~/ros2_ws/install/setup.bash
```

빌드 확인:

```bash
ros2 pkg list | grep -E "^realsense2_camera$|^depthimage_to_laserscan$|^slam_toolbox$|^nav2_bringup$|^md_controller$|^serial$"
```

## 모터 포트 고정 (권장)

재부팅 후 `/dev/ttyUSB*` 순서가 바뀌지 않도록 udev 링크를 고정합니다.

```bash
cd <repo_root>
./util/setup_motor_udev.sh --list
./util/setup_motor_udev.sh --left /dev/ttyUSB0 --right /dev/ttyUSB1
ls -l /dev/ttyMotorLeft /dev/ttyMotorRight
```

그 다음 `md_controller.launch.py`에서 포트를 고정 링크로 맞춥니다.

- `Port: /dev/ttyMotorLeft`
- `RightUseSeparatePort: True`
- `RightPort: /dev/ttyMotorRight`

## A) 맵 생성 모드 (Host)

모든 터미널 공통:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
```

### 터미널 1: RealSense

```bash
ros2 launch realsense2_camera rs_launch.py \
  enable_color:=true \
  enable_gyro:=true \
  enable_accel:=true \
  rgb_camera.color_profile:=1280x720x15 \
  depth_module.depth_profile:=640x360x10 \
  unite_imu_method:=2
```

### 터미널 2: Depth -> LaserScan

```bash
ros2 run depthimage_to_laserscan depthimage_to_laserscan_node --ros-args \
  -r depth:=/camera/camera/depth/image_rect_raw \
  -r depth_camera_info:=/camera/camera/depth/camera_info \
  -r scan:=/scan \
  -p range_min:=0.25 \
  -p range_max:=3.5
```

### 터미널 3: 모터 드라이버

```bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

### 터미널 4: 저속 수동 주행

```bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

### 터미널 5: SLAM Toolbox

```bash
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

### 맵 저장

```bash
mkdir -p ~/maps
ros2 run nav2_map_server map_saver_cli -f ~/maps/my_map
```

결과 파일:

- `~/maps/my_map.yaml`
- `~/maps/my_map.pgm`

## B) 자율주행 모드 (Host, AMCL)

모든 터미널 공통:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
```

### 터미널 1: RealSense

```bash
ros2 launch realsense2_camera rs_launch.py \
  enable_color:=true \
  enable_gyro:=true \
  enable_accel:=true \
  rgb_camera.color_profile:=1280x720x15 \
  depth_module.depth_profile:=640x360x10 \
  unite_imu_method:=2
```

### 터미널 2: Depth -> LaserScan

```bash
ros2 run depthimage_to_laserscan depthimage_to_laserscan_node --ros-args \
  -r depth:=/camera/camera/depth/image_rect_raw \
  -r depth_camera_info:=/camera/camera/depth/camera_info \
  -r scan:=/scan \
  -p range_min:=0.25 \
  -p range_max:=3.5
```

### 터미널 3: 모터 드라이버

```bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

### 터미널 4: Nav2 실행

기본 실행:

```bash
ros2 launch nav2_bringup navigation_launch.py \
  use_sim_time:=False \
  autostart:=True \
  use_rviz:=False \
  map:=/home/$USER/maps/my_map.yaml
```

권장(파라미터 파일 분리):

```bash
mkdir -p ~/ros2_ws/config
cp /opt/ros/humble/share/nav2_bringup/params/nav2_params.yaml \
   ~/ros2_ws/config/nav2_params_host.yaml
```

`~/ros2_ws/config/nav2_params_host.yaml`에서 필요 시 아래 항목을 하드웨어에 맞춰 수정:

- `amcl.ros__parameters.scan_topic: /scan`
- `amcl.ros__parameters.base_frame_id: base_link`
- `amcl.ros__parameters.odom_frame_id: odom`
- `bt_navigator.ros__parameters.global_frame: map`
- `bt_navigator.ros__parameters.robot_base_frame: base_link`

분리 파라미터 적용 실행:

```bash
ros2 launch nav2_bringup navigation_launch.py \
  use_sim_time:=False \
  autostart:=True \
  use_rviz:=False \
  map:=/home/$USER/maps/my_map.yaml \
  params_file:=/home/$USER/ros2_ws/config/nav2_params_host.yaml
```

### 터미널 5: 초기 자세(Initial Pose) 입력

RViz를 쓰지 않는 경우 1회 수동으로 초기 자세를 줍니다.

```bash
ros2 topic pub -1 /initialpose geometry_msgs/msg/PoseWithCovarianceStamped \
"{header: {frame_id: map}, pose: {pose: {position: {x: 0.0, y: 0.0, z: 0.0}, orientation: {z: 0.0, w: 1.0}}, covariance: [0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.068]}}"
```

### 터미널 6: 목표점 전송

```bash
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: map}, pose: {position: {x: 1.0, y: 0.0, z: 0.0}, orientation: {z: 0.0, w: 1.0}}}}"
```

## MacBook 모니터링 (선택)

Jetson에서:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765 address:=0.0.0.0
```

Mac Foxglove 연결:

- `ws://<jetson_ip>:8765`
- 확인 토픽: `/scan`, `/map`, `/odom`, `/tf`, `/amcl_pose`

## 필수 점검 명령

```bash
ros2 topic hz /scan
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo map odom
ros2 topic echo /amcl_pose --once
ros2 topic hz /cmd_vel
```

## 자주 막히는 지점

- `nav2` 실행 후 로봇이 안 움직임
  - 초기 자세(`/initialpose`)를 안 준 경우가 많습니다.
- `map -> odom` TF 없음
  - `amcl`이 `/scan`을 못 받거나 맵 경로가 틀린 상태입니다.
- 직진 명령에서 한쪽 역회전
  - `md_controller.launch.py`의 `left_sign`/`right_sign` 보정이 필요합니다.
- `No such device`/카메라 끊김
  - USB 3.x 직결, 허브 제거, 해상도/프레임 하향으로 먼저 안정화합니다.

상세 에러 대응은 [트러블슈팅 모음](troubleshooting.md)을 참고하세요.
