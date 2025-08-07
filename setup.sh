#!/bin/bash

set -e

# --- 🎯 Configuration ---
SCRIPT_VERSION="2.0.0"
CONFIG_DIR="$HOME/.config/ollama-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
MODELS_DB="$CONFIG_DIR/models.json"
USAGE_LOG="$CONFIG_DIR/usage.log"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# --- 🎨 Enhanced Colors & Styling ---
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
GRAY="\033[0;90m"
BOLD="\033[1m"
DIM="\033[2m"
NC="\033[0m"

# Icons
ICON_ROCKET="🚀"
ICON_CHECK="✅"
ICON_CROSS="❌"
ICON_GEAR="⚙️"
ICON_BRAIN="🧠"
ICON_GPU="🎮"
ICON_RAM="📦"
ICON_CPU="🔧"
ICON_DOWNLOAD="📥"
ICON_SWITCH="🔄"
ICON_STAR="⭐"
ICON_FIRE="🔥"
ICON_MAGIC="✨"

# --- 🛠️ Enhanced Helper Functions ---

print_banner() {
    clear
    echo -e "${CYAN} ${WHITE}${BOLD}                🦙 OLLAMA MANAGER v${SCRIPT_VERSION}"
    echo -e "${CYAN} ${GRAY}         Advanced AI Model Management Suite For OLLAMA"
    echo -e "${CYAN} ═══════════════════════════════════════════════════════════ "
    echo ""
}

print_header() {
    echo -e "\n${BLUE}${BOLD}==> ${1}${NC}"
}

print_success() {
    echo -e "${GREEN}${ICON_CHECK} ${1}${NC}"
}

print_error() {
    echo -e "${RED}${ICON_CROSS} ${1}${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  ${1}${NC}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

confirm() {
    echo -ne "${YELLOW}$1 ${GRAY}[y/N]:${NC} "
    read -r yn
    case "$yn" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

multi_choice() {
    local title="$1"
    shift
    local options=("$@")
    
    echo -e "${CYAN}${BOLD}$title${NC}"
    for i in "${!options[@]}"; do
        echo -e "${GRAY}[$((i+1))]${NC} ${options[i]}"
    done
    echo -ne "${YELLOW}Select option ${GRAY}[1-${#options[@]}]:${NC} "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        return $((choice-1))
    else
        return 255
    fi
}

# --- 📁 Configuration Management ---

init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
    "preferred_models": [],
    "auto_update": true,
    "last_used_model": "",
    "ui_mode": "cli",
    "gpu_optimization": true,
    "model_categories": {
        "coding": [],
        "chat": [],
        "creative": []
    }
}
EOF
    fi
}

save_config() {
    local key="$1"
    local value="$2"
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

get_config() {
    local key="$1"
    jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null || echo ""
}

log_usage() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$USAGE_LOG"
}

# --- 🔍 Enhanced System Detection ---

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

get_gpu_info() {
    local gpu_info=""
    local vram_gb=0
    
    if command -v nvidia-smi &>/dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
        vram_gb=$(echo "$gpu_info" | awk -F', ' '{print int($2/1024)}')
        echo "$gpu_info (${vram_gb}GB VRAM)"
    elif command -v rocm-smi &>/dev/null; then
        gpu_info=$(rocm-smi --showproductname --csv | tail -1 | cut -d',' -f2)
        echo "$gpu_info (AMD ROCm)"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        gpu_info=$(system_profiler SPDisplaysDataType | grep "Chipset Model:" | awk -F': ' '{print $2}' | head -1)
        echo "$gpu_info (Apple Silicon)"
    elif command -v lshw &>/dev/null; then
        gpu_info=$(sudo lshw -C display 2>/dev/null | grep -i "product" | sed 's/.*: //' | head -1)
        echo "${gpu_info:-Integrated Graphics}"
    else
        echo "No GPU detected"
    fi
    
    # Store VRAM size for model recommendations
    echo "$vram_gb" > "${CONFIG_DIR}/vram_size"
}

get_vram_size() {
    [[ -f "${CONFIG_DIR}/vram_size" ]] && cat "${CONFIG_DIR}/vram_size" || echo "0"
}

get_ram_gb() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    else
        free -g | awk '/^Mem:/ {print $2}'
    fi
}

get_cpu_info() {
    local cores threads arch
    cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        arch=$(uname -m)
        echo "$cores cores ($arch)"
    else
        arch=$(lscpu | grep Architecture | awk '{print $2}')
        threads=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')
        echo "$cores cores, ${threads:-1} threads ($arch)"
    fi
}

# --- 📊 Enhanced System Overview ---

show_enhanced_specs() {
    print_header "${ICON_GEAR} System Analysis & Compatibility Check"
    
    local ram_gb cpu_info gpu_info vram_gb os_info
    ram_gb=$(get_ram_gb)
    cpu_info=$(get_cpu_info)
    gpu_info=$(get_gpu_info)
    vram_gb=$(get_vram_size)
    os_info=$(detect_os)
    
    echo -e "${CYAN}┌─ Hardware Specifications ─────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${ICON_CPU} CPU      : $cpu_info"
    echo -e "${CYAN}│${NC} ${ICON_RAM} RAM      : ${ram_gb} GB"
    echo -e "${CYAN}│${NC} ${ICON_GPU} GPU      : $gpu_info"
    echo -e "${CYAN}│${NC} ${ICON_GEAR} OS       : $os_info"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${NC}"
    
    # Performance Rating
    local rating="Unknown"
    local color=$GRAY
    
    if [[ $ram_gb -ge 32 && $vram_gb -ge 8 ]]; then
        rating="Excellent ${ICON_FIRE}"
        color=$GREEN
    elif [[ $ram_gb -ge 16 && $vram_gb -ge 4 ]]; then
        rating="Very Good ${ICON_STAR}"
        color=$CYAN
    elif [[ $ram_gb -ge 8 ]]; then
        rating="Good ${ICON_CHECK}"
        color=$YELLOW
    else
        rating="Limited ${ICON_CROSS}"
        color=$RED
    fi
    
    echo -e "\n${BOLD}AI Performance Rating:${NC} ${color}$rating${NC}"
    echo ""
}

