# 모터 드라이버 연동 가이드

이 문서는 Jetson + D455 + md_motor_driver_ros2(2포트 4AWD) 기준의 모터 연동 상세 절차입니다.

## 모터 제어 드라이버 연동 (yc424k 포크 기준)

사용 드라이버:

- `https://github.com/yc424k/md_motor_driver_ros2`
- 본 가이드 기준 수정사항:
  - 4AWD에서 좌(A)/우(B) 드라이버 분리 제어 파라미터 추가
  - `cmd_vel` timeout 기반 자동 정지
  - `left_sign`, `right_sign` 방향 부호 보정 파라미터 지원

### 적용 전 조건 (권장)

- Visual SLAM 상태가 이미 안정적일 것
  - `/visual_slam/status`에서 `vo_state: 1` 확인
  - `/visual_slam/tracking/odometry`가 안정적으로 발행
- 모터 테스트는 반드시 **바퀴를 띄운 무부하 상태**에서 시작
- E-stop(비상정지) 하드웨어가 준비된 상태에서 진행

### 소스 가져오기 (Jetson Native ROS 워크스페이스)

```bash
cd ~/ros2_ws/src
git clone https://github.com/yc424k/md_motor_driver_ros2.git
```

### 의존성: `serial` 패키지 설치

`md_controller`는 `serial` 라이브러리 패키지를 사용합니다. ROS 2 Humble에서 바로 apt 설치가 안 되는 경우가 있어, 아래처럼 소스 빌드로 준비합니다.

```bash
cd ~/ros2_ws/src
[ -d serial-ros2 ] || git clone https://github.com/RoverRobotics-forks/serial-ros2.git

cd ~/ros2_ws
source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-up-to serial
source install/setup.bash
```

### 빌드 (`md_controller`, `md_teleop`)

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-up-to md_controller md_teleop
source install/setup.bash
```

패키지 확인:

```bash
ros2 pkg list | grep -E "^md_controller$|^md_teleop$|^serial$"
```

### 드라이버 파라미터 확인 (필수)

기본 파라미터는 아래 launch 파일에 정의되어 있습니다.

공통:

- `Port` (기본 `/dev/ttyMotor`)
- `Baudrate` (기본 `57600`)
- `wheel_radius`, `wheel_base`
- `cmd_timeout_ms`, `max_driver_rpm`

왼쪽(A) 드라이버:

- `ID`, `MDT`, `GearRatio`, `poles`, `left_sign`

오른쪽(B) 드라이버:

- `right_enabled`, `RightID`, `RightMDT`, `RightGearRatio`, `right_sign`
- `RightUseSeparatePort`, `RightPort`, `RightBaudrate`

파일 경로:

- `~/ros2_ws/src/md_motor_driver_ros2/md_controller/launch/md_controller.launch.py`

실제 하드웨어에 맞게 아래 파일을 수정 후 테스트합니다.

```bash
vim ~/ros2_ws/src/md_motor_driver_ros2/md_controller/launch/md_controller.launch.py
```

포트 확인:

```bash
ls -l /dev/ttyMotor /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

- `/dev/ttyMotor`가 없으면 launch 파라미터 `Port`를 실제 장치명(예: `/dev/ttyUSB0`)으로 변경합니다.
- 좌/우가 같은 RS485 버스면 `Port` 1개 + `ID/RightID` 분리로 사용합니다.
- 좌/우가 서로 다른 물리 포트면 `RightUseSeparatePort:=True`로 설정하고 `RightPort`를 별도로 지정합니다.
- 좌/우가 **서로 다른 물리 포트(각각 독립 RS485 어댑터)**이면 `ID`와 `RightID`가 동일해도 동작할 수 있습니다(예: 둘 다 `1`).
- 좌/우가 **같은 물리 버스**면 `ID`와 `RightID`는 반드시 서로 달라야 합니다.

2포트 예시:

```python
"Port": "/dev/ttyUSB0",            # Left(A)
"RightUseSeparatePort": True,
"RightPort": "/dev/ttyUSB1",       # Right(B)
"RightBaudrate": 57600,
```

### 재부팅 후 모터 USB 포트 고정 (udev 규칙)

`/dev/ttyUSB0`, `/dev/ttyUSB1`은 재부팅/재연결 시 순서가 바뀔 수 있습니다.  
아래처럼 **고정 심볼릭 링크**(`/dev/ttyMotorLeft`, `/dev/ttyMotorRight`)를 만들어 사용하면 안정적입니다.

1) 자동화 스크립트 사용(권장):

```bash
cd <repo_root>

# 연결된 후보 장치 식별자 확인
./util/setup_motor_udev.sh --list

# 실제 좌/우 장치 지정 후 udev 규칙 생성 + 적용
./util/setup_motor_udev.sh --left /dev/ttyUSB0 --right /dev/ttyUSB1

# 결과 확인
ls -l /dev/ttyMotorLeft /dev/ttyMotorRight
```

