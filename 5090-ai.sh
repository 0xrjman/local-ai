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
ENGINE="${ENGINE:-vllm}"
case "$ENGINE" in
  beellama)
    COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
    CONTAINER="${CONTAINER:-beellama-qwen36-27b-dflash-vision}"
    ;;
  vllm-tq)
    COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-turboquant.yml"
    CONTAINER="${CONTAINER:-vllm-qwen36-nvfp4-tq}"
    ;;
  vllm|*)
    COMPOSE_FILE="${ROOT_DIR}/compose/mtp.yml"
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
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ── Helpers ──────────────────────────────────────────────────────────────────
is_running() {
  docker inspect "$CONTAINER" >/dev/null 2>&1 && \
  [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" == "true" ]]
}

is_ready() {
  curl -sf "http://localhost:${PORT}/v1/models" >/dev/null 2>&1
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
    vllm)     echo "NVFP4+MTP" ;;
    vllm-tq)  echo "NVFP4+TurboQuant" ;;
    beellama) echo "DFlash Vision" ;;
    *)        echo "$ENGINE" ;;
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
WEIGHTS_SUBDIR="qwen3.6-27b-nvfp4-mtp"
HF_REPO="sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP"
HF_URL="https://huggingface.co/${HF_REPO}"

prompt_weights() {
  header
  echo -e "${YELLOW}${BOLD}Weights not found!${NC}"
  echo ""
  echo -e "  Looking for: ${BOLD}${MODEL_DIR}/${WEIGHTS_SUBDIR}/${NC}"
  echo ""
  echo -e "  Model: ${BOLD}Qwen3.6-27B-Text-NVFP4-MTP${NC}"
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

  # Auto-detect if huggingface-cli is available
  local hf_available=false
  if command -v huggingface-cli &>/dev/null || command -v hf &>/dev/null; then
    hf_available=true
    echo -e "  ${DIM}Tip: huggingface-cli detected, download is ready${NC}"
  else
    echo -e "  ${DIM}Tip: install huggingface-hub for direct download: pip install huggingface-hub${NC}"
  fi
  echo ""

  read -rp "  Choice [0-3]: " wchoice

  case "$wchoice" in
    1)
      # Download from HuggingFace
      echo ""
      if ! $hf_available; then
        echo -e "${YELLOW}Installing huggingface-hub...${NC}"
        pip install --quiet huggingface-hub
      fi
      
      local hf_cmd="huggingface-cli"
      command -v hf &>/dev/null && hf_cmd="hf"
      
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
        echo -e "  1. Direct: ${hf_cmd} download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
        echo -e "  2. Mirror: HF_ENDPOINT=https://hf-mirror.com ${hf_cmd} download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
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
  mkdir -p "${ROOT_DIR}"/cache/{triton,torch_compile,flashinfer}
  
  # First run: create .env if not exists
  if [[ ! -f "${ROOT_DIR}/.env" ]]; then
    cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env" 2>/dev/null || true
  fi

  cd "$ROOT_DIR"

  # Check if already running
  if is_running; then
    echo -e "${GREEN}* Already running${NC} (${CONTAINER})"
    echo -e "  Model: $(get_model_name)  Port: ${PORT}"
    return 0
  fi

  # Stop any stale containers from other configs
  local stale
  for stale in vllm-qwen36-nvfp4-mtp vllm-qwen36-nvfp4-tq beellama-qwen36-27b-dflash-vision; do
    if [[ "$stale" != "$CONTAINER" ]] && docker inspect "$stale" >/dev/null 2>&1; then
      echo -e "${YELLOW}Stopping stale container: ${stale}${NC}"
      docker stop "$stale" >/dev/null 2>&1 || true
    fi
  done

  # Engine-specific setup
  case "$ENGINE" in
    beellama)
      do_up_beellama || return 1
      ;;
    vllm|*)
      do_up_vllm || return 1
      ;;
  esac
}

do_up_vllm() {
  echo -e "${BLUE}> Starting $(config_label)...${NC}"
  echo -e "  Compose:   ${COMPOSE_FILE}"
  echo -e "  Container: ${CONTAINER}"

  # Show config summary
  local ctx kv mtp_v vision max_seq
  case "$ENGINE" in
    vllm)
      ctx="219K"; kv="fp8_e4m3"; mtp_v="n=3"; vision="no"; max_seq="${MAX_NUM_SEQS:-2}"
      ;;
    vllm-tq)
      ctx="120K"; kv="turboquant_4bit_nc"; mtp_v="none"; vision="no"; max_seq="${MAX_NUM_SEQS:-6}"
      ;;
  esac
  echo -e "  Context:   ${ctx} | KV: ${kv} | MTP: ${mtp_v} | Vision: ${vision} | Max seqs: ${max_seq}"

  # Check weights
  if [[ ! -d "${MODEL_DIR}/${WEIGHTS_SUBDIR}" ]]; then
    prompt_weights || return 1
  fi

  # Check and pull vLLM image if needed
  local vllm_image
  vllm_image=$(grep 'image:' "$COMPOSE_FILE" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
  vllm_image="${vllm_image#\${VLLM_IMAGE:-}"
  vllm_image="${vllm_image%\}}"
  vllm_image="${vllm_image:-vllm/vllm-openai:v0.22.1}"
  
  if ! docker image inspect "$vllm_image" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}Downloading vLLM image: ${vllm_image}${NC}"
    echo -e "  ${DIM}(This may take a few minutes on first run)${NC}"
    echo ""
    docker pull "$vllm_image"
    echo ""
  fi

  # First-time compile warning
  if [[ ! -d "${ROOT_DIR}/cache/torch_compile" ]] || [[ -z "$(ls -A "${ROOT_DIR}/cache/torch_compile" 2>/dev/null)" ]]; then
    echo -e "  ${YELLOW}Note: First compile is slow (~2-3 min). Cached after that.${NC}"
  fi

  $COMPOSE_BIN -f "$COMPOSE_FILE" up -d
  wait_for_ready_vllm
}

