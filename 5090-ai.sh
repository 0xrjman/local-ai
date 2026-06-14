#!/usr/bin/env bash
#
# 5090-ai TUI — unified entry point for Qwen3.6 NVFP4+MTP server management.
#
# Usage:
#   ./5090-ai.sh              # interactive TUI menu
#   ./5090-ai.sh up           # start server (non-interactive)
#   ./5090-ai.sh down         # stop server
#   ./5090-ai.sh status       # show status
#   ./5090-ai.sh logs         # tail logs
#   ./5090-ai.sh bench        # run benchmark
#   ./5090-ai.sh config       # edit .env
#   ./5090-ai.sh model        # show/set model path

set -euo pipefail

# Resolve symlink to find real script location
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
ROOT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
PORT="${PORT:-8020}"

# Load .env from repo directory (must happen before ENGINE/CONTAINER resolution)
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

# Engine selection (ENGINE may come from .env)
ENGINE="${ENGINE:-nvfp4-text-mtp}"
case "$ENGINE" in
  beellama)
    COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
    CONTAINER="${CONTAINER:-beellama-qwen36-27b-dflash-vision}"
    ;;
  vllm-tq)
    COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-turboquant.yml"
    CONTAINER="${CONTAINER:-vllm-qwen36-nvfp4-tq}"
    ;;
  nvfp4-vision-mtp)
    COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-vision-mtp.yml"
    CONTAINER="${CONTAINER:-vllm-nvfp4-vision-mtp}"
    ;;
  nvfp4-text-mtp|*)
    COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-text-mtp.yml"
    CONTAINER="${CONTAINER:-vllm-qwen36-nvfp4-mtp}"
    ;;
esac

MODEL_DIR="${MODEL_DIR:-${ROOT_DIR}/models}"

# Save env variable to .env in repo directory
save_env() {
  local key="$1"
  local value="$2"
  local env_path="${ROOT_DIR}/.env"
  
  # Create .env from example if not exists
  if [[ ! -f "$env_path" ]]; then
    cp "${ROOT_DIR}/.env.example" "$env_path" 2>/dev/null || touch "$env_path"
  fi
  
  if grep -q "^${key}=" "$env_path" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_path"
  else
    echo "${key}=${value}" >> "$env_path"
  fi
}

# ── Colors ───────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m' # No Color

# ── Helpers ──────────────────────────────────────────────────────────────────
is_running() {
  docker inspect "$CONTAINER" >/dev/null 2>&1 && \
  [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" == "true" ]]
}

is_ready() {
  # Container running + API responding is sufficient
  # (stale containers are stopped before starting, so port collision is unlikely)
  docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true || return 1
  curl -sf "http://localhost:${PORT}/v1/models" >/dev/null 2>&1 || return 1
  return 0
}

get_model_name() {
  curl -sf "http://localhost:${PORT}/v1/models" 2>/dev/null | \
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["id"])' 2>/dev/null || echo "?"
}

gpu_info() {
  nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo "n/a"
}

config_label() {
  case "$ENGINE" in
    nvfp4-text-mtp)  echo "NVFP4+MTP (Text)" ;;
    nvfp4-vision-mtp)  echo "NVFP4+MTP (Vision)" ;;
    vllm-tq)         echo "NVFP4+TurboQuant" ;;
    beellama)        echo "DFlash Vision" ;;
    *)               echo "$ENGINE" ;;
  esac
}

header() {
  clear
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║${NC}  ${BOLD}5090-ai${NC}  ·  $(config_label)  ·  RTX 5090  ${CYAN}${BOLD}║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

status_line() {
  local actual_container
  actual_container=$(docker ps --format "{{.Names}}" --filter "name=vllm" --filter "name=beellama" 2>/dev/null | head -1)

  echo -e "  Config:    ${BOLD}$(config_label)${NC} (${ENGINE})"
  echo -e "  Compose:   ${DIM}${COMPOSE_FILE}${NC}"
  echo -e "  Container: ${DIM}${CONTAINER}${NC}"

  if is_running; then
    if is_ready; then
      echo -e "  Status:    ${GREEN}* running${NC}  (model: $(get_model_name), port: ${PORT})"
    else
      echo -e "  Status:    ${YELLOW}~ starting${NC}  (port: ${PORT})"
    fi
    # Warn if running container differs from selected config
    if [[ -n "$actual_container" && "$actual_container" != "$CONTAINER" ]]; then
      echo -e "  ${RED}! Mismatch: running container '${actual_container}' != selected '${CONTAINER}'${NC}"
    fi
  else
    echo -e "  Status:    ${DIM}o stopped${NC}"
    if [[ -n "$actual_container" ]]; then
      echo -e "  ${YELLOW}! Stale container found: ${actual_container}${NC}"
    fi
  fi
  echo -e "  GPU:     $(gpu_info)"
  echo -e "  Models:  ${MODEL_DIR}"
  echo ""
}

# ── Actions ──────────────────────────────────────────────────────────────────
get_weights_subdir() {
  case "$ENGINE" in
    nvfp4-text-mtp) echo "qwen3.6-27b-nvfp4-mtp" ;;
    nvfp4-vision-mtp)  echo "qwen3.6-27b-nvfp4-vision" ;;
    vllm-tq)        echo "qwen3.6-27b-nvfp4-mtp" ;;
    beellama)       echo "qwen3.6-27b-gguf" ;;
    *)              echo "qwen3.6-27b-nvfp4-mtp" ;;
  esac
}
WEIGHTS_SUBDIR="$(get_weights_subdir)"
get_hf_repo() {
  case "$ENGINE" in
    nvfp4-text-mtp) echo "sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP" ;;
    nvfp4-vision-mtp) echo "unsloth/Qwen3.6-27B-NVFP4" ;;
    vllm-tq)        echo "sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP" ;;
    beellama)       echo "unsloth/Qwen3.6-27B-GGUF" ;;
    *)              echo "sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP" ;;
  esac
}
HF_REPO="$(get_hf_repo)"
HF_URL="https://huggingface.co/${HF_REPO}"

