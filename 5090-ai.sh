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
#   ./5090-ai.sh bench-concurrent  # concurrent throughput benchmark
#   ./5090-ai.sh bench-scheduling  # scheduling latency benchmark
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

# ── vLLM unified compose helpers ─────────────────────────────────────────────
#
# Single compose/vllm.yml drives all configs via env vars.
# Add a new base model by adding a case here — no new compose files.

export_vllm_vars() {
  local mode="$1"
  # Clear genesis patches first (leftover from previous config)
  export GENESIS_PREALLOC_V2=0 GENESIS_P5B=0 GENESIS_P67=0
  export GENESIS_PN8=0 GENESIS_PN34=0 GENESIS_P82=0 GENESIS_P98=0
  export GENESIS_PN59=0 GENESIS_PN54=0 GENESIS_PN32=0

  case "$mode" in
    text-mtp)
      export CONTAINER_NAME="vllm-text-mtp"
      export MODEL_SUBDIR="aeon-qwen3.6-27b-ultimate-text-nvfp4-mtp-xs"
      export QUANT_MODE="modelopt"
      export MODALITY="text"
      export SPEC_CONFIG='{"method":"qwen3_5_mtp","num_speculative_tokens":3}'
      export CHAT_TEMPLATE_PATH="${ROOT_DIR}/chat-templates/aeon-text/chat_template.jinja"
      export MAX_MODEL_LEN="${MAX_MODEL_LEN:-233472}"
      export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.96}"
      export MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
      export MAX_NUM_BATCHED="${MAX_NUM_BATCHED:-4096}"
      export KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
      ;;
    vision-mtp)
      export CONTAINER_NAME="vllm-vision-mtp"
      export MODEL_SUBDIR="aeon-qwen3.6-27b-ultimate-nvfp4-mtp-xs"
      export QUANT_MODE="modelopt"
      export MODALITY="vision"
      export SPEC_CONFIG='{"method":"qwen3_5_mtp","num_speculative_tokens":3}'
      export CHAT_TEMPLATE_PATH="${ROOT_DIR}/chat-templates/aeon-vision/chat_template.jinja"
      export MAX_MODEL_LEN="${MAX_MODEL_LEN:-212992}"
      export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.94}"
      export MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
      export MAX_NUM_BATCHED="${MAX_NUM_BATCHED:-4096}"
      export KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
      ;;
    vision-tq-mtp)
      export CONTAINER_NAME="vllm-vision-tq-mtp"
      export MODEL_SUBDIR="aeon-qwen3.6-27b-ultimate-nvfp4-mtp-xs"
      export QUANT_MODE="modelopt"
      export MODALITY="vision"
      export SPEC_CONFIG='{"method":"qwen3_5_mtp","num_speculative_tokens":3}'
      export CHAT_TEMPLATE_PATH="${ROOT_DIR}/chat-templates/aeon-vision/chat_template.jinja"
      export MAX_MODEL_LEN="${MAX_MODEL_LEN:-332000}"
      export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.92}"
      export MAX_NUM_SEQS="${MAX_NUM_SEQS:-6}"
      export MAX_NUM_BATCHED="${MAX_NUM_BATCHED:-4096}"
      export KV_CACHE_DTYPE="turboquant_4bit_nc"
      export GENESIS_PREALLOC_V2=1 GENESIS_P5B=1 GENESIS_P67=1 GENESIS_PN8=1
      export GENESIS_PN34=1 GENESIS_P82=1 GENESIS_P98=1
      export GENESIS_PN59=1 GENESIS_PN54=1 GENESIS_PN32=1
      ;;
    huihui-vision-mtp)
      export CONTAINER_NAME="vllm-huihui-vision-mtp"
      export MODEL_SUBDIR="huihui-qwen3.6-27b-abliterated-nvfp4-mtp"
      export QUANT_MODE="modelopt"
      export MODALITY="vision"
      export SPEC_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
      export CHAT_TEMPLATE_PATH="${ROOT_DIR}/chat-templates/huihui/chat_template.jinja"
      export MAX_MODEL_LEN="${MAX_MODEL_LEN:-212992}"
      export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.94}"
      export MAX_NUM_SEQS="${MAX_NUM_SEQS:-10}"
      export MAX_NUM_BATCHED="${MAX_NUM_BATCHED:-4096}"
      export KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8_e4m3}"
      ;;
    huihui-vision-tq-mtp)
      export CONTAINER_NAME="vllm-huihui-vision-tq-mtp"
      export MODEL_SUBDIR="huihui-qwen3.6-27b-abliterated-nvfp4-mtp"
      export QUANT_MODE="modelopt"
      export MODALITY="vision"
      export SPEC_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
      export CHAT_TEMPLATE_PATH="${ROOT_DIR}/chat-templates/huihui/chat_template.jinja"
      export MAX_MODEL_LEN="${MAX_MODEL_LEN:-320000}"
      export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.89}"
      export MAX_NUM_SEQS="${MAX_NUM_SEQS:-4}"
      export MAX_NUM_BATCHED="${MAX_NUM_BATCHED:-3120}"
      export KV_CACHE_DTYPE="turboquant_4bit_nc"
      export GENESIS_PREALLOC_V2=1 GENESIS_P5B=1 GENESIS_P67=1 GENESIS_PN8=1
      export GENESIS_PN34=1 GENESIS_P82=1 GENESIS_P98=1
      export GENESIS_PN59=1 GENESIS_PN54=1 GENESIS_PN32=1
      ;;
  esac
}

