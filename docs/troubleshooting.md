# 트러블슈팅 모음

Jetson Orin Nano + D455 + Isaac ROS + md_controller 구성에서 실제로 자주 발생한 오류와 해결 절차를 정리했습니다.

## 트러블슈팅 메모

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

### `W: GPG error: https://dl.yarnpkg.com/debian ... NO_PUBKEY 62D54FD4003F6525` 경고

원인:

- 시스템에 Yarn APT 저장소(`dl.yarnpkg.com`)가 등록되어 있는데, 해당 저장소 서명키가 키링에 없거나 깨진 상태입니다.
- 이 경우 `apt update` 시 서명 검증이 실패하며 GPG 경고가 출력됩니다.

해결 1) Yarn을 사용하지 않는 경우(권장: 불필요 저장소 제거):

```bash
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt update
```

해결 2) Yarn을 계속 사용하는 경우(키 재등록):

```bash
sudo apt update
sudo apt install -y curl gnupg ca-certificates

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
| sudo gpg --dearmor -o /etc/apt/keyrings/yarn.gpg

echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" \
| sudo tee /etc/apt/sources.list.d/yarn.list >/dev/null

sudo apt update
```

확인:

```bash
sudo apt update
```

- 같은 `NO_PUBKEY 62D54FD4003F6525` 경고가 사라지면 정상입니다.

### `User ... is not a member of the 'docker' group` 에러

Isaac ROS `run_dev.sh` 실행 시 발생하는 권한 에러입니다.

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

그룹 반영 확인:

```bash
id -nG | grep docker
docker ps
```

### `LFS files are missing. Please re-clone repos after installing git-lfs.` 에러

증상 예시:

- `./src/isaac_ros_common/scripts/run_dev.sh` 실행 직후 아래 메시지 출력
- `LFS files are missing. Please re-clone repos after installing git-lfs.`
- `isaac_ros_test_cmake/resources/dummy_bag/...` 같은 파일 경로가 함께 출력됨

원인:

- 이 에러는 Docker 실행 실패가 아니라, `run_dev.sh`의 **사전 검사(pre-check)** 단계에서
  Git LFS 객체가 누락되어 중단된 상태입니다.
- 즉 컨테이너에 들어가지도 못한 상태이며, 소스 저장소가 LFS 포인터 파일만 가진 경우에 발생합니다.

해결:

```bash
sudo apt update
sudo apt install -y git-lfs
git lfs install

cd ~/workspaces/isaac_ros-dev/src/isaac_ros_common
git lfs pull

cd ~/workspaces/isaac_ros-dev/src/isaac_ros_visual_slam
git lfs pull

cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
```

여전히 동일하면(권장: 재클론):

```bash
cd ~/workspaces
mv isaac_ros-dev isaac_ros-dev.backup.$(date +%F-%H%M)

mkdir -p isaac_ros-dev/src
cd isaac_ros-dev/src
git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam.git
git clone https://github.com/IntelRealSense/realsense-ros.git

cd ~/workspaces/isaac_ros-dev
./src/isaac_ros_common/scripts/run_dev.sh
```

### `Unable to open port` / `PortNotOpenedException Serial::write failed` (md_controller)

증상 예시:

- `Unable to open port`
- `PortNotOpenedException Serial::write failed.`

원인(대표):

- 사용자 계정이 `dialout` 그룹에 없어 `/dev/ttyUSB*` 권한이 없음
- launch 파라미터 `Port`/`RightPort`가 실제 장치와 불일치

진단:

```bash
id -nG | grep -w dialout || echo "dialout 그룹 없음"
ls -l /dev/ttyMotorLeft /dev/ttyMotorRight /dev/ttyUSB* /dev/ttyACM* 2>/dev/null

PARAM_FILE=$(ls -t /tmp/launch_params_* 2>/dev/null | head -n1)
grep -nE "Port|RightUseSeparatePort|RightPort" "$PARAM_FILE"
```

해결:

```bash
sudo usermod -aG dialout $USER
# SSH 재접속 또는
newgrp dialout
```

그리고 2포트 구성이면:

- `RightUseSeparatePort: True`
- `Port: /dev/ttyMotorLeft`
- `RightPort: /dev/ttyMotorRight`

