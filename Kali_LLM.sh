#!/bin/bash
# ==============================================================================
# Script Name: Kali_LLM.sh
# Version: V1.0
# Developer: 0X001337
# Description: Enterprise-grade Local LLM + MCP Installer for Kali Linux
# ==============================================================================

set -o pipefail

# --- ANSI Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# --- Global Configuration ---
SCRIPT_VERSION="V1.0"
LOG_FILE="/var/log/kali_llm_install.log"
OLLAMA_BASE="/srv/ollama_bin"
OLLAMA_MODELS_DIR="/srv/ollama_models"
MODELS_TEMP="/srv/models_temp"
FIVEIRE_DIR="/opt/5ire"
FIVEIRE_BIN="/usr/local/bin/5ire"

# --- Logging ---
log() {
    local level="$1"; shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" >> "$LOG_FILE" 2>/dev/null
}

# --- UI Helpers ---
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║            🦾 KALI LINUX LOCAL LLM INSTALLER 🦾                ║"
    echo "║      Ollama + 5ire + MCP Server + NVIDIA GPU Optimized         ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo -e "║  ${NC}${BLUE}Developer:${NC} 0X001337                                           ${CYAN}║"
    echo -e "║  ${NC}${BLUE}Version:${NC}   $SCRIPT_VERSION                                               ${CYAN}║"
    echo -e "║  ${NC}${BLUE}Log File:${NC}  $LOG_FILE                      ${CYAN}║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo -e "║  ${NC}${MAGENTA}${BOLD}📊 SYSTEM SPECIFICATIONS${NC}                                      ${CYAN}║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    
    # OS Info with Version
    local os_name=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    local os_version=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    echo -e "║  ${NC}${BOLD}OS:${NC}    ${os_name:-Unknown Linux} ${os_version:-}                          ${CYAN}║"
    
    # RAM Info
    local total_ram=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    echo -e "║  ${NC}${BOLD}RAM:${NC}   ${total_ram:-Unknown} Total                                             ${CYAN}║"
    
    # GPU Info
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
        local gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
        echo -e "║  ${NC}${BOLD}GPU:${NC}   ${gpu_name:-Unknown}                                ${CYAN}║"
        echo -e "║  ${NC}${BOLD}VRAM:${NC}  ${gpu_vram:-Unknown} MiB                                               ${CYAN}║"
    else
        echo -e "║  ${NC}${BOLD}GPU:${NC}   No NVIDIA GPU Detected (CPU Mode)                    ${CYAN}║"
        echo -e "║  ${NC}${BOLD}VRAM:${NC}  N/A                                                ${CYAN}║"
    fi
    
    # Close the main banner frame
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # --- System Status WITHOUT frame ---
    echo -e "${MAGENTA}${BOLD}⚙️  SYSTEM STATUS${NC}"
    
    # Ollama Status
    if [ -x "$OLLAMA_BASE/bin/ollama" ]; then
        local o_ver=$(ollama --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
        echo -e "  ${BOLD}Ollama:${NC}        ${GREEN}[✓]${NC} Installed (v${o_ver})"
    else
        echo -e "  ${BOLD}Ollama:${NC}        ${RED}[✗]${NC} Missing"
    fi

    # 5ire Status
    if [ -x "$FIVEIRE_DIR/5ire.AppImage" ]; then
        echo -e "  ${BOLD}5ire:${NC}          ${GREEN}[✓]${NC} Installed (/opt/5ire)"
    else
        echo -e "  ${BOLD}5ire:${NC}          ${RED}[✗]${NC} Missing"
    fi

    # MCP API Status
    if systemctl is-active --quiet kali-mcp-api.service 2>/dev/null; then
        echo -e "  ${BOLD}MCP API:${NC}       ${GREEN}[✓]${NC} Running (Port 5000)"
    else
        echo -e "  ${BOLD}MCP API:${NC}       ${RED}[✗]${NC} Stopped"
    fi

    # Storage Status
    local usage=$(du -sh "$OLLAMA_MODELS_DIR" 2>/dev/null | cut -f1)
    local free=$(df -h /srv 2>/dev/null | awk 'NR==2{print $4}')
    [ -z "$usage" ] && usage="0B"
    [ -z "$free" ] && free="N/A"
    echo -e "  ${BOLD}Storage:${NC}       ${usage} used / ${free} free on /srv"
    echo ""
}

print_info()    { echo -e "${BLUE}[ℹ]${NC} $*"; }
print_success() { echo -e "${GREEN}[✓]${NC} $*"; }
print_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
print_error()   { echo -e "${RED}[✗]${NC} $*"; }
print_step()    { echo -e "\n${MAGENTA}${BOLD}▶ $*${NC}"; }

# --- Zsh/Bash Compatible Read ---
read_input() {
    local prompt_msg="$1"; local var_name="$2"
    echo -ne "$prompt_msg"
    read -r "$var_name"
}

# --- Input Sanitization ---
# Strips shell metacharacters (command substitution, pipes, redirection, globbing)
# so a value can be safely interpolated into an su -c string.
sanitize_input() {
    echo "$1" | sed 's/[;&|`$(){}<>*?!\\]//g' | tr -d '\n\r'
}

# --- Strict allow-list validators (defence in depth) ---
# Ollama model reference, e.g. qwen2.5:7b or myorg/model:tag
valid_model_ref() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$ ]]
}

# --- Ollama version gate: succeeds when installed ollama >= $1 (e.g. 0.17.1) ---
# Newer architectures (e.g. qwen35) ship their tool renderer/parser INSIDE Ollama
# and declare a minimum version, so importing/pulling them needs a recent Ollama.
ollama_version_at_least() {
    local need="$1" have
    have=$(ollama --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
    [ -z "$have" ] && return 1
    # have >= need  <=>  the smaller of {need,have} sorts to 'need'
    [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n 1)" = "$need" ]
}

# ==============================================================================
# CRITICAL HELPER: Ensure Ollama Server is Running
# ==============================================================================
ensure_ollama_running() {
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        return 0
    fi
    print_info "Starting Ollama server temporarily..."
    su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && nohup $OLLAMA_BASE/bin/ollama serve > /tmp/ollama.log 2>&1 &"
    local i
    for i in $(seq 1 15); do
        if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
            print_success "Ollama server started successfully"
            return 0
        fi
        sleep 1
    done
    print_error "Failed to start Ollama server (see /tmp/ollama.log)"
    return 1
}

# --- Prerequisites ---
prerequisites_check() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    REAL_USER=${SUDO_USER:-$USER}
    REAL_HOME=$(eval echo "~$REAL_USER")
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/kali_llm_install.log"
    log "INFO" "Script started by user: $REAL_USER"
}