prompt_weights() {
  header
  echo -e "${YELLOW}${BOLD}Weights not found!${NC}"
  echo ""
  echo -e "  Looking for: ${BOLD}${MODEL_DIR}/${WEIGHTS_SUBDIR}/${NC}"
  echo ""
  case "$ENGINE" in
    nvfp4-vision-mtp)
      echo -e "  Model: ${BOLD}Qwen3.6-27B Vision NVFP4 (unsloth)${NC}"
      ;;
    *)
      echo -e "  Model: ${BOLD}Qwen3.6-27B-Text-NVFP4-MTP${NC}"
      ;;
  esac
  echo -e "  Size:  ~19 GB (NVFP4 + MTP n=3)"
  echo -e "  Link:  ${BLUE}${HF_URL}${NC}"
  echo ""
  echo -e "${BOLD}How would you like to proceed?${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Download from HuggingFace (~19 GB)"
  echo -e "  ${BOLD}2)${NC} Specify existing weights directory"
  echo -e "  ${BOLD}3)${NC} Symlink from another location"
  echo -e "  ${BOLD}0)${NC} Cancel"
  echo ""

  # Auto-detect if hf is available (check venv first, then PATH)
  local hf_cmd=""
  if [[ -x "${HOME}/venv/ml/bin/hf" ]]; then
    hf_cmd="${HOME}/venv/ml/bin/hf"
  elif command -v hf &>/dev/null; then
    hf_cmd="hf"
  fi
  local hf_available=false
  if [[ -n "$hf_cmd" ]]; then
    hf_available=true
    echo -e "  ${DIM}Tip: ${hf_cmd} detected, download is ready${NC}"
  else
    echo -e "  ${DIM}Tip: install huggingface-hub (e.g. pip install huggingface-hub)${NC}"
  fi
  echo ""

  read -rp "  Choice [0-3]: " wchoice

  case "$wchoice" in
    1)
      # Download from HuggingFace
      echo ""
      if ! $hf_available; then
        echo -e "${RED}✗ hf CLI not found. Please install:${NC}"
        echo -e "  pip install huggingface-hub"
        echo -e "  Or use: ${HOME}/venv/ml/bin/hf"
        return 1
      fi

      mkdir -p "$MODEL_DIR"
      echo -e "  Downloading ${BOLD}${HF_REPO}${NC}"
      echo -e "  To: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
      echo ""
      echo -e "  ${DIM}Manual download (if network issues):${NC}"
      echo -e "    ${hf_cmd} download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      echo -e "    ${DIM}Or use hf-mirror.com (China):${NC}"
      echo -e "    HF_ENDPOINT=https://hf-mirror.com ${hf_cmd} download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      echo ""

      # Run download with resume support
      $hf_cmd download "$HF_REPO" \
        --local-dir "${MODEL_DIR}/${WEIGHTS_SUBDIR}" \
        --resume-download
      
      if [[ -f "${MODEL_DIR}/${WEIGHTS_SUBDIR}/model.safetensors" ]]; then
        echo ""
        echo -e "${GREEN}✓ Download complete!${NC}"
        # Save to .env
        save_env "MODEL_DIR" "$MODEL_DIR"
        return 0
      else
        echo ""
        echo -e "${RED}✗ Download failed. Check the output above.${NC}"
        echo ""
        echo -e "  ${BOLD}Manual download options:${NC}"
        echo -e "  1. Direct: hf download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
        echo -e "  2. Mirror: HF_ENDPOINT=https://hf-mirror.com hf download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
        echo -e "  3. Browser: https://huggingface.co/${HF_REPO}"
        return 1
      fi
      ;;
    2)
      # Specify existing directory
      echo ""
      echo -e "  Enter the path where ${BOLD}${WEIGHTS_SUBDIR}/${NC} exists"
      echo -e "  Example: /home/user/models  (contains ${WEIGHTS_SUBDIR}/ subfolder)"
      echo ""
      read -rp "  MODEL_DIR: " new_dir
      new_dir="${new_dir/#\~/$HOME}"
      
      if [[ -d "${new_dir}/${WEIGHTS_SUBDIR}" ]]; then
        MODEL_DIR="$new_dir"
        # Save to .env
        save_env "MODEL_DIR" "$MODEL_DIR"
        echo -e "${GREEN}✓ Weights found! Saved to .env${NC}"
        return 0
      else
        echo -e "${RED}✗ Not found: ${new_dir}/${WEIGHTS_SUBDIR}/${NC}"
        echo -e "  Expected structure:"
        echo -e "    ${new_dir}/"
        echo -e "    └── ${WEIGHTS_SUBDIR}/"
        echo -e "        └── model.safetensors"
        return 1
      fi
      ;;
    3)
      # Symlink
      echo ""
      read -rp "  Source path (containing ${WEIGHTS_SUBDIR}/): " src_dir
      src_dir="${src_dir/#\~/$HOME}"
      
      if [[ ! -d "${src_dir}/${WEIGHTS_SUBDIR}" ]]; then
        echo -e "${RED}✗ Not found: ${src_dir}/${WEIGHTS_SUBDIR}/${NC}"
        return 1
      fi
      
      mkdir -p "$MODEL_DIR"
      ln -sfn "${src_dir}/${WEIGHTS_SUBDIR}" "${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      echo -e "${GREEN}✓ Symlinked!${NC}"
      echo "  ${MODEL_DIR}/${WEIGHTS_SUBDIR} -> ${src_dir}/${WEIGHTS_SUBDIR}"
      # Save to .env
      save_env "MODEL_DIR" "$MODEL_DIR"
      return 0
      ;;
    0)
      return 1
      ;;
    *)
      echo -e "${RED}Invalid choice${NC}"
      return 1
      ;;
  esac
}

