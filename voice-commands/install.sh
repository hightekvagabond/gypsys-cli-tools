#!/bin/bash

# Voice Commands Installation Script
# Installs: Nerd Dictation (Vosk + Whisper), Talon Voice
# Platform: Ubuntu/Debian Linux
# Author: AI Assistant for Gypsy
# Date: 2025-12-23

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backup directory
BACKUP_DIR="$HOME/.voice-commands-backup-$(date +%Y%m%d-%H%M%S)"

# Log file - use user's home directory to avoid permission issues
LOG_FILE="$HOME/.voice-commands-install-$(date +%Y%m%d-%H%M%S).log"

# Functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS. This script is for Ubuntu/Debian."
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        warn "This script is designed for Ubuntu/Debian. Your OS: $ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed!"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | grep -oP '\d+\.\d+')
    log "Python version: $PYTHON_VERSION"
    
    # Check pip
    if ! command -v pip3 &> /dev/null; then
        log "pip3 not found, will install..."
        NEED_PIP=1
    fi
    
    # Check microphone
    if ! pactl list sources short | grep -q "input"; then
        warn "No microphone detected! Voice recognition won't work."
        warn "Detected sources:"
        pactl list sources short
    else
        success "Microphone detected"
    fi
    
    # Check disk space (need ~5GB)
    AVAILABLE_SPACE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 5 ]]; then
        warn "Low disk space: ${AVAILABLE_SPACE}GB available. Need at least 5GB."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    success "Prerequisites check passed"
}

create_backup() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing configs if they exist
    if [[ -d "$HOME/.config/nerd-dictation" ]]; then
        log "Backing up existing nerd-dictation config..."
        cp -r "$HOME/.config/nerd-dictation" "$BACKUP_DIR/"
    fi
    
    if [[ -d "$HOME/.talon" ]]; then
        log "Backing up existing Talon config..."
        cp -r "$HOME/.talon" "$BACKUP_DIR/"
    fi
    
    # Save list of currently installed packages
    dpkg -l > "$BACKUP_DIR/installed-packages.txt"
    pip3 list > "$BACKUP_DIR/pip-packages.txt" 2>/dev/null || true
    
    echo "$BACKUP_DIR" > ./.last-backup-location
    success "Backup created at: $BACKUP_DIR"
}

install_system_dependencies() {
    log "Installing system dependencies..."
    log "This will require sudo access."
    
    # List of packages we'll install
    PACKAGES=(
        "python3-pip"
        "python3-setuptools"
        "python3-wheel"
        "python3-dev"
        "python3-venv"      # For virtual environments
        "portaudio19-dev"
        "python3-pyaudio"
        "libportaudio2"
        "sox"
        "libsox-fmt-all"
        "xdotool"           # For sending keystrokes
        "libxdo3"
        "ffmpeg"            # For Whisper
        "git"
        "curl"
        "wget"
        "unzip"             # For extracting models
        "libsndfile1"       # For sounddevice
    )
    
    log "Packages to install: ${PACKAGES[*]}"
    
    # Update package list (don't fail if this has issues)
    log "Updating package lists..."
    if ! sudo apt-get update 2>&1 | tee -a "$LOG_FILE"; then
        warn "apt-get update had some errors, but continuing..."
        warn "You may need to fix your APT repositories later"
    fi
    
    # Install packages (allow to continue even if some fail)
    log "Installing packages..."
    if sudo apt-get install -y "${PACKAGES[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        success "System dependencies installed"
    else
        warn "Some packages failed to install, checking critical dependencies..."
        
        # Check for critical packages
        CRITICAL_MISSING=""
        for pkg in python3-venv xdotool sox ffmpeg git; do
            if ! command -v "$pkg" &> /dev/null && ! dpkg -l | grep -q "^ii.*$pkg"; then
                CRITICAL_MISSING="$CRITICAL_MISSING $pkg"
            fi
        done
        
        if [[ -n "$CRITICAL_MISSING" ]]; then
            error "Critical packages missing:$CRITICAL_MISSING"
            error "Installation cannot continue without these packages."
            error "Please fix your APT repositories and try again."
            exit 1
        else
            warn "Non-critical packages may be missing, but continuing..."
            success "Critical dependencies are present"
        fi
    fi
}