# --- 🔧 Enhanced Installation & Updates ---

check_dependencies() {
    print_header "${ICON_GEAR} Checking Dependencies"
    
    local missing=()
    local recommended=("curl" "jq" "git")
    local optional=("fzf" "dialog" "htop" "nvidia-smi")
    
    for cmd in "${recommended[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing required dependencies: ${missing[*]}"
        if confirm "Install missing dependencies?"; then
            install_dependencies "${missing[@]}"
        fi
    fi
    
    # Check optional
    print_info "Checking optional tools..."
    for cmd in "${optional[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            print_success "$cmd is available"
        else
            echo -e "${GRAY}  $cmd not found (optional)${NC}"
        fi
    done
}

install_dependencies() {
    local deps=("$@")
    case "$(detect_os)" in
        ubuntu|debian)
            sudo apt update && sudo apt install -y "${deps[@]}"
            ;;
        arch|manjaro)
            sudo pacman -S --needed "${deps[@]}"
            ;;
        fedora)
            sudo dnf install -y "${deps[@]}"
            ;;
        centos|rhel)
            sudo yum install -y "${deps[@]}"
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install "${deps[@]}"
            else
                print_error "Homebrew not found. Please install manually."
            fi
            ;;
        *)
            print_error "Unsupported OS. Please install manually: ${deps[*]}"
            ;;
    esac
}

check_or_install_ollama() {
    if ! command -v ollama &>/dev/null; then
        print_header "${ICON_DOWNLOAD} Installing Ollama"
        
        case "$(detect_os)" in
            ubuntu|debian|fedora|centos|rhel|arch|manjaro)
                echo "Downloading and installing Ollama..."
                curl -fsSL https://ollama.com/install.sh | sh &
                spinner $!
                ;;
            macos)
                if confirm "Install via Homebrew? (Alternative: manual download)"; then
                    brew install ollama
                else
                    open "https://ollama.com/download"
                    print_info "Please download and install manually, then re-run this script."
                    exit 0
                fi
                ;;
            *)
                print_error "Unsupported OS. Please install manually: https://ollama.com"
                exit 1
                ;;
        esac
        
        print_success "Ollama installed successfully!"
        log_usage "Ollama installed"
    else
        print_success "Ollama is already installed"
        check_ollama_update
    fi
    
    # Start ollama service if not running
    if ! pgrep -f "ollama serve" > /dev/null; then
        print_info "Starting Ollama service..."
        ollama serve > /dev/null 2>&1 &
        sleep 3
    fi
}

get_ollama_version() {
    ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

get_latest_ollama_version() {
    curl -s https://api.github.com/repos/ollama/ollama/releases/latest | jq -r '.tag_name' | sed 's/^v//'
}

check_ollama_update() {
    local current_version latest_version
    current_version=$(get_ollama_version)
    latest_version=$(get_latest_ollama_version)
    
    if [[ "$current_version" != "$latest_version" ]] && [[ -n "$latest_version" ]]; then
        print_warning "New version available: $latest_version (current: $current_version)"
        
        if [[ "$(get_config auto_update)" == "true" ]] || confirm "Update Ollama now?"; then
            print_info "Updating Ollama..."
            curl -fsSL https://ollama.com/install.sh | sh &
            spinner $!
            print_success "Updated to version $latest_version"
            log_usage "Ollama updated to $latest_version"
        fi
    else
        print_success "Ollama is up to date (v$current_version)"
    fi
}

# --- 🧠 Advanced Model Management ---

get_installed_models() {
    ollama list 2>/dev/null | awk 'NR>1 && $1 != "" {print $1}' | sort
}

get_available_models() {
    # Enhanced model database with categories and requirements
    cat > "$MODELS_DB" << 'EOF'
{
    "models": {
        "llama3.1": {"size": "8B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "Latest LLaMA model, excellent for conversation"},
        "llama3.1:70b": {"size": "70B", "ram_req": 64, "vram_req": 0, "category": "chat", "description": "Large LLaMA model, exceptional quality"},
        "mistral": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "Fast and efficient chat model"},
        "mistral-nemo": {"size": "12B", "ram_req": 16, "vram_req": 0, "category": "chat", "description": "Improved Mistral with better reasoning"},
        "codellama": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "coding", "description": "Specialized for code generation"},
        "codellama:13b": {"size": "13B", "ram_req": 16, "vram_req": 0, "category": "coding", "description": "Larger code model, better performance"},
        "deepseek-coder": {"size": "6.7B", "ram_req": 8, "vram_req": 0, "category": "coding", "description": "Excellent for coding tasks"},
        "phi3": {"size": "3.8B", "ram_req": 4, "vram_req": 0, "category": "chat", "description": "Small but capable Microsoft model"},
        "phi3:medium": {"size": "14B", "ram_req": 16, "vram_req": 0, "category": "chat", "description": "Medium-sized Phi model"},
        "gemma2": {"size": "9B", "ram_req": 12, "vram_req": 0, "category": "chat", "description": "Google's latest Gemma model"},
        "gemma2:27b": {"size": "27B", "ram_req": 32, "vram_req": 0, "category": "chat", "description": "Large Gemma model"},
        "qwen2": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "Alibaba's multilingual model"},
        "llava": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "vision", "description": "Vision-language model"},
        "nomic-embed-text": {"size": "0.3B", "ram_req": 2, "vram_req": 0, "category": "embedding", "description": "Text embeddings model"},
        "all-minilm": {"size": "0.1B", "ram_req": 1, "vram_req": 0, "category": "embedding", "description": "Lightweight embeddings"},
        "neural-chat": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "Intel's optimized chat model"},
        "starling-lm": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "High-quality chat model"},
        "solar": {"size": "10.7B", "ram_req": 12, "vram_req": 0, "category": "chat", "description": "Upstage Solar model"},
        "openchat": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "OpenChat conversational model"},
        "vicuna": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "Fine-tuned LLaMA for conversation"},
        "wizard-vicuna-uncensored": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "creative", "description": "Uncensored creative model"},
        "orca-mini": {"size": "3B", "ram_req": 4, "vram_req": 0, "category": "chat", "description": "Small efficient model"},
        "tinydolphin": {"size": "1.1B", "ram_req": 2, "vram_req": 0, "category": "chat", "description": "Tiny but capable model"},
        "stable-code": {"size": "3B", "ram_req": 4, "vram_req": 0, "category": "coding", "description": "Stable AI's code model"},
        "magicoder": {"size": "7B", "ram_req": 8, "vram_req": 0, "category": "coding", "description": "Advanced coding assistant"},
        "yi": {"size": "6B", "ram_req": 8, "vram_req": 0, "category": "chat", "description": "01.AI's multilingual model"}
    }
}
EOF
}