# --- Dependency Check ---
check_dependencies() {
    print_step "Checking system dependencies"
    # Map required command -> providing apt package (they are not always identical).
    declare -A dep_pkg=(
        [curl]=curl [wget]=wget [tar]=tar [zstd]=zstd
        [pgrep]=procps [free]=procps
        [lshw]=lshw [awk]=gawk [sed]=sed [bc]=bc
    )
    local missing_pkgs=()
    local cmd
    for cmd in "${!dep_pkg[@]}"; do
        command -v "$cmd" &> /dev/null || missing_pkgs+=("${dep_pkg[$cmd]}")
    done
    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        # De-duplicate package list (e.g. procps requested twice).
        local unique_pkgs
        unique_pkgs=$(printf '%s\n' "${missing_pkgs[@]}" | sort -u | tr '\n' ' ')
        print_error "Missing packages: $unique_pkgs"
        print_info "Installing missing packages..."
        if apt update -qq >> "$LOG_FILE" 2>&1 && apt install -y $unique_pkgs >> "$LOG_FILE" 2>&1; then
            print_success "Dependencies installed"
        else
            print_error "Failed to install dependencies. See $LOG_FILE"
            return 1
        fi
    else
        print_success "All dependencies satisfied"
    fi
}

# ==============================================================================
# PHASE 1: OS & GPU VALIDATION
# ==============================================================================
validate_environment() {
    print_banner
    print_step "Phase 1: Environment Validation"
    if ! grep -qi "kali" /etc/os-release; then
        print_error "This script is designed for Kali Linux only"
        exit 1
    fi
    print_success "Kali Linux detected"
    
    if ! command -v nvidia-smi &> /dev/null || ! nvidia-smi &> /dev/null; then
        print_warn "NVIDIA driver not detected or not functional"
        read_input "${CYAN}Install NVIDIA drivers now? (requires reboot) [y/N]: ${NC}" install_gpu
        if [[ "$install_gpu" =~ ^[Yy]$ ]]; then
            print_step "Installing NVIDIA drivers..."
            apt update -qq
            apt install -y linux-image-$(dpkg --print-architecture) linux-headers-$(dpkg --print-architecture) nvidia-driver nvidia-smi | tee -a "$LOG_FILE"
            # ${PIPESTATUS[0]} = apt's exit code (not tee's) so a failed install does not trigger a reboot.
            if [ "${PIPESTATUS[0]}" -ne 0 ]; then
                print_error "Driver installation failed. See $LOG_FILE. Not rebooting."
                exit 1
            fi
            print_warn "═══════════════════════════════════════════════════════════"
            print_warn "  REBOOT REQUIRED. System will reboot in 15 seconds."
            print_warn "  (Press Ctrl+C to cancel and reboot manually)"
            print_warn "═══════════════════════════════════════════════════════════"
            sleep 15
            reboot
        else
            print_error "Exiting. Please install GPU drivers manually."
            exit 0
        fi
    else
        print_success "NVIDIA GPU validated and ready"
    fi
}

# ==============================================================================
# PHASE 2: WORKSPACE SETUP
# ==============================================================================
setup_workspace() {
    print_step "Phase 2: Workspace Preparation"
    local dirs=("$OLLAMA_BASE" "$OLLAMA_MODELS_DIR" "$MODELS_TEMP" "$FIVEIRE_DIR")
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_success "Created: $dir"
        fi
    done
    chown -R "$REAL_USER:$REAL_USER" "$OLLAMA_BASE" "$OLLAMA_MODELS_DIR" "$MODELS_TEMP" "$FIVEIRE_DIR" 2>/dev/null || true
    print_success "Workspace ready at /srv"
}

# ==============================================================================
# PHASE 3: OLLAMA INSTALLATION
# ==============================================================================
install_ollama() {
    print_step "Phase 3: Ollama Installation"
    if [ -x "$OLLAMA_BASE/bin/ollama" ]; then
        read_input "${YELLOW}Ollama already installed. Reinstall? [y/N]: ${NC}" reinstall
        [[ "$reinstall" =~ ^[Yy]$ ]] || return 0
    fi
    
    print_info "Downloading Ollama to /tmp..."
    curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst -o /tmp/ollama-linux-amd64.tar.zst || { print_error "Download failed"; return 1; }
    
    print_info "Extracting to $OLLAMA_BASE..."
    tar x -v --zstd -C "$OLLAMA_BASE" -f /tmp/ollama-linux-amd64.tar.zst 2>&1 | tail -n 5
    rm -f /tmp/ollama-linux-amd64.tar.zst
    ln -sf "$OLLAMA_BASE/bin/ollama" /usr/local/bin/ollama
    
    if [ -x "/usr/local/bin/ollama" ]; then
        print_success "Ollama installed: $(ollama --version 2>/dev/null)"
    else
        print_error "Installation verification failed"
    fi
}

# ==============================================================================
# PHASE 4: MODEL DOWNLOAD (Advanced & Reliable)
# ==============================================================================
download_models() {
    while true; do
        clear; print_banner
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${BOLD}                      MODEL MANAGEMENT                       ${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[1]${NC} Download from Ollama Library (Recommended)             ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[2]${NC} Download from Hugging Face GGUF (Advanced)             ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[3]${NC} List installed models                                  ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[4]${NC} Remove a model                                         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Back to Main Menu                                      ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-4]: ${NC}" model_choice
        
        case $model_choice in
            0) return 0 ;;
            1) download_from_ollama ;;
            2) download_from_huggingface ;;
            3) list_installed_models ;;
            4) remove_model ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