install_nerd_dictation() {
    log "Installing Nerd Dictation..."
    
    # Clone the repo (it's just a Python script, not a proper package)
    NERD_DICT_DIR="$HOME/.local/share/nerd-dictation"
    
    if [[ -d "$NERD_DICT_DIR" ]]; then
        log "Removing old nerd-dictation installation..."
        rm -rf "$NERD_DICT_DIR"
    fi
    
    log "Cloning nerd-dictation from GitHub..."
    git clone https://github.com/ideasman42/nerd-dictation.git "$NERD_DICT_DIR"
    
    # Create a venv for nerd-dictation
    log "Creating virtual environment for nerd-dictation..."
    python3 -m venv "$NERD_DICT_DIR/venv"
    
    # Install dependencies in the venv
    log "Installing nerd-dictation dependencies..."
    "$NERD_DICT_DIR/venv/bin/pip" install --upgrade pip setuptools wheel
    "$NERD_DICT_DIR/venv/bin/pip" install vosk sounddevice
    
    # Create wrapper script in .local/bin
    mkdir -p "$HOME/.local/bin"
    
    cat > "$HOME/.local/bin/nerd-dictation" << 'EOF'
#!/bin/bash
# Wrapper for nerd-dictation
NERD_DICT_DIR="$HOME/.local/share/nerd-dictation"
exec "$NERD_DICT_DIR/venv/bin/python" "$NERD_DICT_DIR/nerd-dictation" "$@"
EOF
    chmod +x "$HOME/.local/bin/nerd-dictation"
    
    # Make sure .local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log "Adding ~/.local/bin to PATH in .bashrc"
        echo '' >> "$HOME/.bashrc"
        echo '# Added by voice-commands installer' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Create config directory
    mkdir -p "$HOME/.config/nerd-dictation"
    
    success "Nerd Dictation installed"
}

install_vosk_model() {
    log "Downloading Vosk speech model..."
    log "Using larger model for better accuracy (~1.8GB download)..."
    log "This may take 5-10 minutes depending on your connection..."
    
    VOSK_MODEL_DIR="$HOME/.local/share/vosk-models"
    mkdir -p "$VOSK_MODEL_DIR"
    
    cd "$VOSK_MODEL_DIR"
    
    # Download English model (large, more accurate)
    VOSK_MODEL="vosk-model-en-us-0.22"
    if [[ ! -d "$VOSK_MODEL" ]]; then
        log "Downloading $VOSK_MODEL..."
        wget -q --show-progress "https://alphacephei.com/vosk/models/${VOSK_MODEL}.zip"
        log "Extracting model..."
        unzip -q "${VOSK_MODEL}.zip"
        rm "${VOSK_MODEL}.zip"
        success "Vosk model downloaded and extracted"
    else
        log "Vosk model already exists, skipping download"
    fi
    
    cd - > /dev/null
}

install_whisper() {
    log "Installing OpenAI Whisper..."
    log "This may take a few minutes..."
    
    # Create a virtual environment for Whisper
    WHISPER_VENV="$HOME/.local/share/voice-commands-whisper-venv"
    
    if [[ -d "$WHISPER_VENV" ]]; then
        log "Whisper venv already exists, removing old one..."
        rm -rf "$WHISPER_VENV"
    fi
    
    log "Creating virtual environment for Whisper..."
    python3 -m venv "$WHISPER_VENV"
    
    # Install whisper in the venv
    log "Installing Whisper in virtual environment..."
    "$WHISPER_VENV/bin/pip" install --upgrade pip setuptools wheel
    "$WHISPER_VENV/bin/pip" install openai-whisper
    
    # Download small model (will happen on first use, but we can trigger it now)
    log "Downloading Whisper 'small' model (this takes a few minutes)..."
    "$WHISPER_VENV/bin/python" -c "import whisper; whisper.load_model('small')" 2>&1 | tee -a "$LOG_FILE" || {
        warn "Whisper model download will happen on first use"
    }
    
    success "Whisper installed in virtual environment"
}

