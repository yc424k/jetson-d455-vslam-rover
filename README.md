# Jetson Orin Nano + Intel RealSense D455 초기 설정 가이드

이 문서는 **Jetson Orin Nano 1대**에서 아래를 모두 수행하는 구성을 기준으로 작성되었습니다.

- 카메라 입력 (D455)
- Visual SLAM (Isaac ROS Visual SLAM)
- 로봇 제어 (md_motor_driver_ros2)
- 원격 개발 (MacBook SSH)

---

## 1) 목표 아키텍처

- **Jetson Orin Nano (JetPack 6.2.2)**
  - ROS 2 Humble
  - RealSense ROS 드라이버
  - Isaac ROS Visual SLAM
  - 모터 제어 노드 (`md_motor_driver_ros2`)
- **Intel RealSense D455**
  - Stereo Depth + RGB + IMU
- **MacBook**
  - SSH / VS Code Remote SSH / 로그 확인 / 시각화

---

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

---

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

### 작업 디렉터리 구성

```bash
mkdir -p ~/workspace ~/ros2_ws/src
```

---

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

---

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

---

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

---

## 7) Isaac ROS Visual SLAM 적용 순서

아래는 **Isaac ROS 컨테이너 기반(권장)** 명령 순서입니다.

### 1) Isaac ROS 워크스페이스 준비 (Jetson)

```bash
export ISAAC_ROS_WS=~/workspaces/isaac_ros-dev
mkdir -p ${ISAAC_ROS_WS}/src
cd ${ISAAC_ROS_WS}/src

git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam.git
```

> RealSense 드라이버/udev 규칙은 5~6번 섹션 완료 상태를 전제로 합니다.
> JetPack 6.2.2 + ROS 2 Humble 기준으로 `release-3.2` 태그를 사용합니다.

### 2) Isaac ROS 환경 활성화

```bash
cd ${ISAAC_ROS_WS}
./src/isaac_ros_common/scripts/run_dev.sh
```

> 최초 1회는 Docker 이미지 빌드로 시간이 오래 걸릴 수 있습니다.

### 3) 컨테이너 내부에서 빌드

```bash
cd /workspaces/isaac_ros-dev
rosdep update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

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

---

## 8) 모터 제어 드라이버 연동 (사용 예정 저장소)

사용 드라이버:

- `https://github.com/Lee-seokgwon/md_motor_driver_ros2`

### 소스 가져오기

```bash
cd ~/ros2_ws/src
git clone https://github.com/Lee-seokgwon/md_motor_driver_ros2.git
```

### 빌드

```bash
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

### 연동 시 권장 사항

- `cmd_vel` 입력 주기 제한(타임아웃 포함)
- 가속/감속 제한(slew rate limit)
- 비상정지(E-stop) 우선순위 최상위
- 전원 불안정 대비 watchdog 적용

---

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

---

## 10) 원격 개발 운영 방식 (MacBook)

- SSH 접속: `ssh <user>@<jetson_ip>`
- VS Code Remote SSH 연결
- `tmux` 세션 분리 운영 예시
  - 창1: 센서 노드
  - 창2: SLAM 노드
  - 창3: 모터 제어 노드
  - 창4: 토픽 모니터링/로그

기본 모니터링 명령:

```bash
ros2 node list
ros2 topic list
ros2 topic hz /cmd_vel
ros2 topic echo /odom --once
```

---

## 11) 단계별 Bring-up 권장 순서

1. Jetson OS/네트워크 안정화
2. D455 단독 테스트 (영상+IMU)
3. RealSense ROS 토픽 안정화
4. Visual SLAM pose 안정화
5. 모터 드라이버 단독 테스트
6. `cmd_vel -> 모터` 연동
7. 저속 폐루프 주행 테스트
8. rosbag 기록 기반 튜닝

---

## 12) 초기 점검 체크리스트

- [ ] D455가 USB 3.x로 안정 인식됨
- [ ] IMU 토픽 주기가 안정적임
- [ ] Visual SLAM pose가 저속 주행에서 유지됨
- [ ] `cmd_vel` timeout 시 모터 정지 동작 확인
- [ ] E-stop 입력 시 즉시 정지 확인
- [ ] 전원 강하 시 재시작/복구 절차 확인

---

## 13) 트러블슈팅 메모

- USB 대역폭 부족 시 해상도/프레임레이트를 우선 낮춰 확인
- 진동이 큰 경우 카메라 마운트 강성부터 개선
- 시각 특징이 부족한 환경(단색/반사/암부)에서는 tracking 성능 저하 가능
- 모터 제어는 반드시 저속부터 시작, 최대 속도 테스트는 마지막 단계에 수행

### `Unable to locate package python3-colcon-common-extensions / python3-vcstool` 에러

JetPack 6.2.2(ubuntu 22.04/jammy) 환경에서는 `universe`만 추가한 상태로는
해당 패키지가 보이지 않을 수 있습니다. 아래처럼 ROS 2 apt 소스를 먼저 등록한 뒤 설치합니다.

```bash
sudo apt update && sudo apt install -y curl

