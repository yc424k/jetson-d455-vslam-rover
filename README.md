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

쉘 환경 등록:

```bash
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

왜 필요한가:

- `source /opt/ros/humble/setup.bash`는 ROS 2 기본 환경변수(`PATH`, `AMENT_PREFIX_PATH` 등)를 로드합니다.
- 이 설정이 없으면 `ros2` 명령이 인식되지 않거나, ROS 패키지 탐색이 실패할 수 있습니다.
- `~/.bashrc`에 넣어두면 새 터미널을 열 때마다 자동으로 ROS 2 환경이 적용됩니다.

워크스페이스 환경 등록:

```bash
echo "source ~/ros2_ws/install/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

왜 필요한가:

- `~/ros2_ws/install/setup.bash`는 내 워크스페이스에서 빌드한 패키지를 ROS가 찾을 수 있게 합니다(overlay).
- 이 설정이 있어야 `ros2 run`/`ros2 launch`에서 직접 만든 패키지와 로컬 수정본이 반영됩니다.
- 적용 순서는 `ROS 기본 환경 -> 워크스페이스 환경`이 맞습니다.
- `~/ros2_ws/install/setup.bash`는 `colcon build` 이후 생성되므로, 첫 빌드 전에는 파일이 없을 수 있습니다.

> 참고: 환경에 따라 의존 패키지/저장소 추가가 필요할 수 있습니다.

---

## 5) RealSense(D455) 연결 및 기본 확인

### 장치 인식 확인

```bash
lsusb | grep -i realsense
```

### udev 규칙 / 권한 (필요 시)

```bash
sudo apt install -y librealsense2-utils
realsense-viewer
```

확인 포인트:

- RGB 스트림 정상
- Depth 스트림 정상
- IMU (gyro/accel) 출력 정상
- 프레임 드랍/끊김 여부

---

## 6) ROS 2 RealSense 드라이버 준비

```bash
cd ~/ros2_ws/src
git clone https://github.com/IntelRealSense/realsense-ros.git -b ros2-master
```

의존성 설치 및 빌드:

```bash
cd ~/ros2_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

기본 실행 예시:

```bash
ros2 launch realsense2_camera rs_launch.py enable_gyro:=true enable_accel:=true
```

토픽 확인:

```bash
ros2 topic list | grep camera
ros2 topic hz /camera/gyro/sample
ros2 topic hz /camera/accel/sample
```

---

## 7) Isaac ROS Visual SLAM 적용 순서

권장 순서:

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

---

## 14) 운영 원칙 요약

- **처음 목표는 "맵"보다 "안정적인 pose"**
- **SLAM 안정화 후 모터 제어 통합**
- **항상 저속/단계적 검증**
- **로그(rosbag) 기반으로 튜닝**
