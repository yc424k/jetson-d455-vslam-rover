# Jetson Orin Nano + Intel RealSense D455 초기 설정 가이드

이 문서는 **Jetson Orin Nano 1대**에서 아래를 모두 수행하는 구성을 기준으로 작성되었습니다.

- 카메라 입력 (D455)
- Visual SLAM (Isaac ROS Visual SLAM)
- 로봇 제어 (md_motor_driver_ros2)
- 원격 개발 (MacBook SSH)

## 빠른 목차

- [1) 목표 아키텍처](#sec-1)
- [2) 사전 준비 체크리스트](#sec-2)
- [3) Jetson 기본 환경 세팅](#sec-3)
- [4) ROS 2 Humble 환경 준비](#sec-4)
- [5) RealSense(D455) 연결 및 기본 확인](#sec-5)
- [6) ROS 2 RealSense 드라이버 준비](#sec-6)
- [7) Isaac ROS Visual SLAM 적용 순서](#sec-7)
- [8) 모터 제어 드라이버 연동](#sec-8)
- [9) 권장 ROS 2 노드 구조](#sec-9)
- [10) 원격 개발 운영 방식 (MacBook)](#sec-10)
- [11) 단계별 Bring-up 권장 순서](#sec-11)
- [12) 초기 점검 체크리스트](#sec-12)
- [13) 트러블슈팅 메모](#sec-13)
- [14) 운영 원칙 요약](#sec-14)
- [15) Nav2 기반 자율주행 실행](#sec-15)

## 상세 문서

- [모터 드라이버 연동 상세](docs/motor-driver-integration.md)
- [Depth 카메라 단독 점검 (Foxglove)](docs/depth-camera-validation.md)
- [Nav2 운영 가이드 (모드 분리)](docs/nav2-autonomous-driving.md)
- [Nav2 Host Native 모드 (Docker 없이)](docs/nav2-host-native-mode.md)
- [Nav2 준비 - 맵 생성 모드](docs/nav2-mapping-mode.md)
- [Nav2 자율주행 모드](docs/nav2-autonomous-mode.md)
- [트러블슈팅 모음](docs/troubleshooting.md)
- [모터 USB 포트 고정 스크립트](util/setup_motor_udev.sh)
- [Isaac 컨테이너 부트스트랩 스크립트](util/bootstrap_isaac_container.sh)

---

<a id="sec-1"></a>
## 1) 목표 아키텍처

- **Jetson Orin Nano (JetPack 6.2.2)**
  - ROS 2 Humble
  - RealSense ROS 드라이버
  - Isaac ROS Visual SLAM (Docker 컨테이너에서 실행 권장)
  - 모터 제어 노드 (`md_motor_driver_ros2`)
- **Intel RealSense D455**
  - Stereo Depth + RGB + IMU
- **MacBook**
  - SSH / VS Code Remote SSH / 로그 확인 / 시각화

<a id="sec-2"></a>
## 2) 사전 준비 체크리스트

### 하드웨어

- Jetson Orin Nano Developer Kit
- Intel RealSense D455 + USB 3.x 케이블
- 모터 드라이버(해당 로봇 시스템과 호환)
- 안정적인 전원 공급

### 소프트웨어

- JetPack **6.2.2** 설치 완료
- 같은 네트워크의 MacBook
- SSH 접속 가능 상태

<a id="sec-3"></a>
## 3) Jetson 기본 환경 세팅

> 아래 명령은 Jetson에서 실행합니다.

### 시스템 업데이트

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

### 필수 개발 도구

```bash
sudo apt install -y \
  git curl wget vim tmux htop unzip \
  build-essential cmake pkg-config \
  python3-pip
```

### Docker 설치/권한 설정 (Isaac ROS 컨테이너 필수)

JetPack 6.x에서 Docker가 이미 설치된 경우도 있지만, 아래 순서로 점검/설정하는 것을 권장합니다.

```bash
# Docker가 없으면 설치
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io docker-compose-plugin
fi

# Docker 서비스 시작
sudo systemctl enable --now docker

# 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER

# 현재 세션에 그룹 반영 (또는 SSH 재접속)
newgrp docker

# 동작 확인
docker --version
docker ps
```

확인 포인트:

- `docker ps`가 `permission denied` 없이 실행되어야 합니다.
- Isaac ROS 실행 전 `id -nG | grep docker`에서 `docker` 그룹이 보여야 합니다.

### 작업 디렉터리 구성

```bash
mkdir -p ~/workspace ~/ros2_ws/src
```

<a id="sec-4"></a>
## 4) ROS 2 Humble 환경 준비

JetPack 6.x 계열에서는 ROS 2 설치 방식이 환경마다 조금 다를 수 있으므로,
**팀 내에서 Docker 기반 / Native 기반 중 하나로 통일**하는 것을 권장합니다.

### (A안) Native 설치 선택 시 기본 골격

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y

sudo apt update
sudo apt install -y curl

export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')

curl -L -o /tmp/ros2-apt-source.deb \
"https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"

sudo dpkg -i /tmp/ros2-apt-source.deb
sudo apt update

sudo apt install -y \
  ros-humble-desktop \
  python3-colcon-common-extensions \
  python3-vcstool
```

쉘/워크스페이스 환경 등록(권장: 조건부 source):

```bash
# 기존 중복 라인 정리
sed -i '\|source /opt/ros/humble/setup.bash|d' ~/.bashrc
sed -i '\|source ~/ros2_ws/install/setup.bash|d' ~/.bashrc

# 파일이 존재할 때만 source
echo 'if [ -f /opt/ros/humble/setup.bash ]; then source /opt/ros/humble/setup.bash; fi' >> ~/.bashrc
echo 'if [ -f ~/ros2_ws/install/setup.bash ]; then source ~/ros2_ws/install/setup.bash; fi' >> ~/.bashrc

source ~/.bashrc
```

왜 필요한가:

- `/opt/ros/humble/setup.bash`는 ROS 2 기본 환경변수(`PATH`, `AMENT_PREFIX_PATH` 등)를 로드합니다.
- `~/ros2_ws/install/setup.bash`는 로컬에서 빌드한 패키지를 ROS가 찾게 하는 overlay 설정입니다.
- 적용 순서는 `ROS 기본 환경 -> 워크스페이스 환경`이 맞습니다.
- `~/ros2_ws/install/setup.bash`는 `colcon build` 이후 생성되므로, 조건부 source를 쓰면 첫 빌드 전에도 에러 없이 동작합니다.

> 참고: 환경에 따라 의존 패키지/저장소 추가가 필요할 수 있습니다.

<a id="sec-5"></a>
## 5) RealSense(D455) 연결 및 기본 확인

### 장치 인식 확인

```bash
lsusb | grep -i realsense
```

### (SSH/headless 권장) CLI 기반 장치 확인

```bash
sudo apt install -y librealsense2-utils
rs-enumerate-devices
```

> `realsense-viewer`는 GUI가 필요하므로 SSH/headless 환경에서는 보통 실행하지 않습니다.

확인 포인트:

- D455 모델/시리얼/USB 타입(3.x) 정상 인식
- Firmware/Recommended Firmware 버전 확인
- Color/Depth/IMU 지원 프로파일이 출력되는지 확인

> 실제 ROS 스트림 출력, 주기(`hz`), 프레임 드랍 확인은 **6번(드라이버 준비 후)** 단계에서 수행합니다.
> Depth 카메라 단독 + Foxglove 시각화 점검 절차는 `docs/depth-camera-validation.md`를 참고하세요.

<a id="sec-6"></a>
## 6) ROS 2 RealSense 드라이버 준비

```bash
cd ~/ros2_ws/src
git clone https://github.com/IntelRealSense/realsense-ros.git
cd realsense-ros
git checkout 4.56.4
```

### `rosdep`이란?

- ROS 패키지의 `package.xml`을 읽어서 필요한 시스템 의존성을 자동으로 설치하는 도구입니다.
- 수동으로 라이브러리를 하나씩 찾지 않고, 빌드 전에 의존성을 한 번에 맞출 수 있습니다.

### rosdep 설치/초기화 (최초 1회)

```bash
sudo apt update
sudo apt install -y python3-rosdep || sudo apt install -y python3-rosdep2

# 최초 1회만 초기화
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi

rosdep update
```

버전 확인(권장):

```bash
dpkg -s librealsense2 | grep Version
```

### 왜 `ros2-master` 대신 `4.56.4`를 쓰는가? (중요)

- `realsense-ros` GitHub의 `ros2-master`는 시점에 따라 더 높은 `librealsense2` 버전을 요구할 수 있습니다.
- 실제 JetPack 6.2.2 환경에서는 `librealsense2`가 `2.56.4` 또는 `2.56.5`로 설치되는 경우가 많습니다.
- 이 상태에서 `ros2-master`를 빌드하면 CMake 단계에서 `requested version "2.56.6"` 같은 버전 불일치가 발생할 수 있습니다.
- `4.56.4` 태그는 `find_package(realsense2 2.56)` 기준으로 동작해 `2.56.4/2.56.5` 환경과 호환성이 좋습니다.

정리:

- 최신 브랜치(ros2-master)를 무조건 쓰는 것보다, **현재 시스템에 설치된 librealsense2 버전에 맞는 태그를 고정**하는 것이 빌드 안정성이 높습니다.

의존성 설치 및 빌드:

```bash
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

기본 실행 예시:

```bash
ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
```

### ROS 토픽 기반 확인(드라이버 준비 후 실행)

1) RealSense 노드 실행:

```bash
ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
```

2) 다른 터미널에서 토픽 확인:

```bash
ros2 topic list | grep -E "/camera/(color|depth|gyro|accel|imu)"
```

> 네임스페이스에 따라 `/camera/camera/...` 형태로 보일 수 있습니다. 먼저 `ros2 topic list`로 실제 토픽 이름을 확인한 뒤 그대로 사용합니다.

3) 주요 토픽 주기 확인:

```bash
ros2 topic hz /camera/camera/color/image_raw
ros2 topic hz /camera/camera/depth/image_rect_raw
ros2 topic hz /camera/camera/gyro/sample
ros2 topic hz /camera/camera/accel/sample
```

4) 실제 메시지 1개 확인:

```bash
ros2 topic echo /camera/camera/gyro/sample --once
ros2 topic echo /camera/camera/accel/sample --once
```

판단 기준(초기 점검):

- `ros2 topic list`에 color/depth/gyro/accel 관련 토픽이 보인다.
- `ros2 topic hz`에서 값이 0으로 고정되지 않고 연속적으로 갱신된다.
- `--once`로 실제 메시지(헤더/타임스탬프 포함)가 출력된다.

### 재부팅 후 D455 장치 고정 (권장: `serial_no` 기준)

재부팅 시 `/dev/video*` 번호가 바뀌는 것은 정상입니다.  
RealSense는 단일 카메라여도 여러 video 노드를 만들기 때문에, **장치 경로(`/dev/videoX`)를 고정하지 말고 시리얼 번호로 고정**하는 것이 가장 안전합니다.