download_from_ollama() {
    clear; print_banner
    print_step "Download from Ollama Library"
    echo -e "${BLUE}Browse available models at:${NC}"
    echo -e "${CYAN}https://ollama.com/library${NC}"
    echo ""
    echo -e "${YELLOW}Examples (Tools-capable models):${NC}"
    echo "  • qwen3.5:4b         (Tools model, ~3.4GB)"
    echo "  • qwen3.5:9b         (Tools model, ~6.6GB)"
    echo "  • ornith:9b          (Tools model, ~5.6GB)"
    echo "  • lfm2.5:8b          (Tools model, ~5.2GB)"
    echo "  • llama3.1:8b        (Tools model, ~4.9GB)  [Kali guide]"
    echo "  • llama3.2:3b        (Tools model, ~2.0GB)  [Kali guide]"
    echo "  • qwen3:4b           (Tools model, ~2.5GB)  [Kali guide]"
    echo ""

    read_input "${CYAN}Enter model name (e.g., qwen3:4b ): ${NC}" model_name
    model_name=$(sanitize_input "$model_name")
    
    if [ -z "$model_name" ]; then
        print_error "Model name cannot be empty"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy
        return 1
    fi
    if ! valid_model_ref "$model_name"; then
        print_error "Invalid model name. Allowed: letters, numbers, . _ : / -"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy
        return 1
    fi

    ensure_ollama_running || { read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1; }

    print_info "Pulling model: $model_name ..."
    if su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama pull $model_name"; then
        print_success "Model '$model_name' downloaded successfully"
        log "INFO" "Ollama model pulled: $model_name"
    else
        print_error "Failed to pull model"
        log "ERROR" "Failed to pull: $model_name"
    fi
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ---------- Shared: append a tool-capable TEMPLATE to ./Modelfile ----------
# Usage: hf_write_template <chatml|llama3|none|auto>
hf_write_template() {
    case "$1" in
        chatml)
            # Official Ollama Qwen2.5 template with tool-calling support.
            cat >> Modelfile << 'TEOF'
PARAMETER stop "<|im_start|>"
PARAMETER stop "<|im_end|>"
TEMPLATE """{{- if .Messages }}
{{- if or .System .Tools }}<|im_start|>system
{{- if .System }}
{{ .System }}
{{- end }}
{{- if .Tools }}

# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{{- range .Tools }}
{"type": "function", "function": {{ .Function }}}
{{- end }}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>
{{- end }}<|im_end|>
{{ end }}
{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 -}}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
{{ if .Content }}{{ .Content }}
{{- else if .ToolCalls }}<tool_call>
{{ range .ToolCalls }}{"name": "{{ .Function.Name }}", "arguments": {{ .Function.Arguments }}}
{{ end }}</tool_call>
{{- end }}{{ if not $last }}<|im_end|>
{{ end }}
{{- else if eq .Role "tool" }}<|im_start|>user
<tool_response>
{{ .Content }}
</tool_response><|im_end|>
{{ end }}
{{- if and (ne .Role "assistant") $last }}<|im_start|>assistant
{{ end }}
{{- end }}
{{- else }}
{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
{{ end }}{{ .Response }}{{ if .Response }}<|im_end|>{{ end }}"""
TEOF
            print_success "Using ChatML/Qwen tool-capable template"
            ;;
        llama3)
            # Official Ollama Llama 3.1 template with tool-calling support.
            cat >> Modelfile << 'TEOF'
PARAMETER stop "<|start_header_id|>"
PARAMETER stop "<|end_header_id|>"
PARAMETER stop "<|eot_id|>"
TEMPLATE """{{- if or .System .Tools }}<|start_header_id|>system<|end_header_id|>
{{- if .System }}

{{ .System }}
{{- end }}
{{- if .Tools }}

Cutting Knowledge Date: December 2023

When you receive a tool call response, use the output to format an answer to the original user question.

You are a helpful assistant with tool calling capabilities.
{{- end }}<|eot_id|>
{{- end }}
{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 }}
{{- if eq .Role "user" }}<|start_header_id|>user<|end_header_id|>
{{- if and $.Tools $last }}

Given the following functions, please respond with a JSON for a function call with its proper arguments that best answers the given prompt.

Respond in the format {"name": function name, "parameters": dictionary of argument name and its value}. Do not use variables.

{{ range $.Tools }}
{{- . }}
{{ end }}
{{ .Content }}<|eot_id|>
{{- else }}

{{ .Content }}<|eot_id|>
{{- end }}{{ if $last }}<|start_header_id|>assistant<|end_header_id|>

{{ end }}
{{- else if eq .Role "assistant" }}<|start_header_id|>assistant<|end_header_id|>
{{- if .ToolCalls }}
{{ range .ToolCalls }}
{"name": "{{ .Function.Name }}", "parameters": {{ .Function.Arguments }}}{{ end }}
{{- else }}

{{ .Content }}
{{- end }}{{ if not $last }}<|eot_id|>{{ end }}
{{- else if eq .Role "tool" }}<|start_header_id|>ipython<|end_header_id|>

{{ .Content }}<|eot_id|>{{ if $last }}<|start_header_id|>assistant<|end_header_id|>

{{ end }}
{{- end }}
{{- end }}"""
TEOF
            print_success "Using Llama 3.x tool-capable template"
            ;;
        renderer:*)
            # Modern archs (Qwen3.5, Ornith, LFM2.5, DeepSeek, GLM...) ship their tool-calling
            # RENDERER + PARSER inside Ollama. `ollama create` from a raw GGUF does NOT
            # apply them automatically (ollama/ollama#17636), so we set them explicitly.
            # This is what makes tool-calling actually work — not a text TEMPLATE.
            # Arg form: "renderer:<name>" (same for both) or "renderer:<render>,<parser>"
            # (some models differ, e.g. LFM2.5 = lfm2 / lfm2-thinking).
            local spec="${1#renderer:}" rname pname
            rname="${spec%%,*}"
            if [[ "$spec" == *,* ]]; then pname="${spec#*,}"; else pname="$rname"; fi
            {
                echo "RENDERER $rname"
                echo "PARSER $pname"
            } >> Modelfile
            print_success "Using Ollama built-in renderer '$rname' + parser '$pname'"
            ;;
        none)
            print_warn "No template set (text-only model)"
            ;;
        *)
            print_info "Using the GGUF's embedded template (Auto)"
            ;;
    esac
}

