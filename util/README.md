# util 사용 가이드

이 폴더는 반복 작업을 줄이기 위한 보조 스크립트를 모아둔 곳입니다.

## 포함 스크립트

- `bootstrap_isaac_container.sh`
- `setup_motor_udev.sh`
- `setup_lidar_udev.sh`
- `run_rplidar_s3_mapping.sh`

## 1) `bootstrap_isaac_container.sh`

목적:

- Isaac ROS 컨테이너 재접속 시 필요한 초기화 작업을 한 번에 수행
- ROS 환경 source
- 문제 저장소(yarn) 제거
- 매핑/시각화 필수 패키지 자동 설치(없을 때만)
- 워크스페이스 overlay 자동 source

실행 위치:

- **컨테이너 내부** (`admin@ubuntu:/workspaces/isaac_ros-dev`)

사용 방법:

```bash
source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
```

파일이 안 보일 때(마운트 경로 꼬임) 복구:

```bash
# host
docker rm -f isaac_ros_dev-aarch64-container 2>/dev/null || true

cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh -d ~/workspaces/isaac_ros-dev
```

그 다음 컨테이너에서 다시:

```bash
source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
```

자동 점검 패키지:

```bash
ros-humble-librealsense2
ros-humble-rplidar-ros
ros-humble-slam-toolbox
ros-humble-nav2-map-server
ros-humble-foxglove-bridge
```

주의:

- 이 스크립트는 `source`로 실행해야 현재 셸에 환경이 반영됩니다.
- `run_dev.sh`는 호스트에서 실행하고, 이 스크립트는 컨테이너에서 실행합니다.

## 2) `setup_motor_udev.sh`

목적:

- 모터 시리얼 장치(`/dev/ttyUSB*`, `/dev/ttyACM*`)를 고정 심볼릭 링크로 매핑
- 재부팅 후에도 `/dev/ttyMotorLeft`, `/dev/ttyMotorRight`로 안정적으로 접근

실행 위치:

- **호스트** (`ml406@ubuntu:~`)

1) 후보 장치 확인:

```bash
cd ~/ros2_ws/src/md_motor_driver_ros2/util 2>/dev/null || cd /path/to/this/repo/util
./setup_motor_udev.sh --list
```

2) 규칙 생성/적용:

```bash
./setup_motor_udev.sh --left /dev/ttyUSB0 --right /dev/ttyUSB1
```

3) 결과 확인:

```bash
ls -l /dev/ttyMotorLeft /dev/ttyMotorRight
```

옵션 예시:

```bash
./setup_motor_udev.sh \
  --left /dev/ttyUSB1 \
  --right /dev/ttyUSB0 \
  --left-link ttyMotorA \
  --right-link ttyMotorB
```

주의:

- 스크립트가 `sudo`를 사용해 udev rule을 설치합니다.
- 어댑터를 바꾸면(하드웨어 교체) 규칙을 다시 생성하는 것이 안전합니다.

## 3) `setup_lidar_udev.sh`

목적:

- 라이다 시리얼 장치를 `/dev/ttyLidar` 고정 심볼릭 링크로 매핑
- 재부팅/재연결 후에도 라이다 포트명이 안정적으로 유지되게 설정

실행 위치:

- **호스트** (`ml406@ubuntu:~`)

1) 후보 장치 확인:

```bash
cd ~/ros2_ws/src/md_motor_driver_ros2/util 2>/dev/null || cd /path/to/this/repo/util
./setup_lidar_udev.sh --list
```

2) 규칙 생성/적용:

```bash
./setup_lidar_udev.sh --device /dev/ttyUSB0
```

3) 결과 확인:

```bash
ls -l /dev/ttyLidar
```

옵션 예시:

```bash
./setup_lidar_udev.sh \
  --device /dev/ttyACM0 \
  --link ttyLidar
```

주의:

- 스크립트가 `sudo`를 사용해 udev rule을 설치합니다.
- 라이다 어댑터를 바꾸면(하드웨어 교체) 규칙을 다시 생성하는 것이 안전합니다.

## 4) `run_rplidar_s3_mapping.sh`

목적:

- `RPLIDAR S3M1 -> /scan -> slam_toolbox`를 한 번에 실행
- 맵 생성 모드 반복 실행 시 터미널 수를 줄여 운용 단순화

실행 위치:

- **호스트 또는 컨테이너 내부** (ROS 2 Humble 환경 source 가능한 셸)

사용 방법:

```bash
cd <repo_root>
SERIAL_PORT=/dev/ttyLidar ./util/run_rplidar_s3_mapping.sh
```

환경변수(선택):

- `SERIAL_PORT` (기본: `/dev/ttyLidar`)
- `SERIAL_BAUDRATE` (기본: `1000000`)
- `FRAME_ID` (기본: `laser`)
- `SCAN_MODE` (기본: `DenseBoost`)
- `MIN_LASER_RANGE` (기본: `0.20`)
- `MAX_LASER_RANGE` (기본: `25.0`)

주의:

- `odom -> base_link` TF는 `md_controller`에서 먼저 발행되어야 합니다.
- `base_link -> laser` TF가 없으면 `static_transform_publisher` 또는 URDF로 먼저 제공해야 합니다.

## 추천 운영 순서

1. 호스트에서 `run_dev.sh`로 컨테이너 진입
2. 컨테이너에서 `bootstrap_isaac_container.sh` 실행
3. 호스트에서 필요 시 `setup_motor_udev.sh`로 포트 고정
4. 호스트에서 `setup_lidar_udev.sh`로 라이다 포트(`/dev/ttyLidar`) 고정
5. 맵 생성 시 `run_rplidar_s3_mapping.sh` 또는 문서의 수동 실행 절차 사용