suggest_models_smart() {
    print_header "${ICON_BRAIN} Intelligent Model Recommendations"
    
    local ram_gb vram_gb installed_models
    ram_gb=$(get_ram_gb)
    vram_gb=$(get_vram_size)
    installed_models=$(get_installed_models)
    
    get_available_models
    
    echo -e "${CYAN}Based on your system specs (${ram_gb}GB RAM, ${vram_gb}GB VRAM):${NC}\n"
    
    # Categories
    local categories=("chat" "coding" "creative" "vision" "embedding")
    
    for category in "${categories[@]}"; do
        echo -e "${BOLD}${MAGENTA}${category^} Models:${NC}"
        
        local models
        models=$(jq -r --arg cat "$category" '.models | to_entries[] | select(.value.category == $cat) | select(.value.ram_req <= '"$ram_gb"') | "\(.key)|\(.value.size)|\(.value.description)"' "$MODELS_DB" 2>/dev/null | head -5)
        
        if [[ -n "$models" ]]; then
            while IFS='|' read -r model size description; do
                local status=""
                if echo "$installed_models" | grep -q "^$model$"; then
                    status="${GREEN}[INSTALLED]${NC}"
                else
                    status="${GRAY}[AVAILABLE]${NC}"
                fi
                echo -e "  ${CYAN}•${NC} ${BOLD}$model${NC} ${GRAY}($size)${NC} $status"
                echo -e "    ${DIM}$description${NC}"
            done <<< "$models"
        else
            echo -e "  ${GRAY}No compatible models found for this category${NC}"
        fi
        echo ""
    done
}

# --- 🔄 Interactive Model Management ---