# ---------- Core builder: download GGUF, build Modelfile, create Ollama model ----------
# Usage: hf_build_model <repo> <gguf_file> <ollama_name> <tmpl> <detect_mmproj:yes|no>
hf_build_model() {
    local hf_repo="$1" hf_file="$2" ollama_name="$3" tmpl="$4" detect_mmproj="$5"

    mkdir -p "$MODELS_TEMP"
    cd "$MODELS_TEMP" || { print_error "Cannot access $MODELS_TEMP (run option [1] first)"; return 1; }

    print_info "Downloading GGUF: $hf_file ..."
    if ! wget -q --show-progress "https://huggingface.co/$hf_repo/resolve/main/$hf_file"; then
        print_error "Download failed. Verify the repo and filename exist."
        log "ERROR" "HF download failed: $hf_repo/$hf_file"
        return 1
    fi

    local mmproj_file=""
    if [ "$detect_mmproj" = "yes" ]; then
        local base_name="${hf_file%.gguf}"
        print_info "Checking for vision projector (mmproj)..."
        for candidate in "mmproj-${base_name}.gguf" "mmproj-${base_name}-f16.gguf" "mmproj-${base_name}-F16.gguf" "mmproj-F16.gguf" "mmproj-F32.gguf" "mmproj-BF16.gguf" "mmproj-model-f16.gguf"; do
            # -L follows HF's redirect to the CDN; match the HTTP/1.x or HTTP/2 200 status line.
            if curl -sIL "https://huggingface.co/$hf_repo/resolve/main/$candidate" | grep -qiE "^HTTP/.* 200"; then
                mmproj_file="$candidate"
                break
            fi
        done
        if [ -n "$mmproj_file" ]; then
            print_success "Vision projector detected: $mmproj_file"
            wget -q --show-progress "https://huggingface.co/$hf_repo/resolve/main/$mmproj_file"
        else
            print_warn "No mmproj file found (text-only model)"
        fi
    fi

    print_info "Generating Modelfile..."
    {
        echo "FROM ./$hf_file"
        [ -n "$mmproj_file" ] && echo "FROM ./$mmproj_file"
        echo 'PARAMETER num_ctx 4096'
        if [ "$tmpl" = "renderer:qwen3.5" ]; then
            # Qwen3.5 (thinking) recommended sampling, matching the official Ollama model.
            echo 'PARAMETER temperature 1.0'
            echo 'PARAMETER top_p 0.95'
            echo 'PARAMETER top_k 20'
            echo 'PARAMETER presence_penalty 1.5'
        else
            echo 'PARAMETER temperature 0.7'
            echo 'PARAMETER top_p 0.8'
        fi
    } > Modelfile
    hf_write_template "$tmpl"

    ensure_ollama_running || return 1

    print_info "Building model in Ollama as '$ollama_name'..."
    if su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama create $ollama_name -f $MODELS_TEMP/Modelfile"; then
        print_success "Model '$ollama_name' created successfully"
        log "INFO" "HF model created: $ollama_name"
    else
        print_error "Model build failed. Check Modelfile syntax."
        log "ERROR" "Model build failed: $ollama_name"
    fi

    print_info "Cleaning up temporary files..."
    rm -f "$hf_file" "$mmproj_file" Modelfile
    return 0
}

# ---------- Quantization chooser (sets global HF_QUANT; default Q4_K_M) ----------
hf_choose_quant() {
    HF_QUANT="Q4_K_M"
    echo ""
    echo -e "${YELLOW}Quantization (quality vs size):${NC}"
    echo -e "  ${GREEN}[1]${NC} Q4_K_M  (default — best balance)"
    echo -e "  ${GREEN}[2]${NC} Q5_K_M  (higher quality, larger)"
    echo -e "  ${GREEN}[3]${NC} Q6_K    (near-Q8 quality)"
    echo -e "  ${GREEN}[4]${NC} Q8_0    (near-lossless, large)"
    echo -e "  ${GREEN}[5]${NC} Q3_K_M  (smaller, lower quality)"
    echo -e "  ${GREEN}[6]${NC} BF16    (full precision, very large)"
    read_input "${CYAN}Choose [1-6] (Enter = Q4_K_M): ${NC}" q
    case "$q" in
        ""|1) HF_QUANT="Q4_K_M" ;;
        2)    HF_QUANT="Q5_K_M" ;;
        3)    HF_QUANT="Q6_K" ;;
        4)    HF_QUANT="Q8_0" ;;
        5)    HF_QUANT="Q3_K_M" ;;
        6)    HF_QUANT="BF16" ;;
        *)    print_warn "Invalid choice; using Q4_K_M"; HF_QUANT="Q4_K_M" ;;
    esac
}

# ---------- Map a chosen quant to the repo's actual GGUF filename ----------
# GGUF naming differs per repo (case, UD- prefix, missing quants). Echoes the
# filename for <key,quant>, or returns 1 if that quant is not published.
hf_preset_filename() {
    local key="$1" q="$2"
    case "$key" in
        qwen3.5-4b) echo "Qwen3.5-4B-${q}.gguf" ;;
        qwen3.5-9b) echo "Qwen3.5-9B-${q}.gguf" ;;
        ornith-9b)
            case "$q" in
                Q4_K_M|Q5_K_M|Q6_K|Q8_0) echo "ornith-1.0-9b-${q}.gguf" ;;
                BF16)                     echo "ornith-1.0-9b-bf16.gguf" ;;
                *) return 1 ;;   # e.g. Q3_K_M not published for Ornith
            esac ;;
        lfm2.5-8b)
            case "$q" in
                Q4_K_M|Q5_K_M|Q6_K|Q3_K_M) echo "LFM2.5-8B-A1B-UD-${q}.gguf" ;;
                Q8_0|BF16)                 echo "LFM2.5-8B-A1B-${q}.gguf" ;;
                *) return 1 ;;
            esac ;;
        *) return 1 ;;
    esac
}