### `MOTOR INIT END` 이후 `ERROR (1)` 반복 + `check error`

증상 예시:

- `ERROR (1)`가 연속 출력
- 이후 `check error` 출력

원인:

- 시리얼 포트는 열렸지만, 수신 패킷 파싱이 계속 실패하는 상태
- 주로 드라이버 `ID`/`Baudrate`/배선(좌우 포트 매핑) 불일치에서 발생

해결 절차:

```bash
# Left 단독
ros2 run md_controller md_controller --ros-args \
  -p Port:=/dev/ttyMotorLeft -p Baudrate:=57600 -p ID:=1 \
  -p MDT:=183 -p MDUI:=184 -p right_enabled:=false \
  -p wheel_radius:=0.103 -p wheel_base:=0.4

# Right 단독 (ID는 하드웨어 실제값으로 확인)
ros2 run md_controller md_controller --ros-args \
  -p Port:=/dev/ttyMotorRight -p Baudrate:=57600 -p ID:=1 \
  -p MDT:=183 -p MDUI:=184 -p right_enabled:=false \
  -p wheel_radius:=0.103 -p wheel_base:=0.4
```

실전 메모:

- 좌/우가 독립 포트(분리 RS485 어댑터)면 좌우 `ID`가 같아도 됩니다(예: 둘 다 `1`).
- 같은 버스 공유면 `ID`는 반드시 다르게 설정해야 합니다.

### `md_teleop_key_node` 실행 시 `No module named 'getkey'` 또는 키 입력해도 바퀴 무반응

원인:

- `md_teleop_key_node`는 Python `getkey` 의존성이 필요함
- 더 중요한 점: `md_teleop_key_node`는 `/cmd_rpm`을 발행하고,
  현재 `md_controller`는 `/cmd_vel`만 구독하므로 기본 구성에서는 동작이 연결되지 않음

권장 해결(현재 구성 기준):

```bash
sudo apt update
sudo apt install -y ros-humble-teleop-twist-keyboard

source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

참고(필요 시에만):

```bash
python3 -m pip install --user getkey
```

### `failed to inject CDI devices ... nvidia.com/pva=all` 에러 (Orin Nano)

증상 예시:

- `OCI runtime create failed`
- `failed to inject CDI devices`
- `unresolvable CDI devices nvidia.com/pva=all`

원인:

- `run_dev.sh`(aarch64 경로)가 기본값으로 `NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all`를 넣습니다.
- Jetson Orin Nano 환경에서는 PVA 디바이스를 직접 사용하지 않는 구성인 경우가 많아, `pva=all` 요청이 컨테이너 시작 실패를 유발할 수 있습니다.

해결:

```bash
cd ~/workspaces/isaac_ros-dev

# PVA 요청 제거 (gpu만 사용)
sed -i 's|nvidia.com/gpu=all,nvidia.com/pva=all|nvidia.com/gpu=all|g' \
  src/isaac_ros_common/scripts/run_dev.sh

# 변경 확인
grep -n "NVIDIA_VISIBLE_DEVICES" src/isaac_ros_common/scripts/run_dev.sh

# 컨테이너 재실행
./src/isaac_ros_common/scripts/run_dev.sh
```

왜 이 방법이 필요한가:

- 현재 에러는 Visual SLAM 로직 문제가 아니라 **컨테이너 런타임의 디바이스 주입 단계**에서 실패하는 문제입니다.
- 따라서 `NVIDIA_VISIBLE_DEVICES`에서 사용 불가한 `pva` 항목을 제거하면, Docker가 GPU 디바이스만으로 정상 기동할 수 있습니다.

주의:

- `isaac_ros_common` 업데이트(`git pull`) 후에는 `run_dev.sh`가 원복될 수 있으므로 같은 수정을 다시 적용해야 합니다.

### `package 'realsense2_camera' not found` 에러 (Isaac ROS 컨테이너)

증상 예시:

- `ros2 launch isaac_ros_visual_slam isaac_ros_visual_slam_realsense.launch.py` 실행 시
- `package 'realsense2_camera' not found`

원인:

- `isaac_ros_visual_slam_realsense.launch.py`는 `realsense2_camera_node`를 함께 실행합니다.
- 컨테이너 환경(`/workspaces/isaac_ros-dev/install`, `/opt/ros/humble`)에 `realsense2_camera` 패키지가 없으면 launch가 즉시 종료됩니다.
- 호스트의 다른 워크스페이스(`~/ros2_ws`)에만 빌드되어 있으면 컨테이너에서는 보이지 않습니다.

해결:

```bash
cd /workspaces/isaac_ros-dev/src
[ -d realsense-ros ] || git clone https://github.com/IntelRealSense/realsense-ros.git
cd realsense-ros
git fetch --tags
git checkout 4.56.4

cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash
rosdep update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-up-to realsense2_camera realsense2_description isaac_ros_visual_slam
source install/setup.bash

ros2 pkg list | grep -E "^realsense2_camera$|^realsense2_camera_msgs$|^realsense2_description$"
```

### `Failed to find ... install/realsense2_camera_msgs/.../package.sh` 에러

원인:

- `colcon build --packages-select ...`로 `realsense2_camera`만 선택 빌드하면,
  의존 패키지 `realsense2_camera_msgs`가 누락되어 발생할 수 있습니다.

해결:

```bash
cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash

rm -rf build/realsense2_* install/realsense2_*
colcon build --symlink-install --packages-up-to realsense2_camera realsense2_description isaac_ros_visual_slam
source install/setup.bash
```

대안(선택 빌드 유지 시):

```bash
colcon build --symlink-install --packages-select \
  realsense2_camera_msgs realsense2_camera realsense2_description isaac_ros_visual_slam
```

### `The message type 'isaac_ros_visual_slam_interfaces/msg/VisualSlamStatus' is invalid`

원인:

- 컨테이너 셸에서 워크스페이스 overlay(`install/setup.bash`)가 로드되지 않은 상태입니다.
- `isaac_ros_visual_slam_interfaces` 타입을 찾지 못해 `ros2 topic echo /visual_slam/status --once`가 실패합니다.

해결:

```bash
source /opt/ros/humble/setup.bash
source /workspaces/isaac_ros-dev/install/setup.bash
ros2 interface show isaac_ros_visual_slam_interfaces/msg/VisualSlamStatus
```

- 위 명령에서 메시지 정의가 출력되면 타입 인식은 정상입니다.

### `/visual_slam/status --once`가 대기만 하거나 `/visual_slam/tracking/odometry`가 미발행

원인(대표):

- `visual_slam_node` 구독 입력과 실제 RealSense 토픽 네임스페이스가 다릅니다.
- 예: 구독은 `/camera/infra1...`, 실제 발행은 `/camera/camera/infra1...`

진단:

```bash
ros2 node info /visual_slam_node
ros2 topic list | grep -E "/camera/.*/(infra1|infra2|imu)"
```

해결(launch remap을 `/camera/camera/...`로 수정):

```bash
FILE=/workspaces/isaac_ros-dev/src/isaac_ros_visual_slam/isaac_ros_visual_slam/launch/isaac_ros_visual_slam_realsense.launch.py

sed -i "s|'camera/infra1/image_rect_raw'|'camera/camera/infra1/image_rect_raw'|g" $FILE
sed -i "s|'camera/infra1/camera_info'|'camera/camera/infra1/camera_info'|g" $FILE
sed -i "s|'camera/infra2/image_rect_raw'|'camera/camera/infra2/image_rect_raw'|g" $FILE
sed -i "s|'camera/infra2/camera_info'|'camera/camera/infra2/camera_info'|g" $FILE
sed -i "s|'camera/imu'|'camera/camera/imu'|g" $FILE

cd /workspaces/isaac_ros-dev
source /opt/ros/humble/setup.bash
colcon build --symlink-install --packages-select isaac_ros_visual_slam
source install/setup.bash
```

검증:

```bash
ros2 node info /visual_slam_node | grep -E "/camera/camera/(infra1|infra2|imu)" -n
ros2 topic echo /visual_slam/status --once
ros2 topic hz /visual_slam/tracking/odometry
```

- 정상 기준: `vo_state: 1` 출력, odometry 약 30Hz.

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