interactive_model_installer() {
    print_header "${ICON_DOWNLOAD} Interactive Model Installer"
    
    get_available_models
    local categories=("All" "Chat" "Coding" "Creative" "Vision" "Embedding")
    
    multi_choice "Select category:" "${categories[@]}"
    local selected_cat=$?
    
    if [[ $selected_cat -eq 255 ]]; then
        print_error "Invalid selection"
        return 1
    fi
    
    local filter_cat=""
    [[ $selected_cat -ne 0 ]] && filter_cat=$(echo "${categories[$((selected_cat))]}" | tr '[:upper:]' '[:lower:]')
    
    local ram_gb
    ram_gb=$(get_ram_gb)
    
    echo -e "\n${CYAN}Available models for installation:${NC}"
    local model_list=()
    local counter=1
    
    while IFS='|' read -r model size description category ram_req; do
        if [[ -z "$filter_cat" || "$category" == "$filter_cat" ]]; then
            if [[ $ram_req -le $ram_gb ]]; then
                echo -e "${GRAY}[$counter]${NC} ${BOLD}$model${NC} ${GRAY}($size, ${ram_req}GB RAM)${NC}"
                echo -e "    ${DIM}$description${NC}"
                model_list+=("$model")
                ((counter++))
            fi
        fi
    done <<< "$(jq -r '.models | to_entries[] | "\(.key)|\(.value.size)|\(.value.description)|\(.value.category)|\(.value.ram_req)"' "$MODELS_DB" 2>/dev/null)"
    
    if [[ ${#model_list[@]} -eq 0 ]]; then
        print_warning "No compatible models found"
        return 1
    fi
    
    echo -ne "\n${YELLOW}Enter model numbers to install (space-separated, or 'all'):${NC} "
    read -r selection
    
    if [[ "$selection" == "all" ]]; then
        selection=$(seq 1 ${#model_list[@]} | tr '\n' ' ')
    fi
    
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#model_list[@]} ]]; then
            local model="${model_list[$((num-1))]}"
            install_model_with_progress "$model"
        fi
    done
}

install_model_with_progress() {
    local model="$1"
    print_info "Installing $model..."
    log_usage "Installing model: $model"
    
    # Run ollama pull in background and show progress
    (
        ollama pull "$model" 2>&1 | while IFS= read -r line; do
            if [[ "$line" =~ pulling|verifying|writing ]]; then
                echo -ne "\r${CYAN}$line${NC}"
            fi
        done
        echo ""
    )
    
    if ollama list | grep -q "^$model"; then
        print_success "Successfully installed $model"
        # Add to preferred models
        local prefs
        prefs=$(get_config preferred_models)
        if [[ "$prefs" != *"$model"* ]]; then
            jq --arg model "$model" '.preferred_models += [$model]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
    else
        print_error "Failed to install $model"
    fi
}

# --- 🔄 Enhanced Model Switcher ---

smart_model_switcher() {
    print_header "${ICON_SWITCH} Smart Model Switcher"
    
    local installed_models last_used current_model
    installed_models=$(get_installed_models)
    last_used=$(get_config last_used_model)
    
    if [[ -z "$installed_models" ]]; then
        print_warning "No models installed. Install some models first."
        return 1
    fi
    
    # Check if TUI is available and preferred
    if command -v fzf &>/dev/null && [[ "$(get_config ui_mode)" == "tui" ]]; then
        use_fzf_switcher
        return $?
    fi
    
    echo -e "${CYAN}Installed Models:${NC}"
    local model_array=()
    local counter=1
    
    while IFS= read -r model; do
        local info status
        info=$(get_model_info "$model")
        [[ "$model" == "$last_used" ]] && status="${GREEN}[LAST USED]${NC}" || status=""
        
        echo -e "${GRAY}[$counter]${NC} ${BOLD}$model${NC} $status"
        [[ -n "$info" ]] && echo -e "    ${DIM}$info${NC}"
        
        model_array+=("$model")
        ((counter++))
    done <<< "$installed_models"
    
    echo -ne "\n${YELLOW}Select model to run [1-${#model_array[@]}]:${NC} "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#model_array[@]} ]]; then
        current_model="${model_array[$((choice-1))]}"
        save_config last_used_model "$current_model"
        log_usage "Switched to model: $current_model"
        
        print_success "Starting $current_model..."
        echo -e "${DIM}Type '/bye' to exit the model chat${NC}\n"
        
        ollama run "$current_model"
    else
        print_error "Invalid selection"
    fi
}

use_fzf_switcher() {
    local selected_model
    selected_model=$(get_installed_models | fzf --prompt="Select model: " --height=40% --border --preview="echo 'Model: {}' && ollama show {} 2>/dev/null | head -20")
    
    if [[ -n "$selected_model" ]]; then
        save_config last_used_model "$selected_model"
        log_usage "Switched to model (fzf): $selected_model"
        
        print_success "Starting $selected_model..."
        ollama run "$selected_model"
    fi
}

get_model_info() {
    local model="$1"
    # Try to get basic info about the model
    ollama show "$model" 2>/dev/null | grep -E "Parameters|Family|Format" | head -1 | sed 's/^[[:space:]]*//' || echo ""
}

# --- 🔧 Advanced Features ---

model_performance_test() {
    print_header "${ICON_FIRE} Model Performance Testing"
    
    local installed_models
    installed_models=$(get_installed_models)
    
    if [[ -z "$installed_models" ]]; then
        print_warning "No models installed for testing."
        return 1
    fi
    
    echo -e "${CYAN}Select models to test:${NC}"
    local model_array=()
    local counter=1
    
    while IFS= read -r model; do
        echo -e "${GRAY}[$counter]${NC} $model"
        model_array+=("$model")
        ((counter++))
    done <<< "$installed_models"
    
    echo -ne "\n${YELLOW}Enter model numbers (space-separated):${NC} "
    read -r selection
    
    local test_prompt="Explain quantum computing in simple terms."
    
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#model_array[@]} ]]; then
            local model="${model_array[$((num-1))]}"
            echo -e "\n${BOLD}Testing $model...${NC}"
            
            local start_time end_time duration
            start_time=$(date +%s)
            
            # Test the model with a standard prompt
            echo "$test_prompt" | ollama run "$model" > /dev/null 2>&1
            
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            
            echo -e "${GREEN}$model: ${duration}s response time${NC}"
            log_usage "Performance test: $model - ${duration}s"
        fi
    done
}

bulk_model_operations() {
    print_header "${ICON_GEAR} Bulk Model Operations"
    
    local operations=("Update All" "Remove Unused" "Export List" "Import List" "Clear Cache")
    multi_choice "Select operation:" "${operations[@]}"
    local selected_op=$?
    
    case $selected_op in
        0) # Update All
            print_info "Updating all installed models..."
            while IFS= read -r model; do
                print_info "Updating $model..."
                ollama pull "$model" >/dev/null 2>&1 &
                spinner $!
                print_success "$model updated"
            done <<< "$(get_installed_models)"
            ;;
        1) # Remove Unused
            print_info "Finding unused models..."
            local usage_data
            if [[ -f "$USAGE_LOG" ]]; then
                usage_data=$(tail -100 "$USAGE_LOG" | grep "Switched to model" | awk '{print $NF}' | sort | uniq)
                local installed_models
                installed_models=$(get_installed_models)
                
                echo -e "${YELLOW}Models that haven't been used recently:${NC}"
                while IFS= read -r model; do
                    if ! echo "$usage_data" | grep -q "$model"; then
                        echo -e "  • $model"
                        if confirm "Remove $model?"; then
                            ollama rm "$model"
                            print_success "Removed $model"
                        fi
                    fi
                done <<< "$installed_models"
            else
                print_warning "No usage data available"
            fi
            ;;
        2) # Export List
            local export_file="$HOME/ollama-models-$(date +%Y%m%d).txt"
            get_installed_models > "$export_file"
            print_success "Model list exported to $export_file"
            ;;
        3) # Import List
            echo -ne "${YELLOW}Enter path to model list file:${NC} "
            read -r import_file
            if [[ -f "$import_file" ]]; then
                while IFS= read -r model; do
                    [[ -n "$model" ]] && install_model_with_progress "$model"
                done < "$import_file"
            else
                print_error "File not found: $import_file"
            fi
            ;;
        4) # Clear Cache
            if confirm "Clear Ollama cache and temporary files?"; then
                # Clear ollama cache if possible
                if [[ -d "$HOME/.ollama" ]]; then
                    find "$HOME/.ollama" -name "*.tmp" -delete 2>/dev/null
                    print_success "Cleared temporary files"
                fi
                # Clear our own cache
                rm -f "${CONFIG_DIR}/models.json" "${CONFIG_DIR}/vram_size"
                print_success "Cleared application cache"
            fi
            ;;
        *) print_error "Invalid selection" ;;
    esac
}

# --- 🎨 UI Mode Selection ---