# ---------- Preset downloader (tool-capable, built-in RENDERER/PARSER) ----------
# Each modern arch ships its tool engine inside Ollama; we set RENDERER/PARSER
# explicitly because `ollama create` from a GGUF does not (ollama/ollama#17636).
# Usage: download_hf_preset <qwen3.5-4b|qwen3.5-9b|ornith-9b|lfm2.5-8b>
download_hf_preset() {
    local key="$1"
    local repo name rspec minver
    case "$key" in
        qwen3.5-4b) repo="unsloth/Qwen3.5-4B-GGUF";      name="qwen3.5-4b";  rspec="qwen3.5";           minver="0.17.1" ;;
        qwen3.5-9b) repo="unsloth/Qwen3.5-9B-GGUF";      name="qwen3.5-9b";  rspec="qwen3.5";           minver="0.17.1" ;;
        ornith-9b)  repo="ornith-ai/Ornith-1.0-9B-GGUF"; name="ornith-1.0-9b"; rspec="ornith";          minver="0.30.11" ;;
        lfm2.5-8b)  repo="unsloth/LFM2.5-8B-A1B-GGUF";   name="lfm2.5-8b";   rspec="lfm2,lfm2-thinking"; minver="0.30.0" ;;
        *) print_error "Unknown preset: $key"; return 1 ;;
    esac

    clear; print_banner
    print_step "Download ${name} (Hugging Face)"
    hf_choose_quant
    local gguf
    if ! gguf=$(hf_preset_filename "$key" "$HF_QUANT"); then
        print_warn "Quant $HF_QUANT is not published for ${name}; falling back to Q4_K_M"
        HF_QUANT="Q4_K_M"; gguf=$(hf_preset_filename "$key" "Q4_K_M")
    fi

    echo ""
    print_info "Repo:     $repo"
    print_info "File:     $gguf"
    print_info "Name:     $name"
    print_info "Engine:   RENDERER/PARSER ${rspec} (Ollama built-in)"
    if ! ollama_version_at_least "$minver"; then
        print_warn "${name} tools need Ollama >= ${minver}. If tools don't appear in 5ire, update via Maintenance [6] -> [1]."
    fi
    echo ""
    hf_build_model "$repo" "$gguf" "$name" "renderer:${rspec}" "no"
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ---------- Custom downloader: any repo/file, with template + mmproj detection ----------
download_hf_custom() {
    clear; print_banner
    print_step "Download from Hugging Face (Custom)"
    echo -e "${BLUE}Browse GGUF models at: https://huggingface.co/models?library=gguf${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  NOTES:${NC}"
    echo "  • Repo format: 'organization/model-name' (e.g., Qwen/Qwen3-4B-GGUF)"
    echo "  • Filename must end with .gguf"
    echo "  • For vision models, mmproj file will be auto-detected"
    echo ""

    read_input "${CYAN}Hugging Face Repo: ${NC}" hf_repo
    read_input "${CYAN}GGUF Filename: ${NC}" hf_file
    read_input "${CYAN}Desired Ollama model name: ${NC}" ollama_name

    hf_repo=$(sanitize_input "$hf_repo")
    hf_file=$(sanitize_input "$hf_file")
    ollama_name=$(sanitize_input "$ollama_name")

    if [[ ! "$hf_repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        print_error "Invalid repo format. Use 'organization/model-name'"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    if [[ ! "$hf_file" =~ \.gguf$ ]]; then
        print_error "Filename must end with .gguf"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    if ! valid_model_ref "$ollama_name"; then
        print_error "Invalid model name. Allowed: letters, numbers, . _ : / - (e.g. qwen2.5-custom)"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    # Ollama stores model names lowercase; normalise to avoid create/remove mismatches.
    local ollama_name_lc
    ollama_name_lc=$(echo "$ollama_name" | tr '[:upper:]' '[:lower:]')
    if [ "$ollama_name_lc" != "$ollama_name" ]; then
        print_warn "Ollama lowercases model names: using '$ollama_name_lc'"
        ollama_name="$ollama_name_lc"
    fi

    echo ""
    echo -e "${YELLOW}Select a prompt template (affects MCP / tool-calling):${NC}"
    echo -e "  ${GREEN}[1]${NC} Auto     — let Ollama pick from the GGUF (chat; tools only if embedded)"
    echo -e "  ${GREEN}[2]${NC} ChatML   — tool-capable, for OLDER families (Qwen2.5 / Qwen3 ChatML GGUFs)"
    echo -e "  ${GREEN}[3]${NC} Llama 3  — tool-capable (Llama 3.1 / 3.2)"
    echo -e "  ${GREEN}[4]${NC} None     — text-only (no chat template)"
    echo -e "  ${GREEN}[5]${NC} Built-in RENDERER/PARSER — for MODERN archs (Qwen3.5, DeepSeek,"
    echo -e "             GLM, Gemma4...). ${CYAN}<= correct choice for Qwen3.5 tools${NC} (needs Ollama >= 0.17.1)"
    read_input "${CYAN}Template [1-5] (default 1): ${NC}" tmpl_choice
    local tmpl="auto"
    case "$tmpl_choice" in
        2) tmpl="chatml" ;;
        3) tmpl="llama3" ;;
        4) tmpl="none" ;;
        5) echo -e "  ${YELLOW}Examples:${NC} qwen3.5 · ornith · deepseek3.1 · gemma4 · (LFM2.5 differs: renderer lfm2, parser lfm2-thinking)"
           read_input "${CYAN}RENDERER name (e.g. qwen3.5): ${NC}" rp_name
           read_input "${CYAN}PARSER name (Enter = same as renderer): ${NC}" pp_name
           rp_name=$(sanitize_input "$rp_name"); pp_name=$(sanitize_input "$pp_name")
           if [[ ! "$rp_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
               print_error "Invalid renderer name"; read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
           fi
           if [ -n "$pp_name" ]; then
               if [[ ! "$pp_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                   print_error "Invalid parser name"; read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
               fi
               tmpl="renderer:${rp_name},${pp_name}"
           else
               tmpl="renderer:${rp_name}"
           fi ;;
        *) tmpl="auto" ;;
    esac

    if [ "$tmpl" != "chatml" ] && [ "$tmpl" != "llama3" ] && [ "$tmpl" != "none" ] && ! ollama_version_at_least "0.17.1"; then
        print_warn "Built-in renderer/parser needs Ollama >= 0.17.1. Update via menu option [6] -> [1] if tools don't appear."
    fi

    hf_build_model "$hf_repo" "$hf_file" "$ollama_name" "$tmpl" "yes"
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ---------- Hugging Face menu (dispatcher) ----------
download_from_huggingface() {
    while true; do
        clear; print_banner
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${BOLD}  DOWNLOAD FROM HUGGING FACE                                  ${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Presets (tool-capable, built-in engine):${NC}                    ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[1]${NC} Qwen3.5-4B    (Q4_K_M ~2.5GB) — for 6GB VRAM          ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[2]${NC} Qwen3.5-9B    (Q4_K_M ~5.5GB) — for 8GB+ VRAM         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[3]${NC} Ornith-1.0-9B (Q4_K_M ~5.5GB) — for 8GB+ VRAM         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[4]${NC} LFM2.5-8B-A1B (MoE, fast — needs Ollama >= 0.30)      ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[5]${NC} Custom (enter repo + filename)                        ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Back                                                  ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-5]: ${NC}" hf_choice
        case "$hf_choice" in
            0) return 0 ;;
            1) download_hf_preset "qwen3.5-4b" ;;
            2) download_hf_preset "qwen3.5-9b" ;;
            3) download_hf_preset "ornith-9b" ;;
            4) download_hf_preset "lfm2.5-8b" ;;
            5) download_hf_custom ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