1) D455 시리얼 확인:

```bash
rs-enumerate-devices | grep -E "Name|Serial Number"
```

2) 실행 시 시리얼 지정:

```bash
ros2 launch realsense2_camera rs_launch.py \
  serial_no:=_234222301994 \
  enable_gyro:=true \
  enable_accel:=true
```

주의:

- `serial_no` 앞 `_`는 문자열로 안전하게 전달하기 위한 관례입니다.
- 다중 카메라 환경이면 각 카메라마다 서로 다른 `serial_no`를 지정합니다.

### IMU 커널 활성화 (Jetson, 필요 시)

아래 조건이면 커널 HID/IIO 옵션이 비활성화된 경우가 많습니다.

- launch 로그에 `No HID info provided, IMU is disabled`가 출력됨
- `ros2 topic list | grep -E "/camera/.*/(gyro|accel|imu)"` 결과가 비어 있음
- `modprobe hid_sensor_accel_3d` 시 `Module ... not found` 발생

1) 먼저 모듈 존재 여부 확인:

```bash
modinfo hid_sensor_accel_3d
modinfo hid_sensor_gyro_3d
```

2) 모듈이 없으면(권장: Jetson에서 직접) 커널 옵션 활성화 후 재빌드:

```bash
sudo apt update
sudo apt install -y build-essential bc flex bison libssl-dev zstd libncurses-dev dwarves wget

mkdir -p ~/kernel_r36 && cd ~/kernel_r36
wget -O public_sources.tbz2 https://developer.download.nvidia.com/embedded/L4T/r36_Release_v5.0/sources/public_sources.tbz2
tar xf public_sources.tbz2

KERNEL_TBZ2=$(find . -name kernel_src.tbz2 | head -n1)
mkdir -p Linux_for_Tegra/source
tar xf "$KERNEL_TBZ2" -C Linux_for_Tegra/source

cd Linux_for_Tegra/source/kernel/kernel-jammy-src
zcat /proc/config.gz > .config

./scripts/config --enable HID_SENSOR_HUB
./scripts/config --enable HID_SENSOR_IIO_COMMON
./scripts/config --module HID_SENSOR_ACCEL_3D
./scripts/config --module HID_SENSOR_GYRO_3D
./scripts/config --enable IIO
./scripts/config --enable IIO_BUFFER
./scripts/config --enable IIO_TRIGGERED_BUFFER
./scripts/config --set-str LOCALVERSION "-tegra"
./scripts/config --disable LOCALVERSION_AUTO

make olddefconfig
make -j"$(nproc)" Image modules

sudo cp /boot/Image /boot/Image.backup.$(date +%F-%H%M)
sudo cp arch/arm64/boot/Image /boot/Image
sudo make modules_install
sudo depmod -a
sudo nv-update-initrd
sudo reboot
```

