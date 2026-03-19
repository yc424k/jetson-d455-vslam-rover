#!/usr/bin/env bash
set -euo pipefail

TARGET_FILE="${TARGET_FILE:-$HOME/ros2_ws/src/md_motor_driver_ros2/md_controller/launch/md_controller.launch.py}"
WHEEL_RADIUS="${WHEEL_RADIUS:-0.10}"   # MDH300 wheel dia 200mm
WHEEL_BASE="${WHEEL_BASE:-0.44}"       # user measured 440mm
GEAR_RATIO="${GEAR_RATIO:-4.33}"       # MDH300 datasheet
RIGHT_GEAR_RATIO="${RIGHT_GEAR_RATIO:-4.33}"
POLES="${POLES:-20}"                   # MDH300 datasheet
LEFT_SIGN="${LEFT_SIGN:-1}"
RIGHT_SIGN="${RIGHT_SIGN:-1}"
BACKUP=true

usage() {
  cat <<'EOF'
Usage:
  apply_mdh300_ppr_params.sh [options]

Options:
  --target <path>            md_controller.launch.py path
  --wheel-radius <value>     wheel_radius (m), default: 0.10
  --wheel-base <value>       wheel_base (m), default: 0.44
  --gear-ratio <value>       GearRatio, default: 4.33
  --right-gear-ratio <value> RightGearRatio, default: 4.33
  --poles <value>            poles, default: 20
  --left-sign <value>        left_sign, default: 1
  --right-sign <value>       right_sign, default: 1
  --no-backup                Skip creating .bak timestamp file
  -h, --help                 Show this help

Examples:
  ./apply_mdh300_ppr_params.sh
  ./apply_mdh300_ppr_params.sh --left-sign -1 --right-sign -1
EOF
}

log() {
  echo "[INFO] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

replace_key() {
  local key="$1"
  local value="$2"
  local file="$3"
  if ! grep -q "\"$key\"" "$file"; then
    log "Skip: key not found -> $key"
    return 0
  fi
  perl -0777 -i -pe "s/(\"$key\"\\s*:\\s*)([-+]?[0-9]*\\.?[0-9]+)/\$1$value/g" "$file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        TARGET_FILE="${2:-}"
        shift 2
        ;;
      --wheel-radius)
        WHEEL_RADIUS="${2:-}"
        shift 2
        ;;
      --wheel-base)
        WHEEL_BASE="${2:-}"
        shift 2
        ;;
      --gear-ratio)
        GEAR_RATIO="${2:-}"
        shift 2
        ;;
      --right-gear-ratio)
        RIGHT_GEAR_RATIO="${2:-}"
        shift 2
        ;;
      --poles)
        POLES="${2:-}"
        shift 2
        ;;
      --left-sign)
        LEFT_SIGN="${2:-}"
        shift 2
        ;;
      --right-sign)
        RIGHT_SIGN="${2:-}"
        shift 2
        ;;
      --no-backup)
        BACKUP=false
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  [[ -n "$TARGET_FILE" ]] || die "--target is empty"
  [[ -f "$TARGET_FILE" ]] || die "Target file not found: $TARGET_FILE"

  if [[ "$BACKUP" == true ]]; then
    local backup_file
    backup_file="${TARGET_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$TARGET_FILE" "$backup_file"
    log "Backup created: $backup_file"
  fi

  replace_key "wheel_radius" "$WHEEL_RADIUS" "$TARGET_FILE"
  replace_key "wheel_base" "$WHEEL_BASE" "$TARGET_FILE"
  replace_key "GearRatio" "$GEAR_RATIO" "$TARGET_FILE"
  replace_key "RightGearRatio" "$RIGHT_GEAR_RATIO" "$TARGET_FILE"
  replace_key "poles" "$POLES" "$TARGET_FILE"
  replace_key "left_sign" "$LEFT_SIGN" "$TARGET_FILE"
  replace_key "right_sign" "$RIGHT_SIGN" "$TARGET_FILE"

  log "Applied MDH300(PPR) defaults to: $TARGET_FILE"
  log "Current key lines:"
  rg -n "\"wheel_radius\"|\"wheel_base\"|\"GearRatio\"|\"RightGearRatio\"|\"poles\"|\"left_sign\"|\"right_sign\"" "$TARGET_FILE" || true
}

main "$@"