list_installed_models() {
    clear; print_banner; print_step "Installed Models"
    ensure_ollama_running || return 1
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama list" 2>/dev/null
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    print_info "Disk usage of /srv/ollama_models:"
    du -sh "$OLLAMA_MODELS_DIR" 2>/dev/null
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

remove_model() {
    clear; print_banner; print_step "Remove Model"
    ensure_ollama_running || return 1
    print_info "Currently installed models:"
    su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama list" 2>/dev/null
    echo ""
    read_input "${CYAN}Enter model name to remove: ${NC}" model_name
    model_name=$(sanitize_input "$model_name")
    if [ -z "$model_name" ]; then
        print_error "Model name cannot be empty"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    if ! valid_model_ref "$model_name"; then
        print_error "Invalid model name. Allowed: letters, numbers, . _ : / -"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    print_warn "This will permanently delete: $model_name"
    read_input "${RED}Are you sure? [y/N]: ${NC}" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama rm $model_name"; then
            print_success "Model '$model_name' removed"
            log "INFO" "Model removed: $model_name"
        else
            print_error "Failed to remove model"
        fi
    fi
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ==============================================================================
# PHASE 5: 5IRE INSTALLATION
# ==============================================================================
install_5ire() {
    print_step "Phase 5: 5ire Application Installation"
    if [ -x "$FIVEIRE_DIR/5ire.AppImage" ]; then
        read_input "${YELLOW}5ire already installed. Reinstall? [y/N]: ${NC}" reinstall
        [[ "$reinstall" =~ ^[Yy]$ ]] || return 0
    fi
    
    mkdir -p "$FIVEIRE_DIR"

    print_info "Ensuring AppImage runtime (libfuse2t64) is present..."
    if ! dpkg -s libfuse2t64 &> /dev/null; then
        apt install -y libfuse2t64 >> "$LOG_FILE" 2>&1 || print_warn "libfuse2t64 install failed; launcher will use --appimage-extract-and-run"
    fi

    print_info "Downloading 5ire v0.15.4..."
    wget -q --show-progress -O "$FIVEIRE_DIR/5ire.AppImage" https://github.com/nanbingxyz/5ire/releases/download/v0.15.4/5ire-0.15.4-x86_64.AppImage || { print_error "Download failed"; return 1; }
    chmod +x "$FIVEIRE_DIR/5ire.AppImage"
    
    print_info "Creating intelligent launcher..."
    cat > "$FIVEIRE_BIN" << 'EOF'
#!/bin/bash
OLLAMA_BIN="/srv/ollama_bin/bin/ollama"
export OLLAMA_MODELS="/srv/ollama_models"
if ! curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
    echo "🚀 Starting Ollama server..."
    nohup "$OLLAMA_BIN" serve > /tmp/ollama.log 2>&1 &
    for i in {1..15}; do
        curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1 && { echo "✅ Ollama server ready"; break; }
        [ $i -eq 15 ] && { echo "❌ Server failed to start"; exit 1; }
        sleep 1
    done
fi
/opt/5ire/5ire.AppImage --appimage-extract-and-run "$@"
EOF
    chmod +x "$FIVEIRE_BIN"
    chown "$REAL_USER:$REAL_USER" "$FIVEIRE_BIN"
    local rc
    for rc in "$REAL_HOME/.zshrc" "$REAL_HOME/.bashrc"; do
        [ -e "$rc" ] || continue
        grep -q '/usr/local/bin' "$rc" 2>/dev/null || echo 'export PATH="/usr/local/bin:$PATH"' >> "$rc"
    done

    print_info "Creating desktop menu entry..."
    local apps_dir="$REAL_HOME/.local/share/applications"
    mkdir -p "$apps_dir"
    cat > "$apps_dir/5ire.desktop" << 'EOF'
[Desktop Entry]
Name=5ire
Comment=5ire Desktop AI Assistant (Ollama + MCP)
Exec=/usr/local/bin/5ire
Terminal=false
Type=Application
Categories=Utility;Development;
StartupWMClass=5ire
EOF
    chown -R "$REAL_USER:$REAL_USER" "$apps_dir/5ire.desktop"

    print_success "5ire installed successfully! Launch from the menu or with: ${CYAN}5ire${NC}"
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ==============================================================================
# PHASE 6: MCP KALI SERVER INSTALLATION (ARCHITECTURALLY FIXED)
# ==============================================================================
install_mcp_server() {
    print_step "Phase 6: MCP Kali Server Installation"
    print_info "Installing mcp-kali-server and essential Kali tools..."
    apt update -qq >> "$LOG_FILE" 2>&1
    if apt install -y mcp-kali-server dirb gobuster nikto nmap enum4linux-ng hydra john metasploit-framework sqlmap wpscan wordlists python3-flask >> "$LOG_FILE" 2>&1; then
        print_success "MCP server and Kali tools installed"
    else
        print_error "Some packages failed to install. See $LOG_FILE"
        log "ERROR" "apt install for MCP tools returned non-zero"
    fi

    if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
        print_info "Extracting rockyou.txt wordlist..."
        gunzip -v /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
    fi
    
    print_info "Creating systemd service for the Flask API backend only..."
    print_info "(Note: 'mcp-server' will be spawned by 5ire on demand, no need for background service)"
    
    cat > /tmp/kali-mcp-api.service << EOF
[Unit]
Description=Kali MCP Flask API Backend
After=network.target

[Service]
Type=simple
User=$REAL_USER
ExecStart=/usr/bin/kali-server-mcp
Restart=on-failure
RestartSec=5
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

    systemctl stop kali-mcp.service 2>/dev/null
    systemctl disable kali-mcp.service 2>/dev/null
    rm -f /etc/systemd/system/kali-mcp.service
    rm -f /usr/local/bin/start-kali-mcp.sh

    mv /tmp/kali-mcp-api.service /etc/systemd/system/kali-mcp-api.service
    systemctl daemon-reload
    systemctl enable --now kali-mcp-api.service

    # Fix the known Kali-package regression that breaks /api/tools/* endpoints.
    repair_mcp_server

    sleep 3
    if curl -s http://127.0.0.1:5000/health > /dev/null 2>&1; then
        print_success "MCP Flask API is running successfully on port 5000!"
        print_info "The system is ready. 5ire will launch 'mcp-server' automatically when needed."
    else
        print_error "Failed to start MCP Flask API."
        print_info "Check logs: journalctl -u kali-mcp-api.service -e"
    fi

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${BOLD}  📌 NEXT STEP: Connect MCP to 5ire GUI${NC}                      ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  1. Open 5ire application (type ${CYAN}5ire${NC} in terminal)"
    echo -e "${CYAN}│${NC}  2. Go to ${BOLD}Tools${NC} ➔ ${BOLD}Local${NC} (or MCP Servers)"
    echo -e "${CYAN}│${NC}  3. Add New Server with these exact details:"
    echo -e "${CYAN}│${NC}     - Name: ${GREEN}mcp-kali-server${NC}"
    echo -e "${CYAN}│${NC}     - Description: ${GREEN}MCP Kali Server${NC}"
    echo -e "${CYAN}│${NC}     - Approval Policy: Always"
    echo -e "${CYAN}│${NC}     - Command: ${GREEN}/usr/bin/mcp-server${NC}"
    echo -e "${CYAN}│${NC}  4. Save and ${BOLD}Enable${NC} the server (toggle must be green)"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ==============================================================================
# PHASE 6b: REPAIR MCP SERVER (fix Kali package's broken /api/tools/* endpoints)
# ==============================================================================
# The Kali 'mcp-kali-server' package ships a botched "remove-shell-true" patch that
#   (a) adds a guard rejecting non-string commands -> every /api/tools/* endpoint
#       (nmap, dirb, gobuster, ...) sends an argv list and gets HTTP 500, and
#   (b) computes cmd_args = shlex.split(...) but never uses it, so shell=True is
#       actually still active (the patch's own security goal fails).
# This function rewrites CommandExecutor.execute() to accept both str and list and
# to always run WITHOUT a shell. Idempotent, keeps a .bak, safe if the file differs.
repair_mcp_server() {
    print_step "Repair / Patch MCP Server (Kali package fix)"
    local server_py="/usr/share/mcp-kali-server/server.py"
    if [ ! -f "$server_py" ]; then
        print_error "$server_py not found. Install the MCP server first (option [5])."
        return 1
    fi
    if ! command -v python3 &> /dev/null; then
        print_error "python3 not found; cannot patch."
        return 1
    fi

    [ -f "${server_py}.bak" ] || cp -a "$server_py" "${server_py}.bak"

    local result
    result=$(python3 - "$server_py" << 'PYEOF'
import sys
p = sys.argv[1]
MARK = "Patched by Kali_LLM installer"
try:
    s = open(p, encoding="utf-8").read()
except Exception:
    print("ERR_READ"); sys.exit(0)

if MARK in s:
    print("ALREADY"); sys.exit(0)
if "CommandExecutor expects a string" not in s:
    print("UNKNOWN"); sys.exit(0)

s = s.replace(
"""        if not isinstance(self.command, str):
            raise ValueError(f"CommandExecutor expects a string, but got {type(self.command).__name__}")

        cmd_args = shlex.split(self.command)
""",
"""        # Patched by Kali_LLM installer: accept str (shell string) or list (argv);
        # always run WITHOUT a shell for safety.
        cmd_args = shlex.split(self.command) if isinstance(self.command, str) else self.command
""")
s = s.replace(
"""                self.command,
                shell=self.use_shell,""",
"""                cmd_args,
                shell=False,""")

if "shell=self.use_shell" in s or "expects a string" in s or MARK not in s:
    print("ERR_PATTERN"); sys.exit(0)

try:
    compile(s, p, "exec")
except SyntaxError:
    print("ERR_SYNTAX"); sys.exit(0)

open(p, "w", encoding="utf-8").write(s)
print("PATCHED")
PYEOF
)

    case "$result" in
        PATCHED)
            print_success "server.py patched: tool endpoints fixed + shell disabled"
            log "INFO" "mcp-kali-server server.py patched"
            if systemctl restart kali-mcp-api.service 2>/dev/null; then
                print_success "kali-mcp-api.service restarted"
            else
                print_warn "Patched, but could not restart kali-mcp-api.service"
            fi
            ;;
        ALREADY)  print_success "server.py already patched — nothing to do" ;;
        UNKNOWN)  print_warn "server.py doesn't match the known buggy version; left unchanged (maybe already fixed upstream)" ;;
        ERR_READ) print_error "Could not read $server_py (permissions?)" ;;
        ERR_PATTERN|ERR_SYNTAX)
            print_error "Patch aborted safely; restoring backup"
            cp -a "${server_py}.bak" "$server_py" 2>/dev/null
            ;;
        *) print_error "Unexpected patch result: $result" ;;
    esac
}