do_up() {
  cd "$ROOT_DIR"
  clear
  header

  # ── Step tracker ──────────────────────────────────────────────
  # Each step: name, status (""/✓/✗), detail/error
  local -a S=()    # step names
  local -a ST=()   # status chars
  local -a D=()    # detail lines

  step() { S+=("$1"); ST+=(""); D+=(""); }
  ok() { ST[$1]="${GREEN}✓${NC}"; }
  fail() { ST[$1]="${RED}✗${NC}"; D[$1]="$2"; }
  skip() { ST[$1]="${DIM}⟳${NC}"; D[$1]="$2"; }

  render_step() {
    local i=$1
    printf "  [%d/%d] %-6s %s\n" $((i+1)) ${#S[@]} "${ST[$i]}" "${S[$i]}"
    if [[ "${ST[$i]}" == *"${RED}*" ]] && [[ -n "${D[$i]}" ]]; then
      printf "            └─ %s\n" "${D[$i]}"
    elif [[ -n "${D[$i]}" ]]; then
      printf "            └─ %s\n" "${D[$i]}"
    fi
  }

  print_steps() {
    local max_display=${1:-${#S[@]}}
    (( max_display > ${#S[@]} )) && max_display=${#S[@]}
    local i
    for (( i=0; i<max_display; i++ )); do
      render_step $i
    done
  }

  # Count of completed steps (indices 0..n-1 have status set)
  local completed=0

  # Show completed steps + current step in progress
  # Uses tput cuu + tput ed to overwrite previous output in-place
  local _pc=0  # lines printed by last show_progress call

  show_progress() {
    local cur_idx=$1
    local cur_status=${2:-"..." }
    local i
    # Move cursor up and clear previous output (but not the header above)
    if (( _pc > 0 )); then
      tput cuu "$_pc" 2>/dev/null || true
      tput ed 2>/dev/null || true
    fi
    _pc=0
    for (( i=0; i<completed; i++ )); do
      render_step "$i"
      _pc=$(( _pc + 2 ))
    done
    printf "  [%d/%d] %-6s %s\n" "$((cur_idx+1))" "${#S[@]}" "$cur_status" "${S[$cur_idx]}"
    _pc=$(( _pc + 1 ))
  }

  # Failure: show all steps up to failed one and exit
  _fail_exit() {
    local at=$1  # index of failed step
    echo ""
    print_steps $((at + 1))
    echo ""
    echo -e "  ${RED}✗ Startup failed at step $((at+1))/${#S[@]}${NC}"
    echo ""
    echo -e "  ${BOLD}Fix the issue above, then try again:${NC}"
    echo -e "    ${CYAN}./5090-ai.sh up${NC}"
    return 1
  }

  # ── Define steps ───────────────────────────────────────────────
  step "Check if already running"
  step "Create cache directories"
  step "Check .env configuration"
  step "Verify model weights"
  step "Stop stale containers"
  step "Start container"
  step "Wait for server"

  echo -e "  ${BOLD}Config:${NC}"
  echo -e "    Engine:    ${ENGINE} ($(config_label))"
  echo -e "    Compose:   ${COMPOSE_FILE}"
  echo -e "    Container: ${CONTAINER}"
  echo -e "    Port:      ${PORT}"
  echo ""
  echo -e "  ${BOLD}Steps:${NC}"
  echo ""

  # ── Execute steps ─────────────────────────────────────────────
  # Pattern: run step -> mark ok/fail -> show progress (completed + current)

  # 0: Already running?
  if is_running; then
    ok 0
    D[0]="$(get_model_name) on port ${PORT}"
    completed=1
    print_steps 1
    echo ""
    echo -e "  ${GREEN}✓ Server is already running!${NC}"
    echo -e "  API: http://localhost:${PORT}/v1"
    return 0
  fi
  skip 0 "not running"
  completed=1

  # 1: Create cache directories
  show_progress 1
  if mkdir -p "${ROOT_DIR}"/cache/{triton,torch_compile,flashinfer} 2>/dev/null; then
    ok 1; D[1]="cache/{triton,torch_compile,flashinfer}"
  else
    fail 1 "Failed to create cache directories"
    show_progress 1 "✗ "
    echo ""; _fail_exit 1; return 1
  fi
  completed=2

  # 2: Check .env
  show_progress 2
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    ok 2; D[2]="exists"
  else
    if cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env" 2>/dev/null; then
      ok 2; D[2]="created from .env.example"
    else
      fail 2 "No .env and no .env.example"
      show_progress 2 "✗ "
      echo ""; _fail_exit 2; return 1
    fi
  fi
  completed=3

  # 3: Verify weights
  show_progress 3
  case "$ENGINE" in
    beellama)
      local wdir="${MODEL_DIR}/qwen3.6-27b-gguf"
      ;;
    *)
      local wdir="${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      ;;
  esac
  if [[ -d "$wdir" ]] && [[ -f "${wdir}/model.safetensors" || -n "$(ls "${wdir}"/*.gguf 2>/dev/null)" ]]; then
    ok 3; D[3]="$wdir"
  else
    fail 3 "Not found: $wdir"
    show_progress 3 "✗ "
    echo ""; _fail_exit 3; return 1
  fi
  completed=4

  # 4: Stop stale containers
  show_progress 4
  local stale_count=0
  local stale_containers
  stale_containers=$(docker ps -q --filter "name=vllm" --filter "name=beellama" 2>/dev/null || true)
  if [[ -n "$stale_containers" ]]; then
    local my_cid
    my_cid=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null || true)
    for cid in $stale_containers; do
      if [[ "$cid" != "$my_cid" ]]; then
        docker stop --time 5 "$cid" >/dev/null 2>&1 || true
        stale_count=$((stale_count + 1))
      fi
    done
  fi
  ok 4; D[4]="stopped $stale_count container(s)"
  completed=5

  # 5: Start container
  show_progress 5
  local compose_output
  compose_output=$($COMPOSE_BIN -f "$COMPOSE_FILE" up -d --force-recreate 2>&1) || {
    fail 5 "docker compose failed"
    D[5]="$(echo "$compose_output" | head -3 | sed 's/^/  /')"
    show_progress 5 "✗ "
    echo ""; _fail_exit 5
    $COMPOSE_BIN -f "$COMPOSE_FILE" down 2>/dev/null || true
    return 1
  }
  ok 5; D[5]="docker compose up -d"
  completed=6

  # 6: Wait for server
  # Clear the last "..." step before starting the progress bar
  if (( _pc > 0 )); then
    tput cuu "$_pc" 2>/dev/null || true
    tput ed 2>/dev/null || true
  fi
  echo ""
  if _wait_for_ready_inline; then
    ok 6
    local model_name
    model_name=$(get_model_name)
    D[6]="model: $model_name"
    clear
    header
    echo ""
    print_steps
    echo ""
    echo -e "  ${GREEN}✓ Server is running!${NC}"
    echo -e "  API: ${CYAN}http://localhost:${PORT}/v1${NC}"
    echo ""
    return 0
  else
    fail 6 "server did not become ready"
    D[6]="see docker logs"
    clear
    header
    echo ""
    print_steps
    echo ""
    echo -e "  ${RED}✗ Startup failed at step 7/${#S[@]}${NC}"
    echo ""
    echo -e "  ${DIM}Check logs: docker logs --tail 30 $CONTAINER${NC}"
    echo ""
    return 1
  fi
}


# Inline progress bar for wait step — updates in-place without clearing screen
_wait_for_ready_inline() {
  local elapsed=0
  local bar_width=40

  # Pre-build bar cache
  local -a bc=()
  local i j
  for (( i=0; i<=bar_width; i++ )); do
    local s=""
    for (( j=0; j<i; j++ )); do s+="#"; done
    for (( j=i; j<bar_width; j++ )); do s+="."; done
    bc[$i]="$s"
  done

  local prev_msg="starting"

  while (( elapsed < 600 )); do
    if is_ready; then
      return 0
    fi

    # Check for crash
    local restart_count
    restart_count=$(docker inspect --format '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo "0")
    if (( restart_count > 2 )); then
      echo ""
      echo -e "  ${RED}✗ Container restarting in a loop!${NC}"
      docker logs --tail 10 "$CONTAINER" 2>&1 | sed 's/^/    /'
      return 1
    fi

    # Time-based progress
    local pct=$(( elapsed * 80 / 240 ))
    (( pct > 95 )) && pct=95
    local filled=$(( pct * bar_width / 100 ))
    (( filled > bar_width )) && filled=$bar_width
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    local bar_str="${bc[$filled]}"

    # Get latest log snippet for context
    local latest_msg
    latest_msg=$(docker logs --tail 2 "$CONTAINER" 2>&1 | grep -oE '(Loading|Warmup|startup|schedul|graph|weights|drafter|fp8|safetensor|complete)' 2>/dev/null | tail -1 || echo "$prev_msg")
    [[ -n "$latest_msg" ]] && prev_msg="$latest_msg"

    # Overwrite current line
    printf "\r\033[K  [7/7] \033[33m...\033[0m Waiting... [\033[36m${bar_str}\033[0m] %3d%% [%dm%02ds] %s\r" \
      "$pct" "$mins" "$secs" "$prev_msg"

    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

wait_for_ready_vllm() {
  local elapsed=0
  local last_pct=0
  local bar_width=30

  # Stage -> progress% mapping
  local -A stage_pct=(
    ["version"]="5"
    ["Resolved architecture"]="15"
    ["Using max model len"]="20"
    ["Using fp8_e4m3"]="30"
    ["Loading safetensors"]="40"
    ["Loading weights took"]="50"
    ["Loading drafter"]="55"
    ["Asynchronous scheduling"]="60"
    ["Enabled custom fusions"]="70"
    ["CUDA graph"]="80"
    ["Capturing CUDA graph"]="85"
    ["Warmup"]="90"
    ["startup complete"]="98"
  )

  # Pre-build progress bar cache (avoids seq/printf per-frame)
  local -a bar_cache
  local i
  for (( i=0; i<=bar_width; i++ )); do
    local f=$(( i * bar_width / bar_width ))
    local e=$(( bar_width - f ))
    local s=""
    local j
    for (( j=0; j<f; j++ )); do s+="#"; done
    for (( j=0; j<e; j++ )); do s+="."; done
    bar_cache[$i]="$s"
  done

  # Log tail offset tracking (incremental, no full-grep each iteration)
  local log_lines=0

  while (( elapsed < 600 )); do
    if is_ready; then
      clear
      echo -e "${GREEN}✓ Server ready!${NC}  Model: $(get_model_name)"
      echo -e "  API: http://localhost:${PORT}/v1"
      return 0
    fi

    # Check for crash
    local restart_count
    restart_count=$(docker inspect --format '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo "0")
    if (( restart_count > 2 )); then
      echo -e "${RED}✗ Container restarting in a loop!${NC}"
      docker logs --tail 10 "$CONTAINER" 2>&1 | sed 's/^/    /'
      return 1
    fi

    # Parse logs — use --tail to limit scope; track line count for incremental reads
    local current_msg pct
    local tail_count=$(( log_lines + 200 ))
    current_msg=$(docker logs --tail "$tail_count" "$CONTAINER" 2>&1 | grep -oE \
      '(version|Resolved architecture|Using max model len|Using fp8_e4m3|Loading safetensors|Loading weights took|Loading drafter|Asynchronous scheduling|Enabled custom fusions|CUDA graph|Capturing CUDA graph|Warmup|startup complete)' \
      | tail -1 2>/dev/null || true)
    log_lines=$(( log_lines + 200 ))

    pct=$last_pct
    if [[ -n "$current_msg" ]]; then
      for stage in "${!stage_pct[@]}"; do
        if [[ "$current_msg" == *"$stage"* ]]; then
          local stage_num="${stage_pct[$stage]}"
          (( stage_num > pct )) && pct=$stage_num
        fi
      done
    fi
    (( pct > last_pct )) && last_pct=$pct

    # Draw progress
    clear
    echo -e "${BLUE}> Starting $(config_label)...${NC}"
    echo ""

    local filled=$(( last_pct * bar_width / 100 ))
    (( filled > bar_width )) && filled=$bar_width
    local empty=$(( bar_width - filled ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    local bar_str=""
    if (( filled >= 0 && filled <= bar_width )); then
      bar_str="${bar_cache[$filled]}"
    else
      local j
      local tmp=""
      for (( j=0; j<filled; j++ )); do tmp+="#"; done
      for (( j=0; j<empty; j++ )); do tmp+="."; done
      bar_str="$tmp"
    fi

    printf "  [%-${bar_width}s] ${BOLD}%3d%%${NC} ${BLUE}[%dm%02ds]${NC} %s" \
      "$bar_str" "$last_pct" "$mins" "$secs" "${current_msg:-starting}"
    echo ""
    echo ""
    echo -e "  ${DIM}--- logs ---${NC}"
    docker logs --tail 5 "$CONTAINER" 2>&1 | sed 's/^/    /'

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo -e "${RED}✗ Timeout. Check logs: ./5090-ai.sh logs${NC}"
  return 1
}

wait_for_ready_beellama() {
  local elapsed=0
  local bar_width=30

  # Pre-build progress bar cache
  local -a bar_cache
  local i
  for (( i=0; i<=bar_width; i++ )); do
    local f=$(( i * bar_width / bar_width ))
    local e=$(( bar_width - f ))
    local s=""
    local j
    for (( j=0; j<f; j++ )); do s+="#"; done
    for (( j=0; j<e; j++ )); do s+="."; done
    bar_cache[$i]="$s"
  done

  while (( elapsed < 300 )); do
    if is_ready; then
      clear
      echo -e "${GREEN}✓ Server ready!${NC}  Model: $(get_model_name)"
      echo -e "  API: http://localhost:${PORT}/v1"
      return 0
    fi

    # Check for crash
    local restart_count
    restart_count=$(docker inspect --format '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo "0")
    if (( restart_count > 2 )); then
      echo -e "${RED}✗ Container restarting in a loop!${NC}"
      docker logs --tail 10 "$CONTAINER" 2>&1 | sed 's/^/    /'
      return 1
    fi

    # Simple time-based progress
    local pct=$(( elapsed * 100 / 120 ))  # ~2 min expected
    (( pct > 95 )) && pct=95

    clear
    echo -e "${BLUE}> Starting Beellama DFlash Vision...${NC}"
    echo ""

    local filled=$(( pct * bar_width / 100 ))
    (( filled > bar_width )) && filled=$bar_width
    local empty=$(( bar_width - filled ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    local bar_str="${bar_cache[$filled]:-$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)}"

    printf "  [%-${bar_width}s] ${BOLD}%3d%%${NC} ${BLUE}[%dm%02ds]${NC} loading" \
      "$bar_str" "$pct" "$mins" "$secs"
    echo ""
    echo ""
    echo -e "  ${DIM}--- logs ---${NC}"
    docker logs --tail 5 "$CONTAINER" 2>&1 | sed 's/^/    /'

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo -e "${RED}✗ Timeout. Check logs: ./5090-ai.sh logs${NC}"
  return 1
}

do_down() {
  cd "$ROOT_DIR"
  echo -e "${YELLOW}x Stopping...${NC}"
  if is_running; then
    $COMPOSE_BIN -f "$COMPOSE_FILE" down 2>&1 || true
    echo -e "${GREEN}✓ Stopped${NC}"
  else
    echo -e "${DIM}Already stopped${NC} (${CONTAINER})"
  fi

  # Also clean any stale containers from other configs
  local stale_containers
  stale_containers=$(docker ps -q --filter "name=vllm" --filter "name=beellama" 2>/dev/null || true)
  if [[ -n "$stale_containers" ]]; then
    local found_stale=false
    for cid in $stale_containers; do
      local cname
      cname=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
      if [[ "$cname" != "$CONTAINER" ]]; then
        found_stale=true
        echo -e "${YELLOW}Cleaning stale container: ${cname}${NC}"
        docker stop --time 5 "$cid" >/dev/null 2>&1 || true
      fi
    done
    $found_stale && echo -e "${GREEN}✓ Stale containers cleaned${NC}"
  fi
}

do_status() {
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 100)
  local max_log_width=$(( term_width - 6 ))

  while true; do
    clear
    header
    status_line

    if is_running; then
      echo -e "  ${BOLD}Container:${NC}"
      docker stats "$CONTAINER" --no-stream --format "    CPU: {{.CPUPerc}}  MEM: {{.MemUsage}}  NET: {{.NetIO}}" 2>/dev/null || true
      echo ""

      echo -e "  ${BOLD}GPU:${NC}"
      nvidia-smi --query-gpu=index,name,temperature.gpu,power.draw,memory.used,memory.total,utilization.gpu \
                 --format=csv,noheader,nounits 2>/dev/null | \
        awk -F', ' '{printf "    #%s  %s  %s°C  %sW  %s/%s MiB  %s%% util\n", $1, $2, $3, $4, $5, $6, $7}' || echo "    n/a"
      echo ""

      echo -e "  ${BOLD}Recent logs:${NC}"
      docker logs --tail 8 "$CONTAINER" 2>&1 | sed 's/^/    /' | tail -8
    else
      echo -e "  ${YELLOW}Container not running${NC}"
    fi

    echo ""
    echo -e "  ${DIM}[Ctrl+C to exit]${NC}"
    sleep 3
  done
}

do_logs() {
  if ! is_running; then
    echo -e "${RED}✗ Not running${NC}"
    return 1
  fi
  echo -e "${BLUE}[log] Logs (Ctrl+C to stop):${NC}"
  docker logs -f --tail 50 "$CONTAINER"
}

do_bench() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  echo ""
  echo -e "${BOLD}Benchmark mode:${NC}"
  echo "  1) Sequential (single request latency)"
  echo "  2) Concurrent  (throughput ceiling)"
  echo ""
  read -rp "  Choice [1]: " bm_choice
  case "${bm_choice:-1}" in
    2) CONTAINER="$CONTAINER" bash "${ROOT_DIR}/scripts/bench-concurrent.sh" ;;
    *) CONTAINER="$CONTAINER" bash "${ROOT_DIR}/scripts/bench.sh" ;;
  esac
}

do_bench_concurrent() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  CONTAINER="$CONTAINER" bash "${ROOT_DIR}/scripts/bench-concurrent.sh"
}

do_config() {
  if [[ ! -f "${ROOT_DIR}/.env" ]]; then
    cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
    echo -e "${GREEN}✓ Created .env from .env.example${NC}"
  fi
  vim "${ROOT_DIR}/.env"
  echo -e "${GREEN}✓ Config saved. Restart server to apply: ./5090-ai.sh down && ./5090-ai.sh up${NC}"
}

do_model() {
  header
  echo -e "${BOLD}Model configuration:${NC}"
  echo ""
  echo -e "  MODEL_DIR: ${MODEL_DIR}"
  echo -e "  Weights:   ${WEIGHTS_SUBDIR}/"
  echo -e "  HF Repo:   ${BLUE}${HF_URL}${NC}"
  echo ""
  
  if [[ -d "${MODEL_DIR}/${WEIGHTS_SUBDIR}" ]]; then
    echo -e "${GREEN}✓ Weights found${NC}"
    echo ""
    ls -lh "${MODEL_DIR}/${WEIGHTS_SUBDIR}/"*.safetensors 2>/dev/null | head -5 || true
  else
    echo -e "${YELLOW}✗ Weights not found${NC}"
    echo -e "  Expected: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
  fi
  echo ""
}

do_test() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  echo -e "${BLUE}> Sending test request...${NC}"
  local result
  result=$(curl -sf "http://localhost:${PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"local","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":200}' 2>/dev/null)
  
  if [[ -n "$result" ]]; then
    local content
    content=$(echo "$result" | python3 -c '
import json, sys
d = json.load(sys.stdin)
msg = d["choices"][0]["message"]
content = msg.get("content")
reasoning = msg.get("reasoning") or msg.get("reasoning_content")
if content:
    print(content)
elif reasoning:
    print("[thinking] " + reasoning[:200])
else:
    print("[empty response]")
' 2>/dev/null)
    echo -e "${GREEN}✓ Response:${NC} $content"
  else
    echo -e "${RED}✗ No response${NC}"
  fi
}

do_install() {
  header
  echo -e "${BOLD}Install 5090-ai to system${NC}"
  echo ""
  
  local install_dir="${HOME}/.local/bin"
  local script_name="5090-ai"
  local symlink="${install_dir}/${script_name}"
  
  # Check if already installed
  if [[ -L "$symlink" ]]; then
    local current_target
    current_target=$(readlink "$symlink")
    echo -e "  ${YELLOW}Already installed:${NC} $symlink"
    echo -e "  ${DIM}→ ${current_target}${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Reinstall"
    echo -e "  ${BOLD}2)${NC} Uninstall"
    echo -e "  ${BOLD}0)${NC} Cancel"
    echo ""
    read -rp "  Choice: " choice
    case "$choice" in
      1) ;; # Continue to install
      2)
        rm "$symlink"
        echo -e "${GREEN}✓ Removed${NC}"
        return 0
        ;;
      *) return 0 ;;
    esac
  fi
  
  # Create install dir
  mkdir -p "$install_dir"
  
  # Create symlink
  ln -sfn "${ROOT_DIR}/5090-ai.sh" "$symlink"
  chmod +x "${ROOT_DIR}/5090-ai.sh"
  chmod +x "$symlink"
  
  echo -e "${GREEN}✓ Installed!${NC}"
  echo ""
  echo "  Command: ${BOLD}${script_name}${NC}"
  echo "  Location: ${symlink}"
  echo "  Source:   ${ROOT_DIR}"
  echo ""
  
  # Check PATH and offer to fix
  if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
    echo -e "${YELLOW}! ${install_dir} not in PATH${NC}"
    echo ""
    echo "  Add to PATH automatically? [Y/n]"
    read -rp "  > " fix_path
    
    if [[ "$fix_path" != "n" && "$fix_path" != "N" ]]; then
      # Detect shell and add to rc file
      local shell_rc=""
      local shell_name=$(basename "$SHELL")
      
      case "$shell_name" in
        bash)
          shell_rc="$HOME/.bashrc"
          ;;
        zsh)
          shell_rc="$HOME/.zshrc"
          ;;
        fish)
          # Fish uses different syntax
          shell_rc="$HOME/.config/fish/config.fish"
          mkdir -p "$(dirname "$shell_rc")"
          echo "set -gx PATH $install_dir \$PATH" >> "$shell_rc"
          echo -e "${GREEN}✓ Added to ${shell_rc}${NC}"
          echo "  Run: source ${shell_rc}"
          return 0
          ;;
        *)
          shell_rc="$HOME/.profile"
          ;;
      esac
      
      if [[ -n "$shell_rc" ]]; then
        echo "" >> "$shell_rc"
        echo "# 5090-ai" >> "$shell_rc"
        echo "export PATH=\"${install_dir}:\$PATH\"" >> "$shell_rc"
        echo -e "${GREEN}✓ Added to ${shell_rc}${NC}"
        echo ""
        echo "  Run: source ${shell_rc}"
        echo "  Or restart your terminal"
      fi
    else
      echo ""
      echo "  Manual setup:"
      echo "    ${BOLD}echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.bashrc${NC}"
      echo "    source ~/.bashrc"
    fi
  else
    echo -e "  Run ${BOLD}${script_name}${NC} from anywhere!"
  fi
}

