# Nav2 운영 가이드 (모드 분리)

기존 Nav2 절차를 혼동 없이 쓰기 위해 문서를 모드별로 분리했습니다.

## 먼저 이해할 점

- `2D 정적 맵 파일(<map>.yaml, <map>.pgm)`은 미리 주어지는 파일이 아니라,
  **맵 생성 모드에서 직접 만들어 저장한 결과물**입니다.

## 1) 맵 생성 모드

- 목적: RPLIDAR S3M1 기반으로 맵 생성 후 파일 저장
- 문서: [Nav2 준비 - 맵 생성 모드](nav2-mapping-mode.md)

## 2) 자율주행 모드

- 목적: 저장된 맵 파일을 읽어 Nav2로 목표점 주행
- 문서: [Nav2 자율주행 모드](nav2-autonomous-mode.md)

## 3) Host Native 모드 (Docker 없이)

- 목적: Jetson Host(`~/ros2_ws`)만으로 맵 생성 + 자율주행 실행
- 문서: [Nav2 Host Native 운영 가이드](nav2-host-native-mode.md)

## 권장 순서

1. 맵 생성 모드 수행
2. `~/maps/my_map.yaml`, `~/maps/my_map.pgm` 생성 확인
3. 자율주행 모드 수행