# Write vLLM env vars to compose/.env so docker compose -f compose/vllm.yml
# picks them up automatically (docker compose reads .env from file's directory).
save_compose_env() {
  local env_path="${ROOT_DIR}/compose/.env"
  cat > "$env_path" <<EOF
# Generated by 5090-ai.sh — do not edit manually
CONTAINER_NAME=${CONTAINER_NAME}
MODEL_SUBDIR=${MODEL_SUBDIR}
QUANT_MODE=${QUANT_MODE}
MODALITY=${MODALITY}
SPEC_CONFIG=${SPEC_CONFIG}
CHAT_TEMPLATE_PATH=${CHAT_TEMPLATE_PATH}
MAX_MODEL_LEN=${MAX_MODEL_LEN}
GPU_MEMORY_UTIL=${GPU_MEMORY_UTIL}
MAX_NUM_SEQS=${MAX_NUM_SEQS}
MAX_NUM_BATCHED=${MAX_NUM_BATCHED}
KV_CACHE_DTYPE=${KV_CACHE_DTYPE}
GENESIS_PREALLOC_V2=${GENESIS_PREALLOC_V2:-0}
GENESIS_P5B=${GENESIS_P5B:-0}
GENESIS_P67=${GENESIS_P67:-0}
GENESIS_PN8=${GENESIS_PN8:-0}
GENESIS_PN34=${GENESIS_PN34:-0}
GENESIS_P82=${GENESIS_P82:-0}
GENESIS_P98=${GENESIS_P98:-0}
GENESIS_PN59=${GENESIS_PN59:-0}
GENESIS_PN54=${GENESIS_PN54:-0}
GENESIS_PN32=${GENESIS_PN32:-0}
MODEL_DIR=${MODEL_DIR}
EOF
}

# Engine selection (ENGINE may come from .env)
ENGINE="${ENGINE:-text-mtp}"
# Map ENGINE → COMPOSE_FILE + default CONTAINER name.
# NOTE: CONTAINER may later be overridden by .env; the compose file's
# container_name: directive is the source of truth at runtime.
case "$ENGINE" in
  text-mtp|vision-mtp|vision-tq-mtp|huihui-vision-mtp|huihui-vision-tq-mtp)
    # Single unified compose — env vars drive the config
    export_vllm_vars "$ENGINE"
    COMPOSE_FILE="${ROOT_DIR}/compose/vllm.yml"
    save_compose_env
    : "${CONTAINER:=${CONTAINER_NAME}}"
    ;;
  beellama-dflash-vision)
    COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
    : "${CONTAINER:=beellama-qwen36-27b-dflash-vision}"
    ;;
  beellama-qwopus-mtp)
    COMPOSE_FILE="${ROOT_DIR}/compose/beellama/qwopus-mtp-vision.yml"
    : "${CONTAINER:=beellama-qwopus-mtp-vision}"
    ;;
  *)
    echo "Unknown engine: $ENGINE" >&2
    exit 1
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

# Find the actual running vLLM/beellama container name (if any).
# Returns empty string if nothing is running.
find_running_container() {
  docker ps --format '{{.Names}}' --filter "name=vllm" --filter "name=beellama" 2>/dev/null | head -1
}

is_running() {
  local actual
  actual=$(find_running_container)
  [[ -n "$actual" ]]
}