setup_ui_mode() {
    print_header "${ICON_MAGIC} UI Mode Configuration"
    
    local tui_available=false
    local dialog_available=false
    
    if command -v fzf &>/dev/null; then
        tui_available=true
        print_success "fzf detected - TUI mode available"
    fi
    
    if command -v dialog &>/dev/null; then
        dialog_available=true
        print_success "dialog detected - Enhanced TUI available"
    fi
    
    echo -e "\n${CYAN}Available UI modes:${NC}"
    echo -e "${GRAY}[1]${NC} CLI Mode (default)"
    
    local modes=("cli")
    local mode_names=("CLI Mode")
    local counter=2
    
    if [[ "$tui_available" == true ]]; then
        echo -e "${GRAY}[$counter]${NC} TUI Mode (with fzf)"
        modes+=("tui")
        mode_names+=("TUI Mode")
        ((counter++))
    fi
    
    if [[ "$dialog_available" == true ]]; then
        echo -e "${GRAY}[$counter]${NC} Dialog Mode (enhanced)"
        modes+=("dialog")
        mode_names+=("Dialog Mode")
        ((counter++))
    fi
    
    if [[ ! "$tui_available" && ! "$dialog_available" ]]; then
        if confirm "Install fzf and dialog for enhanced UI modes?"; then
            case "$(detect_os)" in
                ubuntu|debian) sudo apt install -y fzf dialog ;;
                arch|manjaro) sudo pacman -S --needed fzf dialog ;;
                fedora) sudo dnf install -y fzf dialog ;;
                macos) brew install fzf dialog ;;
                *) print_warning "Please install fzf and dialog manually" ;;
            esac
            
            # Recheck availability
            command -v fzf &>/dev/null && modes+=("tui") && mode_names+=("TUI Mode")
            command -v dialog &>/dev/null && modes+=("dialog") && mode_names+=("Dialog Mode")
        fi
    fi
    
    echo -ne "\n${YELLOW}Select UI mode [1-${#modes[@]}]:${NC} "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#modes[@]} ]]; then
        local selected_mode="${modes[$((choice-1))]}"
        save_config ui_mode "$selected_mode"
        print_success "UI mode set to: ${mode_names[$((choice-1))]}"
        log_usage "UI mode changed to: $selected_mode"
    fi
}

# --- 📊 Usage Analytics ---

show_usage_analytics() {
    print_header "${ICON_STAR} Usage Analytics"
    
    if [[ ! -f "$USAGE_LOG" ]]; then
        print_warning "No usage data available yet"
        return 1
    fi
    
    echo -e "${CYAN}Recent Activity Summary:${NC}\n"
    
    # Most used models
    echo -e "${BOLD}Most Used Models:${NC}"
    grep "Switched to model" "$USAGE_LOG" | awk '{print $NF}' | sort | uniq -c | sort -rn | head -5 | while read -r count model; do
        echo -e "  ${GREEN}$model${NC}: $count times"
    done
    
    echo ""
    
    # Recent installations
    echo -e "${BOLD}Recent Installations:${NC}"
    grep "Installing model" "$USAGE_LOG" | tail -5 | while IFS= read -r line; do
        local date_part model_part
        date_part=$(echo "$line" | awk '{print $1, $2}')
        model_part=$(echo "$line" | awk -F': ' '{print $2}')
        echo -e "  ${CYAN}$model_part${NC} ${GRAY}($date_part)${NC}"
    done
    
    echo ""
    
    # Usage statistics
    local total_switches installs updates
    total_switches=$(grep -c "Switched to model" "$USAGE_LOG" 2>/dev/null || echo "0")
    installs=$(grep -c "Installing model" "$USAGE_LOG" 2>/dev/null || echo "0")
    updates=$(grep -c "updated to" "$USAGE_LOG" 2>/dev/null || echo "0")
    
    echo -e "${BOLD}Statistics:${NC}"
    echo -e "  Model switches: $total_switches"
    echo -e "  Models installed: $installs"
    echo -e "  Updates performed: $updates"
}

# --- 🔍 Model Search & Discovery ---

search_models() {
    print_header "${ICON_BRAIN} Model Search & Discovery"
    
    echo -ne "${YELLOW}Enter search term (name, category, or description):${NC} "
    read -r search_term
    
    if [[ -z "$search_term" ]]; then
        print_error "Please enter a search term"
        return 1
    fi
    
    get_available_models
    
    echo -e "\n${CYAN}Search Results for '$search_term':${NC}\n"
    
    local found=false
    while IFS='|' read -r model size description category ram_req; do
        if [[ "$model" =~ $search_term ]] || [[ "$category" =~ $search_term ]] || [[ "$description" =~ $search_term ]]; then
            found=true
            local installed_status=""
            if get_installed_models | grep -q "^$model$"; then
                installed_status="${GREEN}[INSTALLED]${NC}"
            else
                installed_status="${GRAY}[AVAILABLE]${NC}"
            fi
            
            echo -e "${BOLD}$model${NC} ${GRAY}($size, ${ram_req}GB RAM)${NC} $installed_status"
            echo -e "  ${DIM}Category: $category${NC}"
            echo -e "  ${DIM}$description${NC}"
            echo ""
        fi
    done <<< "$(jq -r '.models | to_entries[] | "\(.key)|\(.value.size)|\(.value.description)|\(.value.category)|\(.value.ram_req)"' "$MODELS_DB" 2>/dev/null)"
    
    if [[ "$found" == false ]]; then
        print_warning "No models found matching '$search_term'"
    fi
}

# --- 🛠️ System Optimization ---