export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')

curl -L -o /tmp/ros2-apt-source.deb \
"https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"

sudo dpkg -i /tmp/ros2-apt-source.deb
sudo apt update

sudo apt install -y python3-colcon-common-extensions python3-vcstool
```

### `Unable to locate package librealsense2-utils` 에러

`librealsense2-utils`는 기본 Ubuntu 저장소가 아니라 RealSense apt 저장소가 필요할 수 있습니다.
아래 순서로 저장소를 등록한 뒤 다시 설치합니다.

```bash
sudo apt update
sudo apt install -y curl gnupg lsb-release ca-certificates

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://librealsense.intel.com/Debian/librealsense.pgp \
| sudo gpg --dearmor -o /etc/apt/keyrings/librealsense.pgp

echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/librealsense.pgp] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" \
| sudo tee /etc/apt/sources.list.d/librealsense.list >/dev/null

sudo apt update
sudo apt install -y librealsense2-utils
```

SSH 환경에서는 `realsense-viewer` 대신 아래 명령으로 장치 인식을 확인합니다.

```bash
rs-enumerate-devices
```

### `rosdep: command not found` 에러

```bash
sudo apt update
sudo apt install -y python3-rosdep || sudo apt install -y python3-rosdep2

if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi

rosdep update
```

### `No HID info provided, IMU is disabled` 에러

의미:

- 카메라는 인식됐지만 IMU(HID) 정보를 가져오지 못해 `gyro/accel` 토픽이 비활성화된 상태입니다.

점검:

```bash
ros2 topic list | grep -E "/camera/.*/(gyro|accel|imu)"
modprobe hid_sensor_accel_3d
modprobe hid_sensor_gyro_3d
```

`modprobe`에서 `Module ... not found`가 나오면 6번의 `IMU 커널 활성화` 절차대로 커널 옵션을 켜고 재빌드합니다.

### `Could not find ... realsense2 ... requested version "2.56.6"` 에러

에러 의미:

- `realsense2_camera` 패키지가 CMake에서 `realsense2`를 찾을 때, 현재 시스템 버전보다 높은 버전을 요구하고 있다는 뜻입니다.
- 예시 메시지:
  - `requested version "2.56.6"`
  - `found ... version: 2.56.4`

원인(왜 발생하나):

- `realsense-ros`는 `ros2-master`(2.56.6 요구)인데, 시스템 `librealsense2`는 `2.56.4`/`2.56.5`인 버전 불일치입니다.
- 즉, **GitHub 최신 브랜치 기준 의존성**과 **Jetson에 실제 설치된 SDK 버전**이 어긋난 상태입니다.

해결(권장):

```bash
cd ~/ros2_ws/src/realsense-ros
git fetch --tags
git checkout 4.56.4

cd ~/ros2_ws
rm -rf build/realsense2_camera build/realsense2_description
rm -rf install/realsense2_camera install/realsense2_description

source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-select realsense2_camera realsense2_description
```

왜 이 방법이 해결되는가:

- `git checkout 4.56.4`로 드라이버 쪽 요구 버전을 현재 시스템 SDK 범위(2.56.x)에 맞춥니다.
- 기존 `build/`, `install/`의 재사용 캐시를 삭제해, 이전 실패 설정이 남아있지 않게 합니다.
- 이후 선택 패키지 재빌드(`--packages-select`)로 문제 구간만 빠르게 검증할 수 있습니다.

재발 방지 체크:

```bash
# 1) 시스템 SDK 버전 확인
dpkg -s librealsense2 | grep Version

# 2) 드라이버 태그 확인
cd ~/ros2_ws/src/realsense-ros
git describe --tags --always
```

- 원칙: `librealsense2` 버전과 `realsense-ros` 태그를 맞춘다.
- 팀 문서/스크립트에서 `ros2-master` 고정 대신 태그 고정을 사용한다.

---

## 14) 운영 원칙 요약

- **처음 목표는 "맵"보다 "안정적인 pose"**
- **SLAM 안정화 후 모터 제어 통합**
- **항상 저속/단계적 검증**
- **로그(rosbag) 기반으로 튜닝**