is_ready() {
  # Container running + API responding is sufficient
  local actual
  actual=$(find_running_container)
  [[ -n "$actual" ]] || return 1
  curl -sf "http://localhost:${PORT}/v1/models" >/dev/null 2>&1 || return 1
  return 0
}

# Return the name of the running container, or "$CONTAINER" if none.
# Uses the config EXPECTED name ($CONTAINER) if it matches something running;
# otherwise falls back to the actual running container name.
resolve_container() {
  local expected="$CONTAINER"
  if docker inspect "$expected" >/dev/null 2>&1 && \
     [[ "$(docker inspect --format '{{.State.Running}}' "$expected" 2>/dev/null)" == "true" ]]; then
    echo "$expected"
    return 0
  fi
  find_running_container || echo "$expected"
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
    vision-mtp)  echo "AEON-XS MTP (Vision)" ;;
    vision-tq-mtp)  echo "AEON-XS MTP+TQ (Vision)" ;;
    text-mtp)  echo "AEON-XS MTP (Text)" ;;
    huihui-vision-mtp)  echo "Huihui NVFP4+MTP (Vision)" ;;
    huihui-vision-tq-mtp)  echo "Huihui NVFP4+MTP+TQ (Vision)" ;;
    beellama-dflash-vision)        echo "DFlash Vision" ;;
    beellama-qwopus-mtp)  echo "Qwopus MTP Vision" ;;
    *)               echo "$ENGINE" ;;
  esac
}

header() {
  local label=$(config_label)
  echo -e "  ${CYAN}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}${BOLD}│${NC}  ${BOLD}5090-ai${NC}  ${CYAN}·${NC} ${BOLD}${label}${NC}"
  echo -e "  ${CYAN}${BOLD}│${NC}  ${CYAN}RTX 5090${NC}"
  echo -e "  ${CYAN}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

status_line() {
  local actual_container
  actual_container=$(find_running_container)

  echo -e "  Config:    ${BOLD}$(config_label)${NC} (${ENGINE})"
  echo -e "  Compose:   ${DIM}${COMPOSE_FILE}${NC}"
  echo -e "  Container: ${DIM}$(resolve_container)${NC}"

  if is_running; then
    if is_ready; then
      echo -e "  Status:    ${GREEN}* running${NC}  (model: $(get_model_name), port: ${PORT})"
    else
      echo -e "  Status:    ${YELLOW}~ starting${NC}  (port: ${PORT})"
    fi
    # Warn if running container differs from selected config
    if [[ -n "$actual_container" && "$actual_container" != "$CONTAINER" ]]; then
      echo -e "  ${RED}! Mismatch: running '${actual_container}' ≠ config '${CONTAINER}'${NC}"
    fi
  else
    echo -e "  Status:    ${DIM}o stopped${NC}"
  fi
  echo -e "  GPU:     $(gpu_info)"
  echo -e "  Models:  ${MODEL_DIR}"
  echo ""
}

# ── Actions ──────────────────────────────────────────────────────────────────
get_weights_subdir() {
  case "$ENGINE" in
    text-mtp) echo "aeon-qwen3.6-27b-ultimate-text-nvfp4-mtp-xs" ;;
    huihui-vision-mtp)  echo "huihui-qwen3.6-27b-abliterated-nvfp4-mtp" ;;
    huihui-vision-tq-mtp)  echo "huihui-qwen3.6-27b-abliterated-nvfp4-mtp" ;;
    vision-mtp)  echo "aeon-qwen3.6-27b-ultimate-nvfp4-mtp-xs" ;;
    vision-tq-mtp)  echo "aeon-qwen3.6-27b-ultimate-nvfp4-mtp-xs" ;;
    beellama-qwopus-mtp)  echo "qwopus-3.6-27b-coder-mtp-gguf" ;;
    beellama-dflash-vision)       echo "qwen3.6-27b-gguf" ;;
    *)              echo "qwen3.6-27b-nvfp4-mtp" ;;
  esac
}
WEIGHTS_SUBDIR="$(get_weights_subdir)"
get_hf_repo() {
  case "$ENGINE" in
    vision-mtp)  echo "AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP-XS" ;;
    vision-tq-mtp)  echo "AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP-XS" ;;
    text-mtp) echo "AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Text-NVFP4-MTP-XS" ;;
    huihui-vision-mtp) echo "sakamakismile/Huihui-Qwen3.6-27B-abliterated-NVFP4-MTP" ;;
    huihui-vision-tq-mtp) echo "sakamakismile/Huihui-Qwen3.6-27B-abliterated-NVFP4-MTP" ;;
    beellama-qwopus-mtp) echo "Jackrong/Qwopus3.6-27B-Coder-MTP-GGUF" ;;
    beellama-dflash-vision)       echo "unsloth/Qwen3.6-27B-GGUF" ;;
    *)              echo "sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP" ;;
  esac
}
HF_REPO="$(get_hf_repo)"
HF_URL="https://huggingface.co/${HF_REPO}"