3) 재부팅 후 확인:

```bash
modprobe hid_sensor_accel_3d
modprobe hid_sensor_gyro_3d
lsmod | grep hid_sensor

ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
ros2 topic list | grep -E "/camera/.*/(gyro|accel|imu)"
```

왜 필요한가:

- D455의 IMU는 HID/IIO 경로를 사용합니다.
- JetPack 6.x 기본 커널 설정에서 해당 옵션이 빠져 있으면 RGB/Depth는 동작해도 IMU 토픽은 생성되지 않습니다.

<a id="sec-7"></a>
## 7) Isaac ROS Visual SLAM 적용 순서

아래는 **Isaac ROS 컨테이너 기반(권장/기본)** 명령 순서입니다.

### 왜 Isaac ROS는 Docker에서 실행하나? (중요)

이 문서는 **Isaac ROS를 Docker에서 실행하는 것을 기본 운영 방식**으로 가정합니다.

이유:

- **환경 재현성**: JetPack/ROS/Isaac ROS 의존성 버전을 컨테이너 이미지로 고정해, 다음날 재실행 시에도 같은 환경을 유지하기 쉽습니다.
- **패키지 충돌 방지**: 호스트 `~/ros2_ws`와 Isaac 워크스페이스가 섞이면서 발생하는 `package not found`, schema/service 로딩 오류를 줄일 수 있습니다.
- **GPU/NITROS 실행 일관성**: `run_dev.sh`가 NVIDIA 런타임과 Isaac ROS 실행 환경을 표준화해 Visual SLAM 실행 안정성이 높습니다.
- **역할 분리 용이**: Isaac ROS(SLAM/카메라)는 컨테이너, 모터 드라이버(시리얼 제어)는 호스트로 분리하면 디버깅이 단순해집니다.

### 1) Isaac ROS 워크스페이스 준비 (Jetson)

```bash
export ISAAC_ROS_WS=~/workspaces/isaac_ros-dev
mkdir -p ${ISAAC_ROS_WS}/src
cd ${ISAAC_ROS_WS}/src

git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam.git
git clone https://github.com/IntelRealSense/realsense-ros.git
cd realsense-ros
git checkout 4.56.4
cd ${ISAAC_ROS_WS}/src
```

> RealSense 드라이버/udev 규칙은 5~6번 섹션 완료 상태를 전제로 합니다.
> JetPack 6.2.2 + ROS 2 Humble 기준으로 `release-3.2` 태그를 사용합니다.
> `isaac_ros_visual_slam_realsense.launch.py`는 컨테이너 안에서 `realsense2_camera` 패키지를 직접 실행하므로, `realsense-ros` 소스도 같은 워크스페이스(`isaac_ros-dev/src`)에 있어야 합니다.

### 2) Isaac ROS 환경 활성화

```bash
cd ${ISAAC_ROS_WS}
./src/isaac_ros_common/scripts/run_dev.sh
```

> 최초 1회는 Docker 이미지 빌드로 시간이 오래 걸릴 수 있습니다.
> `docker` 그룹 권한 이슈가 나면 3번 섹션의 Docker 설정을 먼저 완료합니다.