> 스크립트는 `ID_SERIAL_SHORT`가 있으면 해당 값을 우선 사용하고, 없으면 `ID_PATH`로 자동 fallback 합니다.

2) 수동 설정(필요 시) - 장치 식별자 확인:

```bash
for d in /dev/ttyUSB* /dev/ttyACM*; do
  [ -e "$d" ] || continue
  echo "=== $d ==="
  udevadm info -q property -n "$d" | grep -E "ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT|ID_PATH="
done
```

3) udev 규칙 생성(값은 실제 장치 값으로 교체):

```bash
sudo tee /etc/udev/rules.d/99-robot-motor.rules >/dev/null <<'EOF'
# Left motor adapter
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="XXXX", ENV{ID_MODEL_ID}=="YYYY", ENV{ID_SERIAL_SHORT}=="LEFT_SERIAL", SYMLINK+="ttyMotorLeft", GROUP="dialout", MODE="0660"

# Right motor adapter
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="XXXX", ENV{ID_MODEL_ID}=="YYYY", ENV{ID_SERIAL_SHORT}=="RIGHT_SERIAL", SYMLINK+="ttyMotorRight", GROUP="dialout", MODE="0660"
EOF
```

`ID_SERIAL_SHORT`가 없는 어댑터는 `ID_PATH` 기준으로 규칙을 작성합니다:

```bash
SUBSYSTEM=="tty", ENV{ID_PATH}=="platform-3610000.usb-usb-0:1.3:1.0", SYMLINK+="ttyMotorLeft", GROUP="dialout", MODE="0660"
SUBSYSTEM=="tty", ENV{ID_PATH}=="platform-3610000.usb-usb-0:1.4:1.0", SYMLINK+="ttyMotorRight", GROUP="dialout", MODE="0660"
```

4) 규칙 적용:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
# 또는 USB 재연결
```

5) 링크 확인:

```bash
ls -l /dev/ttyMotorLeft /dev/ttyMotorRight
```

6) `md_controller` 파라미터 고정:

```python
"Port": "/dev/ttyMotorLeft",
"RightUseSeparatePort": True,
"RightPort": "/dev/ttyMotorRight",
```

### 1단계: 모터 드라이버 단독 bring-up

```bash
source ~/ros2_ws/install/setup.bash
ros2 launch md_controller md_controller.launch.py use_rviz:=False
```

확인:

```bash
ros2 node list | grep md_controller
```

### 2단계: `/cmd_vel` 저속 수동 테스트

별도 터미널에서:

```bash
sudo apt update
sudo apt install -y ros-humble-teleop-twist-keyboard

source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

> `md_teleop_key_node`는 `/cmd_rpm`을 발행하고, `md_controller`는 `/cmd_vel`을 구독하므로 현재 구조에서는 `teleop_twist_keyboard` 사용을 권장합니다.

또는 단발성 명령 테스트:

```bash
# 아주 작은 직진 명령 (1초)
ros2 topic pub -1 /cmd_vel geometry_msgs/msg/Twist \
"{linear: {x: 0.05, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}"

# 아주 작은 회전 명령 (1초)
ros2 topic pub -1 /cmd_vel geometry_msgs/msg/Twist \
"{linear: {x: 0.0, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.2}}"
```

방향/기어비 보정:

- 직진 명령에서 한쪽이 역방향이면 `left_sign` 또는 `right_sign`를 `-1`로 조정
- 좌/우 드라이버 감속비가 다르면 `GearRatio`와 `RightGearRatio`를 각각 맞춤
- 오른쪽 드라이버를 비활성화하려면 `right_enabled:=False`
- 직진에서 바퀴가 서로 반대로 돌고, 회전에서 같은 방향으로 돌면 `left_sign`/`right_sign` 부호가 서로 반대로 설정된 상태입니다. 이 경우 두 값을 같은 부호(`1,1` 또는 `-1,-1`)로 맞춥니다.

### 3단계: Visual SLAM과 결합

권장 순서:

1. Visual SLAM 세션 유지 (`/visual_slam/status`, `/visual_slam/tracking/odometry` 정상)
2. 모터 드라이버 세션 별도 실행
3. 상위 제어 입력(`/cmd_vel`)을 저속으로만 인가
4. 직진/회전/정지 반복 테스트 후 속도 상향

### 안전 설정 권장 (연동 전)

- `cmd_vel` 입력 주기 제한(타임아웃 포함)
- 가속/감속 제한(slew rate limit)
- 비상정지(E-stop) 우선순위 최상위
- 전원 불안정 대비 watchdog 적용