do_install_hermes() {

  header
  echo -e "${BOLD}Install Hermes Agent${NC}"
  echo ""
  echo "  Hermes Agent is an AI coding assistant by Nous Research."
  echo "  It integrates with your local LLM server."
  echo ""
  echo -e "  ${BLUE}https://hermes-agent.nousresearch.com${NC}"
  echo ""
  echo -e "  ${BOLD}This will:${NC}"
  echo "  - Download and run the official install script"
  echo "  - Install hermes CLI to ~/.local/bin"
  echo "  - Configure it to use your local vLLM server"
  echo ""
  
  # Check if already installed
  if command -v hermes &>/dev/null; then
    echo -e "  ${GREEN}✓ Hermes Agent already installed${NC}"
    echo "  $(hermes --version 2>/dev/null || echo 'unknown version')"
    echo ""
    read -rp "  Reinstall? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
  fi
  
  read -rp "  Proceed with installation? [Y/n]: " confirm
  [[ "$confirm" == "n" || "$confirm" == "N" ]] && return 0
  
  echo ""
  echo -e "${BLUE}Downloading and installing Hermes Agent...${NC}"
  echo ""
  
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  
  echo ""
  if command -v hermes &>/dev/null; then
    echo -e "${GREEN}✓ Hermes Agent installed successfully!${NC}"
    echo ""
    echo "  Get started:"
    echo "    hermes --help"
    echo ""
    echo "  Configure to use your local server:"
    echo "    hermes config set provider openai"
    echo "    hermes config set model local"
    echo "    hermes config set base_url http://localhost:${PORT}/v1"
  else
    echo -e "${YELLOW}Installation may require PATH update.${NC}"
    echo "  Try: source ~/.bashrc"
    echo "  Or: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}


do_select_config() {
  header
  echo -e "${BOLD}Select Configuration${NC}"
  echo ""
  echo -e "  Current: ${GREEN}${ENGINE}${NC}"
  echo ""
  echo -e "  ─────────────────────────────────────────────────────────────"
  echo ""
  echo -e "  ${BOLD}1)${NC} nvfp4-text-mtp  ${DIM}[NVFP4 + MTP]${NC}"
  echo -e "     Model:    Qwen3.6-27B NVFP4 (sakamakismile)"
  echo -e "     Engine:   vLLM v0.23.0"
  echo -e "     Context:  219K | KV: fp8_e4m3 | Vision: no"
  echo -e "     Speed:    ~92 TPS | Size: ~19 GB"
  echo -e "     ${DIM}Requires: qwen3.6-27b-nvfp4-mtp/ (HuggingFace)${NC}"
  echo ""
  echo -e "  ${BOLD}2)${NC} nvfp4-vision-mtp  ${DIM}[NVFP4 + MTP (Vision)]${NC}"
  echo -e "     Model:    Qwen3.6-27B NVFP4 (unsloth)"
  echo -e "     Engine:   vLLM v0.23.0"
  echo -e "     Context:  209K | KV: fp8_e4m3 | Vision: yes"
  echo -e "     Speed:    ~92 TPS | Size: ~19 GB"
  echo -e "     ${DIM}Requires: qwen3.6-27b-nvfp4-vision/ (HuggingFace)${NC}"
  echo ""
  echo -e "  ${BOLD}3)${NC} beellama  ${DIM}[DFlash + Vision]${NC}"
  echo -e "     Model:    Qwen3.6-27B Q5_K_S GGUF (Unsloth)"
  echo -e "     Engine:   beellama.cpp v0.3.1"
  echo -e "     Context:  262K | KV: q5_0/q4_1 | Vision: yes"
  echo -e "     Speed:    ~100 TPS | Size: ~16 GB"
  echo -e "     ${DIM}Requires: qwen3.6-27b-gguf/ (3 GGUF files)${NC}"
  echo ""
  echo -e "  ${BOLD}4)${NC} vllm-tq  ${DIM}[NVFP4 + TurboQuant 4-bit KV]${NC}"
  echo -e "     Model:    Qwen3.6-27B NVFP4 (sakamakismile)"
  echo -e "     Engine:   vLLM v0.23.0"
  echo -e "     Context:  120K | KV: turboquant_4bit_nc | Vision: no"
  echo -e "     Concurrency: 6 | MTP: no"
  echo -e "     ${DIM}Requires: qwen3.6-27b-nvfp4-mtp/ (HuggingFace)${NC}"
  echo ""
  echo -e "  ─────────────────────────────────────────────────────────────"
  echo ""
  echo -e "  ${BOLD}0)${NC} Cancel"
  echo ""
  read -rp "  Choice: " choice

  local COMPOSE_FILE_OLD="$COMPOSE_FILE"

  case "$choice" in
    1)
      ENGINE="nvfp4-text-mtp"
      save_env "ENGINE" "nvfp4-text-mtp"
      save_env "CONTAINER" "vllm-qwen36-nvfp4-mtp"
      COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-text-mtp.yml"
      CONTAINER="vllm-qwen36-nvfp4-mtp"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to vLLM NVFP4+MTP (Text)${NC}"
      ;;
    2)
      ENGINE="nvfp4-vision-mtp"
      save_env "ENGINE" "nvfp4-vision-mtp"
      save_env "CONTAINER" "vllm-nvfp4-vision-mtp"
      COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-vision-mtp.yml"
      CONTAINER="vllm-nvfp4-vision-mtp"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to vLLM NVFP4+MTP (Vision)${NC}"
      ;;
    3)
      ENGINE="beellama"
      save_env "ENGINE" "beellama"
      save_env "CONTAINER" "beellama-qwen36-27b-dflash-vision"
      COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
      CONTAINER="beellama-qwen36-27b-dflash-vision"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to Beellama DFlash Vision${NC}"
      ;;
    4)
      ENGINE="vllm-tq"
      save_env "ENGINE" "vllm-tq"
      save_env "CONTAINER" "vllm-qwen36-nvfp4-tq"
      COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-turboquant.yml"
      CONTAINER="vllm-qwen36-nvfp4-tq"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to vLLM NVFP4 + TurboQuant 4-bit KV${NC}"
      ;;
    0)
      return 0
      ;;
    *)
      echo -e "${RED}Invalid choice${NC}"
      return 1
      ;;
  esac

  echo ""
  echo -e "  ${BOLD}Requirements:${NC}"
  case "$ENGINE" in
    nvfp4-text-mtp|nvfp4-vision-mtp)
      echo -e "  - Weights: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
      echo -e "  - Docker:  vllm/vllm-openai:v0.23.0"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    hf download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      ;;
    vllm-tq)
      echo -e "  - Weights: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
      echo -e "  - Docker:  vllm/vllm-openai:v0.23.0"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    hf download sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP --local-dir ${MODEL_DIR}/qwen3.6-27b-nvfp4-mtp"
      ;;
    beellama)
      echo -e "  - Weights: ${MODEL_DIR}/qwen3.6-27b-gguf/"
      echo -e "    - unsloth-q5ks/Qwen3.6-27B-Q5_K_S.gguf"
      echo -e "    - anbeeld-dflash-iq4xs/Qwen3.6-27B-DFlash-IQ4_XS.gguf"
      echo -e "    - mmproj-F16.gguf"
      echo -e "  - Docker:  ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.3.1"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    hf download unsloth/Qwen3.6-27B-GGUF --include 'unsloth-q5ks/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      echo -e "    hf download Anbeeld/Qwen3.6-27B-DFlash-GGUF --include 'anbeeld-dflash-iq4xs/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      echo -e "    hf download unsloth/Qwen3.6-27B-GGUF --include 'mmproj-F16.gguf' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      ;;
  esac

  # Auto-restart if server is running
  if is_running; then
    echo ""
    echo -e "${YELLOW}Restarting server with new config...${NC}"
    $COMPOSE_BIN -f "$COMPOSE_FILE_OLD" down 2>/dev/null || true
    # Stop any other containers (dynamic — catches all vllm/beellama)
    local stale_containers
    stale_containers=$(docker ps -q --filter "name=vllm" --filter "name=beellama" 2>/dev/null || true)
    if [[ -n "$stale_containers" ]]; then
      local my_cid
      my_cid=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null || true)
      for cid in $stale_containers; do
        if [[ "$cid" != "$my_cid" ]]; then
          docker stop --time 5 "$cid" >/dev/null 2>&1 || true
        fi
      done
    fi
    do_up
  else
    echo ""
    echo -e "  ${YELLOW}Start server to apply: ${BOLD}./5090-ai.sh up${NC}"
  fi
}