### 재접속 시 빠른 복구 루틴 (권장)

Jetson 재부팅/컨테이너 재생성 후 매번 긴 명령을 다시 입력하기 번거롭다면 아래만 실행합니다.

호스트:

```bash
# bootstrap 스크립트를 워크스페이스로 동기화(필요 시)
mkdir -p ~/workspaces/isaac_ros-dev/util
cp /home/ml406/jetson-d455-vslam-rover/util/bootstrap_isaac_container.sh \
   /home/ml406/workspaces/isaac_ros-dev/util/
chmod +x /home/ml406/workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh

cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
```

컨테이너 내부:

```bash
source /workspaces/isaac_ros-dev/util/bootstrap_isaac_container.sh
```

`/workspaces/isaac_ros-dev`가 비정상 마운트되어 `util/bootstrap_isaac_container.sh`가 안 보일 때:

```bash
# host
docker rm -f isaac_ros_dev-aarch64-container 2>/dev/null || true

cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh -d ~/workspaces/isaac_ros-dev
```

`bootstrap_isaac_container.sh`가 수행하는 작업:

- ROS 기본 환경 source
- 문제를 일으키는 `yarn` apt 저장소 제거
- 런타임/매핑/시각화 필수 패키지 설치(`librealsense2`, `rplidar_ros`, `slam_toolbox`, `nav2_map_server`, `foxglove_bridge`)
- 존재 시 워크스페이스 overlay(`install/setup.bash`) 자동 source

### 3) 컨테이너 의존성 동기화 + 빌드

```bash
cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash

# apt update를 막는 불필요 저장소(yarn) 제거
sudo rm -f /etc/apt/sources.list.d/yarn.list

# apt 인덱스 강제 새로고침 (404/Not Found 예방)
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt update
sudo apt install -y \
  ros-humble-librealsense2 \
  ros-humble-rplidar-ros \
  ros-humble-slam-toolbox \
  ros-humble-nav2-map-server \
  ros-humble-foxglove-bridge

rosdep update
rosdep install --from-paths src --ignore-src -r -y

colcon build --symlink-install --packages-up-to realsense2_camera realsense2_description isaac_ros_visual_slam
source install/setup.bash

ros2 pkg list | grep -E "^realsense2_camera$|^realsense2_camera_msgs$|^realsense2_description$|^isaac_ros_visual_slam$"
```

`rosdep install`에서 `ros-humble-librealsense2`, `ros-humble-launch-pytest`, `ros-humble-isaac-ros-*`가 404로 실패하면 아래 순서로 재시도합니다.

```bash
cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash

sudo rm -rf /var/lib/apt/lists/*
sudo apt update
rosdep update
rosdep install --from-paths src --ignore-src -r -y
```

> 위 404는 ROS/Isaac apt 저장소 동기화 시점 이슈로 발생할 수 있습니다.
> 대부분은 `apt lists` 초기화 후 재시도로 해결됩니다.

### 4) Visual SLAM 실행 (RealSense + IMU)

```bash
ros2 launch isaac_ros_visual_slam isaac_ros_visual_slam_realsense.launch.py
```

### 5) 동작 확인 (다른 터미널)

```bash
cd ${ISAAC_ROS_WS}
./src/isaac_ros_common/scripts/run_dev.sh
ros2 topic list | grep -E "visual_slam|/camera/.*/(infra|gyro|accel|imu)"
ros2 topic hz /visual_slam/tracking/odometry
ros2 topic echo /visual_slam/status --once
```

입력이 안 붙는 경우 점검:

```bash
ros2 node info /visual_slam_node
```

- 구독 토픽이 `/camera/infra1...`인데 실제 카메라 토픽이 `/camera/camera/infra1...`이면 네임스페이스 불일치입니다.
- 이 경우 13번 트러블슈팅의 `status/odometry 미발행` 항목대로 remap을 `/camera/camera/...`로 수정합니다.

TF 확인(필요 시):

```bash
ros2 run tf2_ros tf2_echo map base
```

> 로봇 프레임 이름이 `base`가 아니면 `base_link` 또는 `camera_link`로 바꿔서 확인합니다.

권장 검증 순서:

1. D455 RGB + Depth + IMU 토픽 안정화
2. Visual SLAM 실행
3. `/tf`, `/odom`, pose 안정성 확인
4. 저속 수동 주행으로 trajectory 검증

검증 포인트:

- 직진 시 드리프트
- 제자리 회전 시 pose 튐 현상
- 텍스처 부족 구간에서 tracking lost 여부
- 진동 환경에서 pose 안정성

<a id="sec-8"></a>
## 8) 모터 제어 드라이버 연동 (yc424k 포크 기준)
핵심 요약:

- 4AWD 2포트 구성에서는 `Port`/`RightPort`를 분리하고 `RightUseSeparatePort=True`로 설정합니다.
- 독립 포트(각각 별도 RS485 어댑터)면 좌우 `ID`가 같아도 동작할 수 있습니다.
- 수동 제어는 `/cmd_vel` 기반인 `teleop_twist_keyboard` 사용을 권장합니다.

상세 문서:

- [모터 드라이버 연동 상세 가이드](docs/motor-driver-integration.md)
- [USB 포트 고정 스크립트](util/setup_motor_udev.sh)

<a id="sec-9"></a>
## 9) 권장 ROS 2 노드 구조

- `realsense2_camera` : D455 센서 입력
- `visual_slam_node` : Visual SLAM pose 추정
- `motor_driver_node` : 모터 드라이버 제어
- `cmd_vel_mux/safety_node` : 속도 제한, timeout, E-stop
- `teleop or planner_node` : 상위 명령 생성

권장 토픽 흐름:

- 상위 제어: `/cmd_vel`
- 안전 계층 출력: `/cmd_vel_safe`
- 모터 제어 입력: `/cmd_vel_safe` -> `motor_driver_node`
- 상태 추정: `/tf`, `/odom`

<a id="sec-10"></a>
## 10) 원격 개발 운영 방식 (MacBook)

- SSH 접속: `ssh <user>@<jetson_ip>`
- VS Code Remote SSH 연결
- `tmux` 세션 분리 운영 예시
  - 창1: 센서 노드
  - 창2: SLAM 노드
  - 창3: 모터 제어 노드
  - 창4: 토픽 모니터링/로그

### Foxglove Bridge 설치/실행 (Jetson)

Jetson에서 SLAM을 그래픽으로 실시간 확인할 때 권장합니다.

1) Jetson에 패키지 설치:

```bash
sudo apt update
sudo apt install -y ros-humble-foxglove-bridge
```

2) 브리지 실행 (SLAM 토픽이 보이는 동일 환경에서 실행):

```bash
source /opt/ros/humble/setup.bash
ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765 address:=0.0.0.0
```

3) MacBook에서 접속:

- Foxglove Studio 실행
- Open connection -> WebSocket
- `ws://<jetson_ip>:8765` 입력

권장 확인 토픽:

- `/visual_slam/status`
- `/visual_slam/tracking/odometry`
- `/visual_slam/tracking/slam_path`
- `/visual_slam/vis/landmarks_cloud`
- `/tf`

<a id="sec-11"></a>
## 11) 단계별 Bring-up 권장 순서

1. Jetson OS/네트워크 안정화
2. D455 단독 테스트 (영상+IMU)
3. RealSense ROS 토픽 안정화
4. Visual SLAM pose 안정화
5. 모터 드라이버 단독 테스트
6. `cmd_vel -> 모터` 연동
7. 저속 폐루프 주행 테스트
8. rosbag 기록 기반 튜닝

<a id="sec-12"></a>
## 12) 초기 점검 체크리스트

- [ ] D455가 USB 3.x로 안정 인식됨
- [ ] IMU 토픽 주기가 안정적임
- [ ] Visual SLAM pose가 저속 주행에서 유지됨
- [ ] `cmd_vel` timeout 시 모터 정지 동작 확인
- [ ] E-stop 입력 시 즉시 정지 확인
- [ ] 전원 강하 시 재시작/복구 절차 확인

<a id="sec-13"></a>
## 13) 트러블슈팅 메모
상세 트러블슈팅 문서:

- [트러블슈팅 모음](docs/troubleshooting.md)

### 최근 해결된 이슈 요약 (실사용 기준)