# ==============================================================================
# PHASE 7: UPDATE / UPGRADE (System tools, Ollama, 5ire)
# ==============================================================================
update_tools() {
    clear; print_banner
    print_step "Update & Upgrade Tools"

    # --- 1. System packages (Kali tools) ---
    print_info "Updating Kali package lists and upgrading installed tools..."
    if apt update -qq >> "$LOG_FILE" 2>&1 && apt full-upgrade -y >> "$LOG_FILE" 2>&1; then
        print_success "System tools upgraded"
    else
        print_error "System upgrade reported errors. See $LOG_FILE"
    fi
    apt autoremove -y >> "$LOG_FILE" 2>&1 || true

    # --- 2. Ollama (re-download latest static build) ---
    if [ -x "$OLLAMA_BASE/bin/ollama" ]; then
        local cur_ver
        cur_ver=$(ollama --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
        print_info "Updating Ollama (current: v${cur_ver:-unknown})..."
        if curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst -o /tmp/ollama-linux-amd64.tar.zst; then
            tar x --zstd -C "$OLLAMA_BASE" -f /tmp/ollama-linux-amd64.tar.zst >> "$LOG_FILE" 2>&1
            rm -f /tmp/ollama-linux-amd64.tar.zst
            ln -sf "$OLLAMA_BASE/bin/ollama" /usr/local/bin/ollama
            chown -R "$REAL_USER:$REAL_USER" "$OLLAMA_BASE" 2>/dev/null || true
            print_success "Ollama updated to: $(ollama --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)"
            log "INFO" "Ollama updated"
        else
            print_error "Ollama download failed; kept existing version"
        fi
    else
        print_warn "Ollama not installed; skipping (use menu option [2])"
    fi

    # --- 3. mcp-kali-server (apt-managed) + re-apply our patch ---
    # server.py lives in /usr/share (NOT a dpkg conffile), so any package upgrade
    # silently overwrites it with the buggy version. Re-run the repair to be safe.
    if dpkg -s mcp-kali-server &> /dev/null; then
        print_success "mcp-kali-server is managed by apt (upgraded above)"
        print_info "Re-applying MCP tool-endpoint patch (upgrade may have reverted it)..."
        repair_mcp_server
    else
        print_warn "mcp-kali-server not installed; skipping (use menu option [5])"
    fi

    # --- 4. 5ire (optional bump to a newer AppImage version) ---
    if [ -x "$FIVEIRE_DIR/5ire.AppImage" ]; then
        echo ""
        read_input "${CYAN}Update 5ire? Enter version tag (e.g. 0.15.4) or leave empty to skip: ${NC}" fire_ver
        fire_ver=$(sanitize_input "$fire_ver")
        if [ -n "$fire_ver" ]; then
            if [[ "$fire_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_info "Downloading 5ire v${fire_ver}..."
                if wget -q --show-progress -O "$FIVEIRE_DIR/5ire.AppImage.new" \
                    "https://github.com/nanbingxyz/5ire/releases/download/v${fire_ver}/5ire-${fire_ver}-x86_64.AppImage"; then
                    mv -f "$FIVEIRE_DIR/5ire.AppImage.new" "$FIVEIRE_DIR/5ire.AppImage"
                    chmod +x "$FIVEIRE_DIR/5ire.AppImage"
                    print_success "5ire updated to v${fire_ver}"
                    log "INFO" "5ire updated to v${fire_ver}"
                else
                    rm -f "$FIVEIRE_DIR/5ire.AppImage.new"
                    print_error "Download failed; kept existing 5ire. Verify the version tag exists."
                fi
            else
                print_error "Invalid version format (expected X.Y.Z)"
            fi
        else
            print_info "Skipped 5ire update"
        fi
    else
        print_warn "5ire not installed; skipping (use menu option [4])"
    fi

    echo ""
    print_success "Update routine finished"
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
}

# ==============================================================================
# PHASE 8: SERVICE MANAGEMENT (MCP API + Ollama)
# ==============================================================================
show_service_status() {
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${BOLD}                      SERVICE STATUS                         ${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"

    # MCP Flask API (systemd)
    if systemctl is-active --quiet kali-mcp-api.service 2>/dev/null; then
        echo -e "  ${BOLD}MCP API (kali-mcp-api):${NC}  ${GREEN}[✓]${NC} Running (Port 5000)"
    else
        echo -e "  ${BOLD}MCP API (kali-mcp-api):${NC}  ${RED}[✗]${NC} Stopped"
    fi

    # Ollama server (on-demand, not a systemd unit in this setup)
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        echo -e "  ${BOLD}Ollama server:${NC}          ${GREEN}[✓]${NC} Running (Port 11434)"
    else
        echo -e "  ${BOLD}Ollama server:${NC}          ${RED}[✗]${NC} Stopped"
    fi
    echo ""
}

stop_ollama() {
    if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        pkill -f "$OLLAMA_BASE/bin/ollama serve" 2>/dev/null
        pkill -f "ollama serve" 2>/dev/null
        sleep 1
        if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
            print_error "Ollama is still responding (it may be managed elsewhere)"
        else
            print_success "Ollama server stopped"
        fi
    else
        print_info "Ollama server is not running"
    fi
}

manage_services() {
    while true; do
        clear; print_banner
        print_step "Service Management"
        show_service_status
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[1]${NC} Start MCP API          ${GREEN}[2]${NC} Stop MCP API                ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[3]${NC} Restart MCP API        ${GREEN}[4]${NC} MCP API logs (last 30)      ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[5]${NC} Start Ollama           ${GREEN}[6]${NC} Stop Ollama                 ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Back to Main Menu                                      ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-6]: ${NC}" svc_choice

        case $svc_choice in
            0) return 0 ;;
            1) systemctl start kali-mcp-api.service 2>/dev/null \
                 && print_success "MCP API started" || print_error "Failed to start (is it installed? option [5] in main menu)"
               read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            2) systemctl stop kali-mcp-api.service 2>/dev/null \
                 && print_success "MCP API stopped" || print_error "Failed to stop"
               read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            3) systemctl restart kali-mcp-api.service 2>/dev/null \
                 && print_success "MCP API restarted" || print_error "Failed to restart"
               read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            4) echo -e "${CYAN}──────── kali-mcp-api.service (last 30 lines) ────────${NC}"
               journalctl -u kali-mcp-api.service -n 30 --no-pager 2>/dev/null || print_error "No logs available"
               read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            5) ensure_ollama_running; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            6) stop_ollama; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MAINTENANCE MENU (Update + Services + Repair)