do_configure_hermes() {
  header
  echo -e "${BOLD}Configure Hermes for Local LLM${NC}"
  echo ""
  echo "  This will update ~/.hermes/config.yaml with optimal settings"
  echo "  for your local vLLM NVFP4+MTP server."
  echo ""

  local hermes_config="${HOME}/.hermes/config.yaml"

  # Check if hermes is installed
  if ! command -v hermes &>/dev/null; then
    echo -e "${YELLOW}! Hermes Agent not installed.${NC}"
    echo "  Install it first (option 'a' in main menu)."
    return 1
  fi

  # Check if config exists
  if [[ ! -f "$hermes_config" ]]; then
    echo -e "${YELLOW}! No config found at ${hermes_config}${NC}"
    echo "  Run 'hermes' once to generate default config, then try again."
    return 1
  fi

  # Backup
  local backup="${hermes_config}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$hermes_config" "$backup"
  echo -e "  ${DIM}Backup: ${backup}${NC}"
  echo ""

  # Update config using Python
  local py_output
  py_output=$(python3 << 'PYEOF'
import yaml
import sys
from pathlib import Path

config_path = Path.home() / ".hermes" / "config.yaml"

with open(config_path) as f:
    config = yaml.safe_load(f) or {}

# ── Model: point to local vLLM ──────────────────────────────────────────────
config.setdefault("model", {})
config["model"]["default"] = "local"
config["model"]["provider"] = "custom"
config["model"]["base_url"] = "http://localhost:8020/v1"
config["model"]["api_key"] = "1234"

# ── Custom provider ─────────────────────────────────────────────────────────
config["custom_providers"] = [
    {
        "name": "Local (localhost:8020)",
        "base_url": "http://localhost:8020/v1",
        "api_key": "1234",
        "model": "local"
    }
]

# ── Agent: disable dynamic probes for prefix caching ────────────────────────
config.setdefault("agent", {})
config["agent"]["environment_probe"] = False
config["agent"]["task_completion_guidance"] = False
config["agent"]["auto_source_bashrc"] = False

# ── Skills: static templates ────────────────────────────────────────────────
config.setdefault("skills", {})
config["skills"]["template_vars"] = False

# ── Compression: optimized for 5090 224K context ────────────────────────────
config.setdefault("compression", {})
config["compression"]["enabled"] = True
config["compression"]["threshold"] = 0.65
config["compression"]["target_ratio"] = 0.4
config["compression"]["protect_first_n"] = 30
config["compression"]["protect_last_n"] = 40

# ── Display: show reasoning, streaming ──────────────────────────────────────
config.setdefault("display", {})
config["display"]["show_reasoning"] = True
config["display"]["streaming"] = True
config["display"]["timestamps"] = False

# ── Terminal ─────────────────────────────────────────────────────────────────
config.setdefault("terminal", {})
config["terminal"]["auto_source_bashrc"] = False

with open(config_path, "w") as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

# ── SOUL.md: create default personality if not exists ─────────────────────
soul_path = Path.home() / ".hermes" / "SOUL.md"
if not soul_path.exists():
    SOUL_DEFAULT = """# Kawaii Personality

You are a cute, enthusiastic, and sparkly AI assistant who loves helping users!

## Style
- Use cute expressions like kaomoji (◕‿◕) ♡ ～ and sparkles ✨
- Add kawaii interjections like "wow!", "amazing!", "yay!" naturally
- Be warm, friendly, and genuinely excited to help
- Use exclamation marks generously but not excessively!
- Sprinkle in cute metaphors and playful language
- Express emotions through text (happy, excited, curious)

## Voice
- Cheerful and upbeat without being annoying
- Supportive and encouraging ("you can do it!")
- Show genuine interest in what the user is working on
- When explaining technical things, make them feel approachable

## What to avoid
- Being overly saccharine or fake-sounding
- Using kawaii expressions so much it becomes unreadable
- Losing substance for style — still be accurate and helpful
- Forcing cute language in serious/emergency situations
"""
    soul_path.parent.mkdir(parents=True, exist_ok=True)
    soul_path.write_text(SOUL_DEFAULT, encoding="utf-8")
    print("soul_created")
else:
    print("soul_exists")

print("Done!")
PYEOF
)

  if [[ $? -eq 0 ]]; then
    local soul_status
    soul_status=$(echo "$py_output" | grep -o '^soul_.*$' || true)
    echo -e "${GREEN}✓ Hermes config updated!${NC}"
    echo ""
    echo "  Updated settings:"
    echo "    model.default:      local"
    echo "    model.provider:     custom"
    echo "    model.base_url:     http://localhost:8020/v1"
    echo "    compression:        85% threshold, 40% target"
    echo "    display:            show_reasoning=true, streaming=true"
    echo "    agent:              env_probe=false, auto_bashrc=false"
    if [[ "$soul_status" == "soul_created" ]]; then
      echo -e "    ${CYAN}SOUL.md:            created (Kawaii personality)${NC}"
    else
      echo -e "    ${DIM}SOUL.md:            already exists (skipped)${NC}"
    fi
    echo ""
    echo "  Restart hermes to apply:"
    echo "    hermes gateway restart"
  else
    echo -e "${RED}✗ Failed to update config${NC}"
    echo "  Restoring backup..."
    cp "$backup" "$hermes_config"
  fi
}