install_talon() {
    log "Installing Talon Voice..."
    
    # Talon is distributed as a binary for Linux
    TALON_DIR="$HOME/.talon"
    TALON_BIN_DIR="$HOME/.local/bin"
    
    mkdir -p "$TALON_BIN_DIR"
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        warn "Talon Voice officially supports x86_64. Your architecture: $ARCH"
        warn "Skipping Talon installation. Install manually from: https://talonvoice.com/"
        return
    fi
    
    # Check if Talon is already installed and working
    if [[ -x "$TALON_DIR/app/talon" ]] || [[ -x "$TALON_DIR/talon" ]]; then
        log "Talon appears to be already installed"
        read -p "Reinstall Talon? This will backup the existing installation. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping Talon installation, keeping existing version"
            success "Using existing Talon installation"
            return
        fi
        
        # Backup existing installation
        log "Backing up existing Talon installation..."
        TALON_BACKUP="$BACKUP_DIR/talon-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$TALON_BACKUP"
        cp -r "$TALON_DIR" "$TALON_BACKUP/" 2>/dev/null || true
        log "Backup saved to: $TALON_BACKUP"
        
        # Remove old installation
        rm -rf "$TALON_DIR"
    fi
    
    # Download Talon
    log "Downloading Talon Voice..."
    TALON_URL="https://talonvoice.com/dl/latest/talon-linux.tar.xz"
    
    cd /tmp
    rm -f talon-linux.tar.xz
    wget -q --show-progress "$TALON_URL" -O talon-linux.tar.xz
    
    log "Extracting Talon..."
    rm -rf talon
    tar -xf talon-linux.tar.xz
    
    # Move to home directory
    mkdir -p "$TALON_DIR"
    mv talon "$TALON_DIR/app"
    
    # Create symlink
    ln -sf "$TALON_DIR/app/talon" "$TALON_BIN_DIR/talon"
    
    # Download community commands (optional but recommended)
    log "Downloading Talon Community commands..."
    if [[ ! -d "$TALON_DIR/user/community" ]]; then
        mkdir -p "$TALON_DIR/user"
        cd "$TALON_DIR/user"
        git clone https://github.com/talonhub/community.git community 2>&1 | tee -a "$LOG_FILE" || {
            warn "Could not download Talon community commands"
        }
    fi
    
    cd /tmp
    rm -f talon-linux.tar.xz
    
    success "Talon Voice installed"
}