# ==============================================================================
maintenance_menu() {
    while true; do
        clear; print_banner
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${BOLD}  MAINTENANCE                                                 ${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[1]${NC} Update Tools (System + Ollama + 5ire)                  ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[2]${NC} Manage Services (MCP API + Ollama)                     ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[3]${NC} Repair MCP Server (fix tool endpoints)                 ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Back to Main Menu                                      ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-3]: ${NC}" maint_choice
        case "$maint_choice" in
            0) return 0 ;;
            1) update_tools ;;
            2) manage_services ;;
            3) repair_mcp_server; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MAIN MENU
# ==============================================================================
main_menu() {
    while true; do
        clear; print_banner
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${BOLD}                         MAIN MENU                           ${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[1]${NC} Prepare Workspace (/srv)                               ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[2]${NC} Install Ollama                                         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[3]${NC} Download & Manage Models                               ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[4]${NC} Install 5ire Application                               ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[5]${NC} Install & Configure MCP Server (Kali Tools)            ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[6]${NC} Maintenance (Update · Services · Repair)               ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Exit Script                                            ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-6]: ${NC}" choice

        case $choice in
            0) echo -e "${GREEN}Thank you for using Kali LLM Installer!${NC}"; log "INFO" "Exited cleanly"; exit 0 ;;
            1) setup_workspace; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            2) install_ollama; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            3) download_models ;;
            4) install_5ire ;;
            5) install_mcp_server ;;
            6) maintenance_menu ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================
main() {
    prerequisites_check
    check_dependencies
    validate_environment
    main_menu
}

main "$@"