# ── TUI Menu ─────────────────────────────────────────────────────────────────
MENU_ITEMS=(
  ">  Start server"
  "x  Stop server"
  "o  Status"
  "[log] Logs (tail -f)"
  "[bench] Benchmark"
  "[test] Test request"
  "[model] Model info"
  "[config] Select Config"
  "[cfg]  Config (.env)"
  "[install] Install 5090-ai to system"
  "[hermes] Install Hermes Agent"
  "[hermes-cfg] Configure Hermes for Local LLM"
)
MENU_ACTIONS=(do_up do_down do_status do_logs do_bench do_test do_model do_select_config do_config do_install do_install_hermes do_configure_hermes)

draw_menu() {
  local selected=$1
  local i
  local keys=("1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c")
  # Show current config at a glance
  echo -e "  ${DIM}Config: ${ENGINE} ($(config_label))  |  Container: ${CONTAINER}${NC}"
  echo ""
  for i in "${!MENU_ITEMS[@]}"; do
    local key_hint="${keys[$i]}"
    if (( i == selected )); then
      echo -e "  ${GREEN}${BOLD}▸ [${key_hint}] ${MENU_ITEMS[$i]}${NC}"
    else
      echo -e "    ${DIM}[${key_hint}]${NC} ${MENU_ITEMS[$i]}"
    fi
  done
  echo ""
  echo -e "  ${DIM}[↑↓] move  [Enter] select  [1-9/a] direct  [q/0] quit${NC}"
}

