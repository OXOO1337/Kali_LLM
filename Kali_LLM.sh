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

download_from_huggingface() {
    clear; print_banner
    print_step "Download from Hugging Face (Advanced)"
    echo -e "${BLUE}Browse GGUF models at: https://huggingface.co/models?library=gguf${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT NOTES:${NC}"
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
    if [[ ! "$ollama_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Model name can only contain letters, numbers, - and _"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    
    mkdir -p "$MODELS_TEMP"
    cd "$MODELS_TEMP" || { print_error "Cannot access $MODELS_TEMP (run option [1] first)"; read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1; }

    print_info "Downloading main GGUF file..."
    if ! wget -q --show-progress "https://huggingface.co/$hf_repo/resolve/main/$hf_file"; then
        print_error "Download failed. Verify repo and filename."
        log "ERROR" "HF download failed: $hf_repo/$hf_file"
        read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1
    fi
    
    local mmproj_file=""
    local base_name="${hf_file%.gguf}"
    print_info "Checking for vision projector (mmproj)..."
    for candidate in "mmproj-${base_name}.gguf" "mmproj-${base_name}-f16.gguf" "mmproj-${base_name}-F16.gguf" "mmproj-model-f16.gguf"; do
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
    
    print_info "Generating Modelfile..."
    # Note: the prompt template is intentionally omitted so Ollama can infer the
    # correct chat template from the GGUF metadata (works for Llama/Qwen/Gemma/Phi...).
    {
        echo "FROM ./$hf_file"
        [ -n "$mmproj_file" ] && echo "FROM ./$mmproj_file"
        echo 'PARAMETER temperature 0.7'
        echo 'PARAMETER top_p 0.8'
        echo 'PARAMETER num_ctx 4096'
    } > Modelfile

    ensure_ollama_running || { read_input "${CYAN}Press Enter to continue... ${NC}" dummy; return 1; }
    
    print_info "Building model in Ollama..."
    if su - "$REAL_USER" -c "export OLLAMA_MODELS=$OLLAMA_MODELS_DIR && ollama create $ollama_name -f $MODELS_TEMP/Modelfile"; then
        print_success "Model '$ollama_name' created successfully"
        log "INFO" "Custom model created: $ollama_name"
    else
        print_error "Model build failed. Check Modelfile syntax."
        log "ERROR" "Model build failed: $ollama_name"
    fi
    
    print_info "Cleaning up temporary files..."
    rm -f "$hf_file" "$mmproj_file" Modelfile
    read_input "${CYAN}Press Enter to continue... ${NC}" dummy
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

    # --- 3. mcp-kali-server (via apt, already covered by full-upgrade) ---
    if dpkg -s mcp-kali-server &> /dev/null; then
        print_success "mcp-kali-server is managed by apt (upgraded above)"
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
        echo -e "${CYAN}│${NC}  ${GREEN}[6]${NC} Update Tools (System + Ollama + 5ire)                  ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}[7]${NC} Manage Services (MCP API + Ollama)                     ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${RED}[0]${NC} Exit Script                                            ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read_input "${CYAN}Select option [0-7]: ${NC}" choice

        case $choice in
            0) echo -e "${GREEN}Thank you for using Kali LLM Installer!${NC}"; log "INFO" "Exited cleanly"; exit 0 ;;
            1) setup_workspace; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            2) install_ollama; read_input "${CYAN}Press Enter to continue... ${NC}" dummy ;;
            3) download_models ;;
            4) install_5ire ;;
            5) install_mcp_server ;;
            6) update_tools ;;
            7) manage_services ;;
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