create_launcher_scripts() {
    log "Creating launcher scripts..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Use the standalone launcher creation script
    if [[ -x "$SCRIPT_DIR/create-launchers.sh" ]]; then
        "$SCRIPT_DIR/create-launchers.sh" | tee -a "$LOG_FILE"
        success "Launcher scripts created"
        return 0
    fi
    
    # Fallback: create them inline
    PROJECT_BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
    mkdir -p "$PROJECT_BIN_DIR"
    
    # Vosk launcher
    cat > "$SCRIPT_DIR/vosk-dictate" << 'EOF'
#!/bin/bash
# Nerd Dictation with Vosk (fast, real-time)

VOSK_MODEL="$HOME/.local/share/vosk-models/vosk-model-en-us-0.22"

if [[ ! -d "$VOSK_MODEL" ]]; then
    echo "Error: Vosk model not found at: $VOSK_MODEL"
    echo "Run the install script again."
    exit 1
fi

echo "🎤 Starting Vosk Dictation (real-time)"
echo "Speak now. Press Ctrl+C to stop."
echo ""

nerd-dictation begin \
    --vosk-model-dir="$VOSK_MODEL" \
    --simulate-input-tool=XDOTOOL \
    --pulse-device-name=default \
    --full-sentence \
    --numbers-as-digits
EOF
    chmod +x "$SCRIPT_DIR/vosk-dictate"
    ln -sf "$SCRIPT_DIR/vosk-dictate" "$PROJECT_BIN_DIR/vosk-dictate"
    
    # Also create stop command
    cat > "$SCRIPT_DIR/vosk-dictate-stop" << 'EOF'
#!/bin/bash
# Stop Vosk dictation
nerd-dictation end
EOF
    chmod +x "$SCRIPT_DIR/vosk-dictate-stop"
    ln -sf "$SCRIPT_DIR/vosk-dictate-stop" "$PROJECT_BIN_DIR/vosk-dictate-stop"
    
    # Whisper dictation script (separate tool)
    cat > "$SCRIPT_DIR/whisper-dictate" << 'WHISPEREOF'
#!/usr/bin/env python3
"""
Simple Whisper-based dictation tool
Records audio, transcribes with Whisper, types the result
"""
import sys
import os
import tempfile
import subprocess
import signal

# Add Whisper venv to path
WHISPER_VENV = os.path.expanduser("~/.local/share/voice-commands-whisper-venv")
sys.path.insert(0, os.path.join(WHISPER_VENV, "lib/python3.12/site-packages"))

try:
    import whisper
except ImportError:
    print("Error: Whisper not found. Run install script again.")
    sys.exit(1)

def record_audio(output_file, sample_rate=16000):
    """Record audio until Ctrl+C"""
    print("🎤 Recording... Press Ctrl+C when done speaking.")
    print("")
    
    # Use sox to record
    cmd = [
        'rec',
        '-r', str(sample_rate),
        '-c', '1',
        '-b', '16',
        output_file
    ]
    
    try:
        subprocess.run(cmd, check=True)
    except KeyboardInterrupt:
        print("\n✓ Recording stopped")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error recording: {e}")
        return False
    
    return True

def transcribe_audio(audio_file, model_name="small"):
    """Transcribe audio with Whisper"""
    print("🧠 Transcribing with Whisper...")
    
    model = whisper.load_model(model_name)
    result = model.transcribe(audio_file)
    
    return result["text"].strip()

def type_text(text):
    """Type text using xdotool"""
    print(f"⌨️  Typing: {text}")
    print("")
    
    try:
        subprocess.run(['xdotool', 'type', '--', text], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error typing text: {e}")
        return False
    
    return True

def main():
    print("=" * 60)
    print("  Whisper Dictation")
    print("=" * 60)
    print("")
    
    # Create temporary file for audio
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        audio_file = f.name
    
    try:
        # Record audio
        if not record_audio(audio_file):
            return 1
        
        # Check if file has content
        if os.path.getsize(audio_file) < 1000:
            print("Warning: Recording too short, no audio detected")
            return 1
        
        # Transcribe
        text = transcribe_audio(audio_file)
        
        if not text:
            print("No speech detected")
            return 1
        
        print(f"Transcribed: \"{text}\"")
        print("")
        
        # Type it
        type_text(text)
        
        print("✅ Done!")
        
    finally:
        # Clean up
        if os.path.exists(audio_file):
            os.unlink(audio_file)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
WHISPEREOF
    chmod +x "$SCRIPT_DIR/whisper-dictate"
    ln -sf "$SCRIPT_DIR/whisper-dictate" "$PROJECT_BIN_DIR/whisper-dictate"
    
    # Talon start
    cat > "$SCRIPT_DIR/talon-start" << 'EOF'
#!/bin/bash
# Start Talon Voice in background

if pgrep -x "talon" > /dev/null; then
    echo "Talon is already running"
    exit 0
fi

echo "Starting Talon Voice..."
nohup "$HOME/.talon/app/talon" > "$HOME/.talon/talon.log" 2>&1 &
echo "Talon started in background (PID: $!)"
echo "Check status with: talon-status"
echo "View logs with: talon-logs"
EOF
    chmod +x "$SCRIPT_DIR/talon-start"
    ln -sf "$SCRIPT_DIR/talon-start" "$PROJECT_BIN_DIR/talon-start"
    
    # Talon stop
    cat > "$SCRIPT_DIR/talon-stop" << 'EOF'
#!/bin/bash
# Stop Talon Voice

if ! pgrep -x "talon" > /dev/null; then
    echo "Talon is not running"
    exit 0
fi

echo "Stopping Talon Voice..."
pkill -x "talon"
echo "Talon stopped"
EOF
    chmod +x "$SCRIPT_DIR/talon-stop"
    ln -sf "$SCRIPT_DIR/talon-stop" "$PROJECT_BIN_DIR/talon-stop"
    
    # Talon status
    cat > "$SCRIPT_DIR/talon-status" << 'EOF'
#!/bin/bash
# Check Talon Voice status

if pgrep -x "talon" > /dev/null; then
    PID=$(pgrep -x "talon")
    echo "Talon is running (PID: $PID)"
    ps -p $PID -o pid,etime,cmd
else
    echo "Talon is not running"
fi
EOF
    chmod +x "$SCRIPT_DIR/talon-status"
    ln -sf "$SCRIPT_DIR/talon-status" "$PROJECT_BIN_DIR/talon-status"
    
    # Talon logs
    cat > "$SCRIPT_DIR/talon-logs" << 'EOF'
#!/bin/bash
# View Talon logs

LOG_FILE="$HOME/.talon/talon.log"

if [[ -f "$LOG_FILE" ]]; then
    tail -f "$LOG_FILE"
else
    echo "No log file found at: $LOG_FILE"
    exit 1
fi
EOF
    chmod +x "$SCRIPT_DIR/talon-logs"
    ln -sf "$SCRIPT_DIR/talon-logs" "$PROJECT_BIN_DIR/talon-logs"
    
    success "Launcher scripts created in $SCRIPT_DIR and symlinked from $PROJECT_BIN_DIR"
}

create_uninstall_script() {
    log "Creating uninstall script..."
    
    cat > "./uninstall.sh" << 'UNINSTALL_EOF'
#!/bin/bash

# Voice Commands Uninstallation Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "Voice Commands Uninstaller"
echo "=========================="
echo ""
warn "This will remove all voice recognition software and configurations."
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Stop any running services
log "Stopping Talon Voice if running..."
pkill -x "talon" 2>/dev/null || true

# Remove nerd-dictation
log "Removing nerd-dictation..."
rm -f "$HOME/.local/bin/nerd-dictation"
rm -rf "$HOME/.local/share/nerd-dictation"

# Remove Whisper venv
log "Removing Whisper virtual environment..."
rm -rf "$HOME/.local/share/voice-commands-whisper-venv"

# Remove launcher scripts and symlinks
log "Removing launcher scripts..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"

# Remove symlinks from project bin
rm -f "$PROJECT_BIN_DIR/vosk-dictate"
rm -f "$PROJECT_BIN_DIR/vosk-dictate-stop"
rm -f "$PROJECT_BIN_DIR/whisper-dictate"
rm -f "$PROJECT_BIN_DIR/talon-start"
rm -f "$PROJECT_BIN_DIR/talon-stop"
rm -f "$PROJECT_BIN_DIR/talon-status"
rm -f "$PROJECT_BIN_DIR/talon-logs"

# Remove actual scripts from voice-commands directory
rm -f "$SCRIPT_DIR/vosk-dictate"
rm -f "$SCRIPT_DIR/vosk-dictate-stop"
rm -f "$SCRIPT_DIR/whisper-dictate"
rm -f "$SCRIPT_DIR/talon-start"
rm -f "$SCRIPT_DIR/talon-stop"
rm -f "$SCRIPT_DIR/talon-status"
rm -f "$SCRIPT_DIR/talon-logs"

# Ask about removing models and configs
echo ""
read -p "Remove downloaded models and configs? This saves ~2-3GB (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Removing models and configs..."
    rm -rf "$HOME/.local/share/vosk-models"
    rm -rf "$HOME/.config/nerd-dictation"
    rm -rf "$HOME/.talon"
    rm -rf "$HOME/.cache/whisper"
    success "Models and configs removed"
else
    log "Keeping models and configs (you can remove manually later)"
fi

# Restore backup if exists
if [[ -f ./.last-backup-location ]]; then
    BACKUP_LOC=$(cat ./.last-backup-location)
    if [[ -d "$BACKUP_LOC" ]]; then
        echo ""
        log "Backup found at: $BACKUP_LOC"
        read -p "Restore backed up configurations? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Restoring backup..."
            [[ -d "$BACKUP_LOC/nerd-dictation" ]] && cp -r "$BACKUP_LOC/nerd-dictation" "$HOME/.config/"
            [[ -d "$BACKUP_LOC/talon" ]] && cp -r "$BACKUP_LOC/talon" "$HOME/"
            success "Backup restored"
        fi
    fi
fi

echo ""
success "Uninstallation complete!"
log "System packages (portaudio, sox, etc.) were left installed."
log "Remove them manually with: sudo apt-get remove python3-pyaudio sox xdotool"
UNINSTALL_EOF
    
    chmod +x "./uninstall.sh"
    success "Uninstall script created"
}

print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Voice Commands Installation Complete! 🎉              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    success "All voice recognition systems installed successfully!"
    echo ""
    echo "📝 Quick Start Commands:"
    echo ""
    echo "  ${GREEN}vosk-dictate${NC}           - Fast real-time dictation (Vosk)"
    echo "  ${GREEN}vosk-dictate-stop${NC}      - Stop Vosk dictation"
    echo "  ${GREEN}whisper-dictate${NC}        - Accurate dictation (Whisper)"
    echo "  ${GREEN}talon-start${NC}            - Start Talon Voice for advanced commands"
    echo "  ${GREEN}talon-stop${NC}             - Stop Talon Voice"
    echo "  ${GREEN}talon-status${NC}           - Check Talon status"
    echo ""
    echo "📚 Documentation:"
    echo "  ${BLUE}cat README.md${NC}          - Full documentation"
    echo ""
    echo "💾 Backup Location:"
    echo "  ${YELLOW}$BACKUP_DIR${NC}"
    echo ""
    echo "🗑️  To Uninstall:"
    echo "  ${RED}./uninstall.sh${NC}"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "  - ${YELLOW}Restart your terminal${NC} or run: ${GREEN}source ~/.bashrc${NC}"
    echo "  - Voice tools run on HOST (not in devcontainers)"
    echo "  - Make sure to click in your editor to give it focus"
    echo ""
    echo "📄 Installation log: ${BLUE}$LOG_FILE${NC}"
    echo ""
}