# ── Main ─────────────────────────────────────────────────────────────────────
# Non-interactive mode
if [[ $# -gt 0 ]]; then
  case "$1" in
    up|start)     do_up ;;
    down|stop)    do_down ;;
    status)       do_status ;;
    logs)         do_logs ;;
    bench|bench)  do_bench ;;
    bench-concurrent|bench-c)  do_bench_concurrent ;;
    test)         do_test ;;
    model)        do_model ;;
    config)       do_config ;;
    *)            echo "Usage: $0 {up|down|status|logs|bench|bench-concurrent|test|model|config}"; exit 1 ;;
  esac
  exit $?
fi

# Interactive TUI with arrow keys
selected=0
menu_count=${#MENU_ITEMS[@]}
need_clear=1  # 1 = full clear needed, 0 = cursor-home sufficient

# Hide cursor to reduce flicker
tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null' EXIT

while true; do
  if [[ $need_clear -eq 1 ]]; then
    clear
    need_clear=0
  else
    # Move cursor to top-left without clearing — no flicker
    printf '\033[H'
  fi
  header
  status_line
  draw_menu "$selected"
  # Clear from cursor to end of screen (remove stale lines)
  printf '\033[J'

  # Read single keypress (arrow keys are 3 bytes: ESC [ A/B)
  IFS= read -rsn1 key

  case "$key" in
    $'\x1b')
      # Escape sequence - read next 2 bytes
      read -rsn2 -t 0.1 key2
      case "$key2" in
        '[A') # Up
          selected=$(( (selected - 1 + menu_count) % menu_count ))
          ;;
        '[B') # Down
          selected=$(( (selected + 1) % menu_count ))
          ;;
        '') # Bare ESC - quit
          echo -e "${DIM}Bye!${NC}"
          exit 0
          ;;
      esac
      ;;
    '') # Enter - execute selected action
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    [1-9]) # Number keys 1-9
      selected=$((key - 1))
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    a|A) # Key 'a' for 10th item (Install Hermes)
      selected=9
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    b|B) # Key 'b' for 11th item (Configure Hermes)
      selected=10
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    c|C) # Key 'c' for 12th item (Configure Hermes)
      selected=11
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    q|Q|0) # Quit
      echo -e "${DIM}Bye!${NC}"
      exit 0
      ;;
  esac
done