| 증상 | 핵심 원인 | 해결 |
|---|---|---|
| `LFS files are missing...` (`run_dev.sh`) | Git LFS 객체 누락 | `git-lfs` 설치 후 `isaac_ros_common`, `isaac_ros_visual_slam`에서 `git lfs pull` |
| `groups: 'ml406': no such user` + docker 그룹 경고 (컨테이너 내부) | `run_dev.sh`를 컨테이너 안에서 다시 실행 | `run_dev.sh`는 **호스트에서만** 실행, 컨테이너 내부에서는 `source`만 수행 |
| `Package 'realsense2_camera' not found` (host `~/ros2_ws`) | RealSense 패키지가 host 워크스페이스에 없음(컨테이너에만 존재) | RealSense/Isaac ROS는 Docker에서 실행하거나, host에 `realsense-ros` 별도 빌드 |
| `Package 'rplidar_ros' not found` (컨테이너) | 해당 ROS 패키지 미설치 | 컨테이너 내부에서 `ros-humble-rplidar-ros` 설치 |
| `apt update` 실패 + `NO_PUBKEY 62D54FD4003F6525` | Yarn 저장소 서명키 문제 | `sudo rm -f /etc/apt/sources.list.d/yarn.list` 후 `sudo apt update` |
| `xioctl(VIDIOC_QBUF) ... No such device` | D455 USB 연결 끊김/리셋 또는 중복 점유 | 케이블/포트 점검, 카메라 노드 단일 실행 유지, 노드 재기동 |

### Docker 컨테이너 내부 추가 설치 패키지 정리

아래는 실제 bring-up 과정에서 컨테이너 안(`admin@ubuntu:/workspaces/isaac_ros-dev`)에 추가 설치한 패키지입니다.

```bash
ros-humble-rplidar-ros
ros-humble-slam-toolbox
ros-humble-nav2-map-server
```

필요 시(컨테이너 내부) 재설치:

```bash
sudo apt update
sudo apt install -y \
  ros-humble-rplidar-ros \
  ros-humble-slam-toolbox \
  ros-humble-nav2-map-server
```

설치 확인:

```bash
ros2 pkg list | grep -E "rplidar_ros|slam_toolbox|nav2_map_server"
```

주의:

- 컨테이너를 새로 생성하면(이미지/컨테이너 교체) 수동 설치 패키지가 사라질 수 있습니다.
- 재현성을 위해 필요한 패키지는 문서에 남기고, 동일 명령으로 다시 설치 가능한 형태로 관리합니다.

<a id="sec-14"></a>
## 14) 운영 원칙 요약

- **처음 목표는 "맵"보다 "안정적인 pose"**
- **SLAM 안정화 후 모터 제어 통합**
- **항상 저속/단계적 검증**
- **로그(rosbag) 기반으로 튜닝**

<a id="sec-15"></a>
## 15) Nav2 기반 자율주행 실행

상세 문서:

- [Nav2 운영 가이드 (모드 분리)](docs/nav2-autonomous-driving.md)
- [Nav2 Host Native 모드 (Docker 없이)](docs/nav2-host-native-mode.md)
- [Nav2 준비 - 맵 생성 모드](docs/nav2-mapping-mode.md)
- [Nav2 자율주행 모드](docs/nav2-autonomous-mode.md)

### 맵 생성 모드 실행 팁 (slam_toolbox 드롭 메시지 대응)

`slam_toolbox` 실행 시 아래 로그가 반복되면 매핑 품질이 떨어질 수 있습니다.

- `discarding message because the queue is full`
- `the timestamp on the message is earlier than all the data in the transform cache`

아래 순서로 실행하면 Jetson에서 드롭 빈도를 줄이기 쉽습니다.

```bash
# 1) md_controller (Host)
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

```bash
# 2) RPLIDAR S3M1 (Docker)
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

```bash
# 3) base_link -> laser TF (필요 시)
ros2 run tf2_ros static_transform_publisher \
  0.10 0.0 0.18 0.0 0.0 0.0 base_link laser
```

```bash
# 4) slam_toolbox (Docker)
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

확인 명령:

```bash
ros2 topic hz /scan
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo base_link laser
ros2 topic echo /map --once --qos-durability transient_local
```

주의:

- 줄바꿈용 `\` 뒤에 공백이 들어가면 인자 파싱이 깨질 수 있습니다.  
  예: `-p tf_buffer_duration:=120.0 \ ` (잘못된 예)