do_up_beellama() {
  echo -e "${BLUE}> Starting Beellama DFlash Vision...${NC}"

  # Check GGUF weights
  local gguf_dir="${MODEL_DIR}/qwen3.6-27b-gguf"
  if [[ ! -d "$gguf_dir" ]]; then
    echo -e "${YELLOW}GGUF weights not found at:${NC}"
    echo "  ${gguf_dir}/"
    echo ""
    echo -e "${BOLD}Required files:${NC}"
    echo "  - unsloth-q5ks/Qwen3.6-27B-Q5_K_S.gguf"
    echo "  - anbeeld-dflash-iq4xs/Qwen3.6-27B-DFlash-IQ4_XS.gguf"
    echo "  - mmproj-F16.gguf"
    echo ""
    echo -e "${BOLD}Download:${NC}"
    echo "  huggingface-cli download unsloth/Qwen3.6-27B-GGUF --include 'unsloth-q5ks/*' --local-dir ${gguf_dir}"
    echo "  huggingface-cli download Anbeeld/Qwen3.6-27B-DFlash-GGUF --include 'anbeeld-dflash-iq4xs/*' --local-dir ${gguf_dir}"
    echo "  huggingface-cli download unsloth/Qwen3.6-27B-GGUF --include 'mmproj-F16.gguf' --local-dir ${gguf_dir}"
    echo ""
    echo -e "  ${DIM}Or set MODEL_DIR in .env to point to existing weights${NC}"
    return 1
  fi

  # Check beellama image
  local beellama_image
  beellama_image=$(grep 'image:' "$COMPOSE_FILE" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
  beellama_image="${beellama_image#\${BEELLAMA_IMAGE:-}"
  beellama_image="${beellama_image%\}}"
  beellama_image="${beellama_image:-ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.3.1}"
  
  if ! docker image inspect "$beellama_image" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}Downloading Beellama image: ${beellama_image}${NC}"
    echo -e "  ${DIM}(This may take a few minutes on first run)${NC}"
    echo ""
    docker pull "$beellama_image"
    echo ""
  fi

  $COMPOSE_BIN -f "$COMPOSE_FILE" up -d
  wait_for_ready_beellama
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

    # Parse logs for progress
    local current_msg pct
    current_msg=$(docker logs "$CONTAINER" 2>&1 | grep -oE \
      '(version|Resolved architecture|Using max model len|Using fp8_e4m3|Loading safetensors|Loading weights took|Loading drafter|Asynchronous scheduling|Enabled custom fusions|CUDA graph|Capturing CUDA graph|Warmup|startup complete)' \
      | tail -1 2>/dev/null || true)

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
    local empty=$(( bar_width - filled ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    printf "  [%-${bar_width}s] ${BOLD}%3d%%${NC} ${BLUE}[%dm%02ds]${NC} %s" \
      "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)$(printf '.%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)" \
      "$last_pct" "$mins" "$secs" "${current_msg:-starting}"
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
    local empty=$(( bar_width - filled ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    printf "  [%-${bar_width}s] ${BOLD}%3d%%${NC} ${BLUE}[%dm%02ds]${NC} loading" \
      "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)$(printf '.%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)" \
      "$pct" "$mins" "$secs"
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
    -d '{"model":"qwen3.6","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":200}' 2>/dev/null)
  
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
    echo "    hermes config set model qwen3.6"
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
  echo -e "  ${BOLD}1)${NC} vllm  ${DIM}[NVFP4 + MTP]${NC}"
  echo -e "     Model:    Qwen3.6-27B NVFP4 (sakamakismile)"
  echo -e "     Engine:   vLLM v0.22.1"
  echo -e "     Context:  224K | KV: fp8_e4m3 | Vision: no"
  echo -e "     Speed:    ~92 TPS | Size: ~19 GB"
  echo -e "     ${DIM}Requires: qwen3.6-27b-nvfp4-mtp/ (HuggingFace)${NC}"
  echo ""
  echo -e "  ${BOLD}2)${NC} beellama  ${DIM}[DFlash + Vision]${NC}"
  echo -e "     Model:    Qwen3.6-27B Q5_K_S GGUF (Unsloth)"
  echo -e "     Engine:   beellama.cpp v0.3.1"
  echo -e "     Context:  262K | KV: q5_0/q4_1 | Vision: yes"
  echo -e "     Speed:    ~100 TPS | Size: ~16 GB"
  echo -e "     ${DIM}Requires: qwen3.6-27b-gguf/ (3 GGUF files)${NC}"
  echo ""
  echo -e "  ${BOLD}3)${NC} vllm-tq  ${DIM}[NVFP4 + TurboQuant 4-bit KV]${NC}"
  echo -e "     Model:    Qwen3.6-27B NVFP4 (sakamakismile)"
  echo -e "     Engine:   vLLM v0.22.1"
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
      ENGINE="vllm"
      save_env "ENGINE" "vllm"
      save_env "CONTAINER" "vllm-qwen36-nvfp4-mtp"
      COMPOSE_FILE="${ROOT_DIR}/compose/mtp.yml"
      CONTAINER="vllm-qwen36-nvfp4-mtp"
      echo ""
      echo -e "${GREEN}✓ Switched to vLLM NVFP4+MTP${NC}"
      ;;
    2)
      ENGINE="beellama"
      save_env "ENGINE" "beellama"
      save_env "CONTAINER" "beellama-qwen36-27b-dflash-vision"
      COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
      CONTAINER="beellama-qwen36-27b-dflash-vision"
      echo ""
      echo -e "${GREEN}✓ Switched to Beellama DFlash Vision${NC}"
      ;;
    3)
      ENGINE="vllm-tq"
      save_env "ENGINE" "vllm-tq"
      save_env "CONTAINER" "vllm-qwen36-nvfp4-tq"
      COMPOSE_FILE="${ROOT_DIR}/compose/nvfp4-turboquant.yml"
      CONTAINER="vllm-qwen36-nvfp4-tq"
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
    vllm)
      echo -e "  - Weights: ${MODEL_DIR}/qwen3.6-27b-nvfp4-mtp/"
      echo -e "  - Docker:  vllm/vllm-openai:v0.22.1"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    huggingface-cli download sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP --local-dir ${MODEL_DIR}/qwen3.6-27b-nvfp4-mtp"
      ;;
    vllm-tq)
      echo -e "  - Weights: ${MODEL_DIR}/qwen3.6-27b-nvfp4-mtp/"
      echo -e "  - Docker:  vllm/vllm-openai:v0.22.1"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    huggingface-cli download sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP --local-dir ${MODEL_DIR}/qwen3.6-27b-nvfp4-mtp"
      ;;
    beellama)
      echo -e "  - Weights: ${MODEL_DIR}/qwen3.6-27b-gguf/"
      echo -e "    - unsloth-q5ks/Qwen3.6-27B-Q5_K_S.gguf"
      echo -e "    - anbeeld-dflash-iq4xs/Qwen3.6-27B-DFlash-IQ4_XS.gguf"
      echo -e "    - mmproj-F16.gguf"
      echo -e "  - Docker:  ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.3.1"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    huggingface-cli download unsloth/Qwen3.6-27B-GGUF --include 'unsloth-q5ks/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      echo -e "    huggingface-cli download Anbeeld/Qwen3.6-27B-DFlash-GGUF --include 'anbeeld-dflash-iq4xs/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      echo -e "    huggingface-cli download unsloth/Qwen3.6-27B-GGUF --include 'mmproj-F16.gguf' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
      ;;
  esac

  # Auto-restart if server is running
  if is_running; then
    echo ""
    echo -e "${YELLOW}Restarting server with new config...${NC}"
    $COMPOSE_BIN -f "$COMPOSE_FILE_OLD" down 2>/dev/null || true
    # Also stop any other known containers
    docker stop vllm-qwen36-nvfp4-mtp vllm-qwen36-nvfp4-tq beellama-qwen36-27b-dflash-vision 2>/dev/null || true
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
  python3 << 'PYEOF'
import yaml
import sys
from pathlib import Path

config_path = Path.home() / ".hermes" / "config.yaml"

with open(config_path) as f:
    config = yaml.safe_load(f) or {}

# ── Model: point to local vLLM ──────────────────────────────────────────────
config.setdefault("model", {})
config["model"]["default"] = "qwen3.6"
config["model"]["provider"] = "custom"
config["model"]["base_url"] = "http://localhost:8020/v1"
config["model"]["api_key"] = "1234"

# ── Custom provider ─────────────────────────────────────────────────────────
config["custom_providers"] = [
    {
        "name": "Local (localhost:8020)",
        "base_url": "http://localhost:8020/v1",
        "api_key": "1234",
        "model": "qwen3.6"
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

print("Done!")
PYEOF

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Hermes config updated!${NC}"
    echo ""
    echo "  Updated settings:"
    echo "    model.default:      qwen3.6"
    echo "    model.provider:     custom"
    echo "    model.base_url:     http://localhost:8020/v1"
    echo "    compression:        85% threshold, 40% target"
    echo "    display:            show_reasoning=true, streaming=true"
    echo "    agent:              env_probe=false, auto_bashrc=false"
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