optimize_system() {
    print_header "${ICON_GEAR} System Optimization for AI Workloads"
    
    echo -e "${CYAN}Analyzing system for AI optimization opportunities...${NC}\n"
    
    local ram_gb vram_gb swap_size
    ram_gb=$(get_ram_gb)
    vram_gb=$(get_vram_size)
    
    # Check swap
    if command -v free &>/dev/null; then
        swap_size=$(free -g | awk '/^Swap:/ {print $2}')
    else
        swap_size=0
    fi
    
    echo -e "${BOLD}Optimization Recommendations:${NC}\n"
    
    # RAM optimization
    if [[ $ram_gb -lt 16 ]]; then
        print_warning "Consider upgrading to 16GB+ RAM for better model performance"
        if [[ $swap_size -lt 8 ]]; then
            echo -e "  ${CYAN}•${NC} Current swap: ${swap_size}GB - consider increasing to 8GB+"
            if confirm "Create/increase swap file?"; then
                create_swap_file
            fi
        fi
    else
        print_success "RAM: Adequate for most models"
    fi
    
    # GPU optimization
    if [[ $vram_gb -gt 0 ]]; then
        print_success "GPU: CUDA detected, models can use GPU acceleration"
        if confirm "Optimize GPU memory settings?"; then
            optimize_gpu_settings
        fi
    else
        print_info "GPU: Using CPU inference (consider GPU for faster performance)"
    fi
    
    # System settings
    echo -e "\n${BOLD}System Tuning:${NC}"
    
    # Check for performance governor
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        local current_governor
        current_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        echo -e "  Current CPU governor: $current_governor"
        
        if [[ "$current_governor" != "performance" ]] && confirm "Set CPU governor to performance mode?"; then
            echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
            print_success "CPU governor set to performance"
        fi
    fi
    
    # Ollama environment optimizations
    echo -e "\n${BOLD}Ollama Optimizations:${NC}"
    if confirm "Apply Ollama performance optimizations?"; then
        apply_ollama_optimizations
    fi
}

create_swap_file() {
    print_info "Creating 8GB swap file..."
    
    if [[ "$EUID" -ne 0 ]]; then
        print_error "Root privileges required for swap creation"
        return 1
    fi
    
    # Create swap file
    fallocate -l 8G /swapfile || dd if=/dev/zero of=/swapfile bs=1G count=8
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make permanent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    
    print_success "8GB swap file created and activated"
}

optimize_gpu_settings() {
    print_info "Applying GPU optimizations..."
    
    # Set GPU memory growth for TensorFlow/PyTorch compatibility
    export CUDA_VISIBLE_DEVICES=0
    
    # Ollama GPU settings
    export OLLAMA_GPU_OVERHEAD=0.1
    export OLLAMA_MAX_LOADED_MODELS=3
    
    print_success "GPU optimization settings applied"
    
    # Save to profile
    local shell_profile="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && shell_profile="$HOME/.zshrc"
    
    if confirm "Save GPU optimizations to $shell_profile?"; then
        echo "" >> "$shell_profile"
        echo "# Ollama GPU Optimizations" >> "$shell_profile"
        echo "export CUDA_VISIBLE_DEVICES=0" >> "$shell_profile"
        echo "export OLLAMA_GPU_OVERHEAD=0.1" >> "$shell_profile"
        echo "export OLLAMA_MAX_LOADED_MODELS=3" >> "$shell_profile"
        print_success "Optimizations saved to $shell_profile"
    fi
}

apply_ollama_optimizations() {
    # Set optimal Ollama environment variables
    export OLLAMA_NUM_PARALLEL=2
    export OLLAMA_MAX_QUEUE=10
    export OLLAMA_KEEP_ALIVE=5m
    
    local shell_profile="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && shell_profile="$HOME/.zshrc"
    
    echo "" >> "$shell_profile"
    echo "# Ollama Performance Optimizations" >> "$shell_profile"
    echo "export OLLAMA_NUM_PARALLEL=2" >> "$shell_profile"
    echo "export OLLAMA_MAX_QUEUE=10" >> "$shell_profile"
    echo "export OLLAMA_KEEP_ALIVE=5m" >> "$shell_profile"
    
    print_success "Ollama optimizations applied and saved"
}

# --- 🔄 Backup & Restore ---

backup_restore_menu() {
    print_header "${ICON_GEAR} Backup & Restore"
    
    local options=("Create Backup" "Restore from Backup" "Schedule Auto-Backup" "View Backups")
    multi_choice "Select operation:" "${options[@]}"
    local selected=$?
    
    case $selected in
        0) create_backup ;;
        1) restore_backup ;;
        2) schedule_backup ;;
        3) list_backups ;;
        *) print_error "Invalid selection" ;;
    esac
}

create_backup() {
    local backup_dir="$HOME/.ollama-backups"
    local backup_name="ollama-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$backup_dir/$backup_name"
    
    mkdir -p "$backup_dir"
    mkdir -p "$backup_path"
    
    print_info "Creating backup..."
    
    # Backup model list
    get_installed_models > "$backup_path/models.txt"
    
    # Backup configuration
    cp -r "$CONFIG_DIR" "$backup_path/config" 2>/dev/null || true
    
    # Backup Ollama config if it exists
    [[ -d "$HOME/.ollama" ]] && cp -r "$HOME/.ollama" "$backup_path/ollama-config" 2>/dev/null || true
    
    # Create manifest
    cat > "$backup_path/manifest.json" << EOF
{
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "models": $(jq -R . "$backup_path/models.txt" | jq -s .),
    "version": "$SCRIPT_VERSION"
}
EOF
    
    # Compress backup
    tar -czf "$backup_dir/$backup_name.tar.gz" -C "$backup_dir" "$backup_name"
    rm -rf "$backup_path"
    
    print_success "Backup created: $backup_dir/$backup_name.tar.gz"
    log_usage "Backup created: $backup_name"
}

restore_backup() {
    local backup_dir="$HOME/.ollama-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        print_error "No backups directory found"
        return 1
    fi
    
    echo -e "${CYAN}Available backups:${NC}"
    local backups=()
    local counter=1
    
    for backup in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup" ]]; then
            local backup_name
            backup_name=$(basename "$backup" .tar.gz)
            echo -e "${GRAY}[$counter]${NC} $backup_name"
            backups+=("$backup")
            ((counter++))
        fi
    done
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_error "No backups found"
        return 1
    fi
    
    echo -ne "\n${YELLOW}Select backup to restore [1-${#backups[@]}]:${NC} "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#backups[@]} ]]; then
        local backup_file="${backups[$((choice-1))]}"
        local temp_dir="/tmp/ollama-restore-$"
        
        print_info "Extracting backup..."
        mkdir -p "$temp_dir"
        tar -xzf "$backup_file" -C "$temp_dir"
        
        local backup_name
        backup_name=$(basename "$backup_file" .tar.gz)
        local backup_path="$temp_dir/$backup_name"
        
        if [[ -f "$backup_path/models.txt" ]]; then
            print_info "Restoring models..."
            while IFS= read -r model; do
                [[ -n "$model" ]] && install_model_with_progress "$model"
            done < "$backup_path/models.txt"
        fi
        
        if [[ -d "$backup_path/config" ]]; then
            print_info "Restoring configuration..."
            cp -r "$backup_path/config/"* "$CONFIG_DIR/" 2>/dev/null || true
        fi
        
        rm -rf "$temp_dir"
        print_success "Backup restored successfully"
        log_usage "Backup restored: $backup_name"
    fi
}

