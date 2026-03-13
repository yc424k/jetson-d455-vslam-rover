# RealSense D455 Depth 카메라 단독 점검 (Foxglove)

이 문서는 **SLAM 실행 전**, D455의 Color/Depth/IMU 스트림이 정상인지
Foxglove로 먼저 확인하는 절차를 정리합니다.

## 목적

- 카메라 입력 자체가 정상인지 분리 검증
- `librealsense`/ROS 드라이버/네트워크(Foxglove Bridge) 문제를 조기 분리
- SLAM 문제와 카메라 문제를 섞지 않고 디버깅

## 실행 원칙

- 이 점검 단계에서는 `isaac_ros_visual_slam`을 실행하지 않습니다.
- 같은 D455를 두 노드가 동시에 점유하면 장치 충돌이 발생할 수 있습니다.

## 권장 실행 환경

- Jetson + Isaac ROS Docker 컨테이너(`~/workspaces/isaac_ros-dev`)
- MacBook + Foxglove Studio

빠른 시작(컨테이너 내부):

```bash
source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
```

## 실행 순서

### 터미널 A: RealSense 노드

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh -d ~/workspaces/isaac_ros-dev

source /opt/ros/humble/setup.bash
[ -f /workspaces/isaac_ros-dev/install/setup.bash ] && source /workspaces/isaac_ros-dev/install/setup.bash

ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
```

### 터미널 B: Foxglove Bridge

```bash
cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh -d ~/workspaces/isaac_ros-dev

source /opt/ros/humble/setup.bash
[ -f /workspaces/isaac_ros-dev/install/setup.bash ] && source /workspaces/isaac_ros-dev/install/setup.bash

ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765 address:=0.0.0.0
```

### Mac Foxglove 연결

- 연결 주소: `ws://<jetson_ip>:8765`

## Foxglove 권장 패널 구성

1) `Image` 패널 (Color)
- Topic: `/camera/camera/color/image_raw`

2) `Image` 패널 (Depth)
- Topic: `/camera/camera/depth/image_rect_raw`
- Color mode: `Color map`
- Color map: `Turbo` 또는 `Rainbow`
- Value min: `300` (mm)
- Value max: `6000` (mm, 실내면 `4000`도 자주 사용)

3) `Raw Messages` 패널
- `/camera/camera/depth/camera_info`
- `/camera/camera/imu` (또는 `/camera/camera/gyro/sample`, `/camera/camera/accel/sample`)

4) `3D` 패널 (선택)
- `/tf`, `/tf_static` 프레임 확인

## CLI 점검 명령

```bash
ros2 topic list | grep -E "/camera/camera/(color|depth|gyro|accel|imu)"
ros2 topic hz /camera/camera/color/image_raw
ros2 topic hz /camera/camera/depth/image_rect_raw
ros2 topic echo /camera/camera/depth/camera_info --once
```

IMU까지 확인할 경우:

```bash
ros2 topic hz /camera/camera/gyro/sample
ros2 topic hz /camera/camera/accel/sample
ros2 topic echo /camera/camera/imu --once
```

## 합격 기준

- Color/Depth 토픽이 생성되고 `hz`가 연속 갱신됨
- Depth 이미지가 Foxglove Image 패널에서 거리 차이에 따라 색상으로 구분됨
- `camera_info`가 1회 이상 정상 출력됨
- (IMU 사용 시) gyro/accel/imu 토픽이 publish됨

## 자주 발생하는 오류와 즉시 조치

### `Could not load library ... librealsense2.so.2.56`

원인: 컨테이너 내 `librealsense` 런타임 누락

```bash
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo apt-get install -y ros-humble-librealsense2
```

필요 시 realsense 패키지 재빌드:

```bash
cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash
colcon build --symlink-install --packages-select realsense2_camera realsense2_description
```

### `No such device` / `xioctl(VIDIOC_QBUF)` / `RGB modules inconsistency`

원인 후보:
- RealSense 노드 중복 실행(장치 중복 점유)
- USB 케이블/포트 불안정

조치:
- `realsense2_camera` 노드 1개만 실행
- 허브 대신 Jetson USB 3.x 포트에 직결
- 케이블 재장착 후 재시도

### IMU 토픽 미생성

원인 후보:
- `enable_gyro` / `enable_accel` 미설정
- HID/커널 인식 문제

우선 확인:

```bash
ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true unite_imu_method:=2
ls -l /dev/hidraw*
```