prompt_weights() {
  clear
  header
  echo -e "${YELLOW}${BOLD}Weights not found!${NC}"
  echo ""
  echo -e "  Looking for: ${BOLD}${MODEL_DIR}/${WEIGHTS_SUBDIR}/${NC}"
  echo ""
  case "$ENGINE" in
    vision-mtp|vision-tq-mtp)
      echo -e "  Model: ${BOLD}Qwen3.6-27B AEON Ultimate XS (abliterated + MTP)${NC}"
      ;;
    huihui-vision-mtp|huihui-vision-tq-mtp)
      echo -e "  Model: ${BOLD}Qwen3.6-27B NVFP4 (Huihui abliterated + MTP)${NC}"
      ;;
    *)
      echo -e "  Model: ${BOLD}Qwen3.6-27B-Text-NVFP4-MTP${NC}"
      ;;
  esac
  echo -e "  Size:  ~21 GB (NVFP4 + GDN projections FP4)"
  echo -e "  Link:  ${BLUE}${HF_URL}${NC}"
  echo ""
  echo -e "${BOLD}How would you like to proceed?${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Download from HuggingFace (~19 GB)"
  echo -e "  ${BOLD}2)${NC} Specify existing weights directory"
  echo -e "  ${BOLD}3)${NC} Symlink from another location"
  echo -e "  ${BOLD}0)${NC} Cancel"
  echo ""

  # Auto-detect if hf is available via PATH
  local hf_cmd=""
  if command -v hf &>/dev/null; then
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

  # Auto-detect: if user typed a path instead of a number, treat as option 2
  local _auto_path=""
  if [[ "$wchoice" == /* || "$wchoice" == ~* ]]; then
    _auto_path="$wchoice"
    wchoice="2"
  fi

  case "$wchoice" in
    1)
      # Download from HuggingFace
      echo ""
      if ! $hf_available; then
        echo -e "${RED}✗ hf CLI not found. Please install:${NC}"
        echo -e "  pip install huggingface-hub"
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
      local new_dir
      if [[ -n "${_auto_path:-}" ]]; then
        new_dir="$_auto_path"
        echo ""
        echo -e "  Using path: ${BOLD}${new_dir}${NC}"
      else
        echo ""
        echo -e "  Enter the path where ${BOLD}${WEIGHTS_SUBDIR}/${NC} exists"
        echo -e "  You can enter the parent dir OR the weights dir directly"
        echo -e "  Example: /home/user/models  (contains ${WEIGHTS_SUBDIR}/ subfolder)"
        echo ""
        read -rp "  MODEL_DIR: " new_dir
        new_dir="${new_dir/#\~/$HOME}"
      fi
      
      if [[ -d "${new_dir}/${WEIGHTS_SUBDIR}" ]]; then
        # User entered parent directory (e.g. /home/user/models)
        MODEL_DIR="$new_dir"
        save_env "MODEL_DIR" "$MODEL_DIR"
        echo -e "${GREEN}✓ Weights found! Saved to .env${NC}"
        return 0
      elif [[ -f "${new_dir}/model.safetensors" || -n "$(ls "${new_dir}"/*.gguf 2>/dev/null)" ]]; then
        # User entered the weights directory directly
        local actual_name
        actual_name="$(basename "$new_dir")"
        MODEL_DIR="$(dirname "$new_dir")"
        save_env "MODEL_DIR" "$MODEL_DIR"
        # If directory name doesn't match WEIGHTS_SUBDIR, rename it
        if [[ "$actual_name" != "$WEIGHTS_SUBDIR" ]]; then
          mv "$new_dir" "${MODEL_DIR}/${WEIGHTS_SUBDIR}"
          echo -e "${GREEN}✓ Weights found! Renamed ${actual_name} -> ${WEIGHTS_SUBDIR}${NC}"
        else
          echo -e "${GREEN}✓ Weights found! Saved MODEL_DIR=${MODEL_DIR}${NC}"
        fi
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

  # Print just the current step line (previous steps already on screen)
  show_progress() {
    local cur_idx=$1
    local cur_status=${2:-"..." }
    printf "  [%d/%d] %-6s %s\n" "$((cur_idx+1))" "${#S[@]}" "$cur_status" "${S[$cur_idx]}"
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

  # 0: Already running?  Check expected container name only.
  if docker inspect "$CONTAINER" >/dev/null 2>&1 && \
     [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" == "true" ]]; then
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
    render_step 1
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
    render_step 2
  else
    if cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env" 2>/dev/null; then
      ok 2; D[2]="created from .env.example"
      render_step 2
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
    beellama-dflash-vision)
      local wdir="${MODEL_DIR}/qwen3.6-27b-gguf"
      ;;
    *)
      local wdir="${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      ;;
  esac
  if [[ -d "$wdir" ]] && [[ -f "${wdir}/model.safetensors" || -n "$(ls "${wdir}"/*.gguf 2>/dev/null)" ]]; then
    ok 3; D[3]="$wdir"
  else
    render_step 3
    if prompt_weights; then
      # Re-check after download/setup
      if [[ -d "$wdir" ]] && [[ -f "${wdir}/model.safetensors" || -n "$(ls "${wdir}"/*.gguf 2>/dev/null)" ]]; then
        ok 3; D[3]="$wdir"
      else
        fail 3 "Weights still not found after setup"
        echo ""; _fail_exit 3; return 1
      fi
    else
      fail 3 "Weights not found, setup cancelled"
      echo ""; _fail_exit 3; return 1
    fi
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
  render_step 4
  completed=5

  # 5: Start container
  show_progress 5
  # save_compose_env writes vLLM-specific vars (CONTAINER_NAME, MODEL_SUBDIR, ...).
  # Beellama modes use their own compose files which have inline defaults.
  if [[ "$COMPOSE_FILE" == *"compose/vllm.yml" ]]; then
    save_compose_env
  fi
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
  render_step 5
  completed=6

  # 6: Wait for server
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
    echo -e "  ${BOLD}──────── Container logs (live, Ctrl+C to return) ────────${NC}"
    docker logs -f --tail 20 "$(resolve_container)" 2>&1
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


# Inline progress bar for wait step — shows container logs alongside progress
_wait_for_ready_inline() {
  local elapsed=0
  local bar_width=40
  local log_lines=8  # how many log lines to show

  # Determine which container to watch (actual running one, or config name)
  local cname
  cname=$(resolve_container)

  # Pre-build bar cache
  local -a bc=()
  local i j
  for (( i=0; i<=bar_width; i++ )); do
    local s=""
    for (( j=0; j<i; j++ )); do s+="#"; done
    for (( j=i; j<bar_width; j++ )); do s+="."; done
    bc[$i]="$s"
  done

  # Total lines printed per iteration: 1 progress + 1 blank + log_lines = log_lines+2
  local lines_per_iter=$(( log_lines + 2 ))

  while (( elapsed < 600 )); do
    if is_ready; then
      return 0
    fi

    # Check for crash — use the actual container name for docker inspect
    local restart_count
    restart_count=$(docker inspect --format '{{.RestartCount}}' "$cname" 2>/dev/null || echo "0")
    if (( restart_count > 2 )); then
      echo ""
      echo -e "  ${RED}✗ Container restarting in a loop!${NC}"
      docker logs --tail 10 "$cname" 2>&1 | sed 's/^/    /'
      return 1
    fi

    # Time-based progress
    local pct=$(( elapsed * 80 / 240 ))
    (( pct > 95 )) && pct=95
    local filled=$(( pct * bar_width / 100 ))
    (( filled > bar_width )) && filled=$bar_width
    local bar_str="${bc[$filled]}"
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    # On subsequent iterations, move cursor up to overwrite previous block
    if (( elapsed > 0 )); then
      printf "\033[%dA\033[J" "$lines_per_iter"
    fi

    # Progress bar line
    printf "  [7/7] \033[33m...\033[0m Waiting... [\033[36m%s\033[0m] %3d%% [%dm%02ds]\n" \
      "$bar_str" "$pct" "$mins" "$secs"
    echo ""

    # Print exactly log_lines of container output (pad/truncate to keep position stable)
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 100)
    local line_width=$(( term_width - 3 ))  # 2 indent + 1 margin
    local line_idx=0
    while IFS= read -r line; do
      if (( line_idx < log_lines )); then
        # Truncate to fit terminal width (prevents line-wrap chaos)
        printf "  %.${line_width}s\n" "$line"
        (( line_idx++ ))
      fi
    done < <(docker logs --tail "$log_lines" "$cname" 2>&1)
    # Pad remaining lines if docker output was short
    while (( line_idx < log_lines )); do
      echo ""
      (( line_idx++ ))
    done

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

  # Stop EVERY vLLM/beellama container — regardless of what $CONTAINER says.
  # This handles config-mismatch cases cleanly.
  local any
  any=$(docker ps -q --filter "name=vllm" --filter "name=beellama" 2>/dev/null || true)
  if [[ -n "$any" ]]; then
    for cid in $any; do
      local cname
      cname=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
      echo -e "  ${YELLOW}Stopping ${cname}${NC}"
      docker stop --time 5 "$cid" >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}✓ Stopped${NC}"
  else
    echo -e "${DIM}Already stopped${NC}"
  fi
}

do_status() {
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 100)
  local max_log_width=$(( term_width - 6 ))
  local actual

  while true; do
    clear
    header
    status_line

    if is_running; then
      actual=$(resolve_container)
      echo -e "  ${BOLD}Container:${NC}"
      docker stats "$actual" --no-stream --format "    CPU: {{.CPUPerc}}  MEM: {{.MemUsage}}  NET: {{.NetIO}}" 2>/dev/null || true
      echo ""

      echo -e "  ${BOLD}GPU:${NC}"
      nvidia-smi --query-gpu=index,name,temperature.gpu,power.draw,memory.used,memory.total,utilization.gpu \
                 --format=csv,noheader,nounits 2>/dev/null | \
        awk -F', ' '{printf "    #%s  %s  %s°C  %sW  %s/%s MiB  %s%% util\n", $1, $2, $3, $4, $5, $6, $7}' || echo "    n/a"
      echo ""

      echo -e "  ${BOLD}Recent logs:${NC}"
      docker logs --tail 8 "$actual" 2>&1 | sed 's/^/    /' | tail -8
    else
      echo -e "  ${YELLOW}Container not running${NC}"
    fi

    echo ""
    echo -e "  ${DIM}[Ctrl+C to exit]${NC}"
    sleep 3
  done
}

do_logs() {
  local actual
  actual=$(find_running_container)
  if [[ -z "$actual" ]]; then
    echo -e "${RED}✗ Not running${NC}"
    return 1
  fi
  echo -e "${BLUE}[log] Logs (Ctrl+C to stop):${NC}"
  docker logs -f --tail 50 "$actual"
}

do_bench() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  local actual
  actual=$(resolve_container)
  echo ""
  echo -e "${BOLD}Benchmark mode:${NC}"
  echo "  1) Sequential       (single request latency)"
  echo "  2) Concurrent       (throughput ceiling)"
  echo "  3) Scheduling        (decode + new prefill overlap)"
  echo "  4) Ctx Level Stress  (mixed context sizes, concurrent pairs)"
  echo ""
  read -rp "  Choice [1]: " bm_choice
  case "${bm_choice:-1}" in
    2) CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-concurrent.sh" ;;
    3) CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-scheduling.sh" ;;
    4) CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-ctx-levels.sh" ;;
    *) CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench.sh" ;;
  esac
}

do_bench_concurrent() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  local actual
  actual=$(resolve_container)
  CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-concurrent.sh"
}

do_bench_scheduling() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  local actual
  actual=$(resolve_container)
  CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-scheduling.sh"
}

do_bench_ctx_levels() {
  if ! is_ready; then
    echo -e "${RED}✗ Server not ready${NC}"
    return 1
  fi
  local actual
  actual=$(resolve_container)
  CONTAINER="$actual" bash "${ROOT_DIR}/scripts/bench-ctx-levels.sh"
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
  clear
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
  clear
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
  clear
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
  local configs=(
    "vision-mtp"
    "vision-tq-mtp"
    "text-mtp"
    "huihui-vision-mtp"
    "huihui-vision-tq-mtp"
    "beellama-dflash-vision"
    "beellama-qwopus-mtp"
  )
  local labels=(
    "Engine: vLLM · KV: fp8_e4m3 · Ctx: 208K · MTP3 · Vision · AEON-XS"
    "Engine: vLLM · KV: turboquant · Ctx: 324K · MTP3 · Vision · AEON-XS · Genesis"
    "Engine: vLLM · KV: fp8_e4m3 · Ctx: 228K · MTP3 · Text · AEON-XS"
    "Engine: vLLM · KV: fp8_e4m3 · Ctx: 208K · MTP3 · Vision · Huihui [deprecated]"
    "Engine: vLLM · KV: turboquant · Ctx: 312K · MTP3 · Vision · P5b+P67+PN8+PN32+PN34+P54+P59+P82 · Huihui [deprecated]"
    "Engine: beellama.cpp · KV: q5_0/q4_1 · Ctx: 262K · DFlash · Vision"
    "Engine: beellama.cpp · MTP · Ctx: 262K · Q4_K_M · Vision · Coder · no-thinking"
  )
  local selected=0
  local config_count=${#configs[@]}
  local choice

  tput civis 2>/dev/null || true

  while true; do
    header
    echo -e "${BOLD}Select Configuration${NC}"
    echo ""
    echo -e "  ${DIM}Current: ${ENGINE}${NC}"
    echo ""
    echo -e "  ${CYAN}★${NC} ${CYAN}production-ready${NC}  ·  ${DIM}dim = experimental${NC}"
    echo ""
    echo -e "  ─────────────────────────────────────────────────────────────"
    echo ""

    for i in "${!configs[@]}"; do
      local cfg="${configs[$i]}"
      if (( i == selected )); then
        echo -e "  ${GREEN}${BOLD}▸ ${cfg}${NC}"
        echo -e "     ${GREEN}${labels[$i]}${NC}"
      elif [[ "$cfg" == aeon-* ]]; then
        echo -e "  ${CYAN}  ${cfg}${NC} ${CYAN}★${NC}"
        echo -e "     ${CYAN}${labels[$i]}${NC}"
      else
        echo -e "    ${DIM}${cfg}${NC}"
        echo -e "     ${DIM}${labels[$i]}${NC}"
      fi
      echo ""
    done

    echo -e "  ─────────────────────────────────────────────────────────────"
    echo ""
    echo -e "  ${DIM}[↑↓] move  [Enter] select  [q] quit${NC}"
    echo ""

    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.1 key2
        case "$key2" in
          '[A') selected=$(( (selected - 1 + config_count) % config_count )) ;;
          '[B') selected=$(( (selected + 1) % config_count )) ;;
        esac
        ;;
      '')
        choice="${configs[$selected]}"
        break
        ;;
      q|Q)
        tput cnorm 2>/dev/null || true
        return 0
        ;;
    esac
  done

  tput cnorm 2>/dev/null || true
  local COMPOSE_FILE_OLD="$COMPOSE_FILE"

  case "$choice" in
    text-mtp|vision-mtp|vision-tq-mtp|huihui-vision-mtp|huihui-vision-tq-mtp)
      ENGINE="$choice"
      save_env "ENGINE" "$choice"
      export_vllm_vars "$choice"
      save_env "CONTAINER" "${CONTAINER_NAME}"
      save_compose_env
      COMPOSE_FILE="${ROOT_DIR}/compose/vllm.yml"
      CONTAINER="${CONTAINER_NAME}"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to $(config_label)${NC}"
      ;;
    beellama-dflash-vision)
      ENGINE="beellama-dflash-vision"
      save_env "ENGINE" "beellama-dflash-vision"
      save_env "CONTAINER" "beellama-qwen36-27b-dflash-vision"
      COMPOSE_FILE="${ROOT_DIR}/compose/beellama/dflash-vision.yml"
      CONTAINER="beellama-qwen36-27b-dflash-vision"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to Beellama DFlash Vision${NC}"
      ;;
    beellama-qwopus-mtp)
      ENGINE="beellama-qwopus-mtp"
      save_env "ENGINE" "beellama-qwopus-mtp"
      save_env "CONTAINER" "beellama-qwopus-mtp-vision"
      COMPOSE_FILE="${ROOT_DIR}/compose/beellama/qwopus-mtp-vision.yml"
      CONTAINER="beellama-qwopus-mtp-vision"
      WEIGHTS_SUBDIR="$(get_weights_subdir)"
      echo ""
      echo -e "${GREEN}✓ Switched to Qwopus MTP Vision${NC}"
      ;;
  esac

  echo ""
  echo -e "  ${BOLD}Requirements:${NC}"
  case "$ENGINE" in
    text-mtp|huihui-vision-mtp|huihui-vision-tq-mtp|vision-mtp|vision-tq-mtp)
      echo -e "  - Weights: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
      echo -e "  - Docker:  vllm/vllm-openai:v0.23.0"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      echo -e "    hf download ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}"
      echo -e "    ${DIM}Fallback: modelscope download --model ${HF_REPO} --local-dir ${MODEL_DIR}/${WEIGHTS_SUBDIR}${NC}"
      ;;
    beellama-dflash-vision|beellama-qwopus-mtp)
      echo -e "  - Weights: ${MODEL_DIR}/${WEIGHTS_SUBDIR}/"
      echo -e "  - Docker:  ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.3.1"
      echo ""
      echo -e "  ${DIM}Download:${NC}"
      case "$ENGINE" in
        beellama-dflash-vision)
          echo -e "    hf download unsloth/Qwen3.6-27B-GGUF --include 'unsloth-q5ks/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
          echo -e "    hf download Anbeeld/Qwen3.6-27B-DFlash-GGUF --include 'anbeeld-dflash-iq4xs/*' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
          echo -e "    hf download unsloth/Qwen3.6-27B-GGUF --include 'mmproj-F16.gguf' --local-dir ${MODEL_DIR}/qwen3.6-27b-gguf"
          ;;
        beellama-qwopus-mtp)
          echo -e "    hf download Jackrong/Qwopus3.6-27B-Coder-MTP-GGUF --include 'Q4_K_M*' --include 'mmproj*' --local-dir ${MODEL_DIR}/qwopus-3.6-27b-coder-mtp-gguf"
          echo -e "    ${DIM}Fallback: modelscope download --model Jackrong/Qwopus3.6-27B-Coder-MTP-GGUF --include 'Q4_K_M*' --include 'mmproj*' --local-dir ${MODEL_DIR}/qwopus-3.6-27b-coder-mtp-gguf${NC}"
          ;;
      esac
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
  clear
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

# ── Configure SOUL.md ─────────────────────────────────────────────────────────
do_configure_soul() {
  clear
  local soul_path="${HOME}/.hermes/SOUL.md"

  header
  echo -e "${BOLD}Configure SOUL.md (Kawaii Personality)${NC}"
  echo ""

  # Show current state
  if [[ -L "$soul_path" ]]; then
    echo -e "  Current: ${BOLD}symlink${NC} -> $(readlink "$soul_path")"
  elif [[ -f "$soul_path" ]]; then
    echo -e "  Current: ${BOLD}regular file${NC}"
  else
    echo -e "  Current: ${YELLOW}not found${NC}"
  fi
  echo ""

  # Backup existing SOUL.md if it exists
  if [[ -e "$soul_path" ]]; then
    local bk_path="${soul_path}.bk"
    cp -p "$soul_path" "$bk_path"
    echo -e "  ${GREEN}✓ Backed up to ${bk_path}${NC}"
  fi
  echo ""

  # Overwrite with Kawaii personality (works for both symlink and regular file)
  cat > "$soul_path" << 'SOULEOF'
# Kawaii Personality

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
SOULEOF

  echo -e "  ${GREEN}✓ SOUL.md configured!${NC}"
  echo ""
  echo -e "  Restart Hermes to apply:"
  echo -e "    hermes gateway restart"
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
  "[soul] Configure SOUL.md"
)
MENU_ACTIONS=(do_up do_down do_status do_logs do_bench do_test do_model do_select_config do_config do_install do_install_hermes do_configure_hermes do_configure_soul)

draw_menu() {
  local selected=$1
  local i
  local keys=("1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d")
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
  echo -e "  ${DIM}[↑↓] move  [Enter] select  [1-9/a-f] direct  [q/0] quit${NC}"
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
    bench-scheduling|bench-s)  do_bench_scheduling ;;
    bench-ctx-levels|bench-x)  do_bench_ctx_levels ;;
    test)         do_test ;;
    model)        do_model ;;
    config)       do_config ;;
    *)            echo "Usage: $0 {up|down|status|logs|bench|bench-concurrent|bench-scheduling|test|model|config}"; exit 1 ;;
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
    a|A) # Key 'a' for 10th item (Select Config)
      selected=9
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    b|B) # Key 'b' for 11th item (Config .env)
      selected=10
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    c|C) # Key 'c' for 12th item (Install 5090-ai)
      selected=11
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    d|D) # Key 'd' for 13th item (Install Hermes)
      selected=12
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    e|E) # Key 'e' for 14th item (Configure Hermes)
      selected=13
      ${MENU_ACTIONS[$selected]}
      read -rp "  Press Enter to continue..."
      need_clear=1
      ;;
    f|F) # Key 'f' for 15th item (Configure SOUL.md)
      selected=14
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