list_backups() {
    local backup_dir="$HOME/.ollama-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        print_error "No backups directory found"
        return 1
    fi
    
    echo -e "${CYAN}Backup History:${NC}\n"
    
    for backup in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup" ]]; then
            local backup_name size date
            backup_name=$(basename "$backup" .tar.gz)
            size=$(du -h "$backup" | cut -f1)
            date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || date -r "$backup" '+%Y-%m-%d %H:%M:%S')
            
            echo -e "${BOLD}$backup_name${NC}"
            echo -e "  Size: $size"
            echo -e "  Date: $date"
            echo ""
        fi
    done
}

schedule_backup() {
    print_info "Auto-backup scheduling (requires cron)"
    
    if ! command -v crontab &>/dev/null; then
        print_error "Crontab not available. Please install cron."
        return 1
    fi
    
    local frequencies=("Daily" "Weekly" "Monthly" "Disable")
    multi_choice "Select backup frequency:" "${frequencies[@]}"
    local freq=$?
    
    local cron_entry=""
    case $freq in
        0) cron_entry="0 2 * * * $0 --auto-backup" ;; # Daily at 2 AM
        1) cron_entry="0 2 * * 0 $0 --auto-backup" ;; # Weekly on Sunday at 2 AM
        2) cron_entry="0 2 1 * * $0 --auto-backup" ;; # Monthly on 1st at 2 AM
        3) # Remove existing backup cron
            crontab -l | grep -v "$0 --auto-backup" | crontab -
            print_success "Auto-backup disabled"
            return 0
            ;;
        *) print_error "Invalid selection"; return 1 ;;
    esac
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    print_success "Auto-backup scheduled: ${frequencies[$freq]}"
}

# --- 📊 System Monitoring ---

monitor_system() {
    print_header "${ICON_FIRE} Real-time System Monitoring"
    
    if ! command -v htop &>/dev/null; then
        print_warning "htop not found. Install for better monitoring."
        if confirm "Install htop?"; then
            case "$(detect_os)" in
                ubuntu|debian) sudo apt install -y htop ;;
                arch|manjaro) sudo pacman -S --needed htop ;;
                fedora) sudo dnf install -y htop ;;
                macos) brew install htop ;;
            esac
        fi
    fi
    
    echo -e "${CYAN}System monitoring options:${NC}"
    local options=("Resource Usage" "GPU Monitoring" "Ollama Processes" "Model Performance")
    multi_choice "Select monitoring type:" "${options[@]}"
    local selected=$?
    
    case $selected in
        0)
            if command -v htop &>/dev/null; then
                htop
            else
                top
            fi
            ;;
        1)
            if command -v nvidia-smi &>/dev/null; then
                watch -n 1 nvidia-smi
            else
                print_error "nvidia-smi not available"
            fi
            ;;
        2)
            echo -e "${CYAN}Ollama Processes:${NC}"
            ps aux | grep ollama | grep -v grep
            echo -e "\n${CYAN}Listening on:${NC}"
            netstat -tlnp 2>/dev/null | grep ollama || lsof -i :11434 2>/dev/null
            ;;
        3)
            monitor_model_performance
            ;;
        *) print_error "Invalid selection" ;;
    esac
}

monitor_model_performance() {
    print_info "Model performance monitoring (press Ctrl+C to stop)"
    
    while true; do
        clear
        echo -e "${CYAN}Model Performance Monitor${NC}"
        echo -e "${GRAY}$(date)${NC}\n"
        
        # System resources
        local cpu_usage ram_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        ram_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}')
        
        echo -e "CPU Usage: ${cpu_usage}%"
        echo -e "RAM Usage: ${ram_usage}%"
        
        # GPU if available
        if command -v nvidia-smi &>/dev/null; then
            local gpu_util gpu_mem
            gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
            gpu_mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1 | awk -F', ' '{printf "%.1f", $1/$2*100}')
            echo -e "GPU Usage: ${gpu_util}%"
            echo -e "GPU Memory: ${gpu_mem}%"
        fi
        
        # Ollama processes
        echo -e "\nOllama Processes:"
        ps aux | grep ollama | grep -v grep | awk '{print $2, $3, $4, $11}'
        
        sleep 2
    done
}

# --- 🎯 Main Menu System ---

show_main_menu() {
    local options=(
        "🚀 Quick Start (Install & Setup)"
        "🧠 Smart Model Installer"
        "🔄 Model Switcher"
        "📊 System Analysis"
        "⚙️  System Optimization"
        "🔍 Search Models"
        "📈 Performance Test"
        "🛠️  Bulk Operations"
        "💾 Backup & Restore"
        "📊 Usage Analytics"
        "🎨 UI Configuration"
        "🖥️  System Monitor"
        "❓ Help & Documentation"
        "🚪 Exit"
    )
    for i in "${!options[@]}"; do
        echo -e "${GRAY}[$((i+1))]${NC} ${options[i]}"
    done
    
    echo -ne "\n${YELLOW}Select option ${GRAY}[1-${#options[@]}]:${NC} "
    read -r choice
    
    case $choice in
        1) quick_start ;;
        2) interactive_model_installer ;;
        3) smart_model_switcher ;;
        4) show_enhanced_specs && suggest_models_smart ;;
        5) optimize_system ;;
        6) search_models ;;
        7) model_performance_test ;;
        8) bulk_model_operations ;;
        9) backup_restore_menu ;;
        10) show_usage_analytics ;;
        11) setup_ui_mode ;;
        12) monitor_system ;;
        13) show_help ;;
        14) print_success "Thanks for using Ollama Manager! 🦙"; exit 0 ;;
        *) print_error "Invalid selection" ;;
    esac
}