# Main installation flow
main() {
    # Check if running as root/sudo
    if [[ $EUID -eq 0 ]]; then
        error "Do NOT run this script with sudo!"
        echo ""
        echo "This script will prompt for sudo when needed (for apt-get only)."
        echo "Audio devices won't work when running as root."
        echo ""
        echo "Run without sudo:"
        echo "  ./install.sh"
        exit 1
    fi
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        Voice Commands Installer for Cursor/VSCode             ║"
    echo "║                                                                ║"
    echo "║  This will install:                                            ║"
    echo "║    • Nerd Dictation + Vosk (fast dictation)                   ║"
    echo "║    • Nerd Dictation + Whisper (accurate dictation)            ║"
    echo "║    • Talon Voice (advanced coding commands)                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log "Starting installation... (this may take 10-15 minutes)"
    log "Log file: $LOG_FILE"
    echo ""
    log "Installation method:"
    log "  • Nerd Dictation → cloned repo with dedicated venv"
    log "  • Whisper → dedicated virtual environment"
    log "  • Talon → binary download"
    echo ""
    
    check_prerequisites
    create_backup
    install_system_dependencies
    install_nerd_dictation
    install_vosk_model
    install_whisper
    install_talon
    create_launcher_scripts
    create_uninstall_script
    
    print_summary
}

# Run main
main "$@"