quick_start() {
    print_header "${ICON_ROCKET} Quick Start Setup"
    
    print_info "Running complete setup and optimization..."
    
    # Initialize everything
    init_config
    check_dependencies
    check_or_install_ollama
    show_enhanced_specs
    
    # Auto-install recommended models
    if confirm "Auto-install recommended models for your system?"; then
        local ram_gb
        ram_gb=$(get_ram_gb)
        
        local recommended_models=()
        if [[ $ram_gb -ge 32 ]]; then
            recommended_models=("llama3.1" "mistral" "codellama" "phi3")
        elif [[ $ram_gb -ge 16 ]]; then
            recommended_models=("llama3.1" "phi3" "codellama")
        elif [[ $ram_gb -ge 8 ]]; then
            recommended_models=("phi3" "gemma2")
        else
            recommended_models=("tinydolphin" "orca-mini")
        fi
        
        for model in "${recommended_models[@]}"; do
            install_model_with_progress "$model"
        done
    fi
    
    # Setup UI preferences
    setup_ui_mode
    
    # Apply optimizations
    if confirm "Apply system optimizations?"; then
        optimize_system
    fi
    
    print_success "Quick start complete! Your system is ready for AI."
    log_usage "Quick start completed"
}

show_help() {
    print_header "${ICON_MAGIC} Help & Documentation"
    
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                   OLLAMA MANAGER                          ║
║                  Advanced Features Guide                  ║
╚═══════════════════════════════════════════════════════════╝

🚀 QUICK START
  • Automatically detects your system capabilities
  • Installs Ollama and recommended models
  • Applies performance optimizations
  • Sets up preferred UI mode

🧠 SMART FEATURES
  • GPU/RAM-based model recommendations
  • Automatic performance optimization
  • Usage analytics and model switching
  • Backup and restore functionality

🎨 UI MODES
  • CLI: Traditional command-line interface
  • TUI: Enhanced interface with fzf
  • Dialog: Full-screen dialog interface

📊 MONITORING
  • Real-time resource monitoring
  • Model performance benchmarking
  • Usage tracking and analytics

🛠️ AUTOMATION
  • Automatic updates
  • Scheduled backups
  • Bulk model operations
  • System optimization

⚙️ CONFIGURATION
  All settings stored in: ~/.config/ollama-manager/
  • config.json: User preferences
  • usage.log: Activity tracking
  • models.json: Model database

🔧 COMMAND LINE OPTIONS
  --auto-backup    : Create automatic backup
  --quick-setup    : Run quick start setup
  --monitor        : Start system monitoring
  --optimize       : Apply system optimizations

📚 KEYBOARD SHORTCUTS
  Ctrl+C          : Cancel current operation
  Tab             : Auto-complete (in compatible shells)
  ↑/↓             : History navigation

🆘 TROUBLESHOOTING
  • Check logs: ~/.config/ollama-manager/usage.log
  • Reset config: rm -rf ~/.config/ollama-manager
  • GPU issues: Run system optimization
  • Model errors: Try bulk update operation

🌐 RESOURCES
  • Ollama: https://ollama.com
  • Models: https://ollama.com/library
  • Issues: Check system analysis

EOF
    
    echo -ne "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --- 🚀 Main Execution ---

main() {
    # Handle command line arguments
    case "${1:-}" in
        --auto-backup)
            create_backup
            exit 0
            ;;
        --quick-setup)
            print_banner
            init_config
            quick_start
            exit 0
            ;;
        --monitor)
            monitor_system
            exit 0
            ;;
        --optimize)
            optimize_system
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version)
            echo "Ollama Manager v$SCRIPT_VERSION"
            exit 0
            ;;
    esac
    
    # Main interactive loop
    print_banner
    init_config
    
    # Check for first run
    if [[ ! -f "$CONFIG_FILE" ]] || [[ "$(get_config ui_mode)" == "" ]]; then
        print_info "First run detected. Running initial setup..."
        quick_start
    fi
    
    # Main menu loop
    while true; do
        echo "Options: "
        show_main_menu
        echo ""
        
        # Brief pause to show any messages
        sleep 1
    done
}

# --- 🎯 Error Handling & Cleanup ---

cleanup() {
    local exit_code=$?
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null
    
    # Clean up temporary files
    rm -f /tmp/ollama-restore-$ 2>/dev/null
    
    if [[ $exit_code -ne 0 ]]; then
        print_error "Script exited with error code: $exit_code"
        log_usage "Script error: exit code $exit_code"
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# --- 🚀 Script Entry Point ---

# Ensure we have required tools
if ! command -v curl &>/dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Some features may be limited.${NC}" >&2
    echo -e "${CYAN}Installing jq...${NC}"
    
    case "$(detect_os)" in
        ubuntu|debian) sudo apt update && sudo apt install -y jq ;;
        arch|manjaro) sudo pacman -S --needed jq ;;
        fedora) sudo dnf install -y jq ;;
        centos|rhel) sudo yum install -y jq ;;
        macos) 
            if command -v brew &>/dev/null; then
                brew install jq
            else
                echo -e "${RED}Please install jq manually or install Homebrew${NC}" >&2
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Please install jq manually for your system${NC}" >&2
            exit 1
            ;;
    esac
fi

# Check if running as root (not recommended)
if [[ $EUID -eq 0 ]]; then
    print_warning "Running as root is not recommended for Ollama operations"
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

# Ensure ollama service directory exists
if [[ ! -d "$HOME/.ollama" ]]; then
    mkdir -p "$HOME/.ollama"
fi

# Start main function
main "$@"