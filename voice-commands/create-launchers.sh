#!/bin/bash
# Create launcher scripts for voice commands
# This can be run standalone to fix broken installations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"

mkdir -p "$PROJECT_BIN_DIR"

echo "Creating launcher scripts in $SCRIPT_DIR..."
echo "Creating symlinks in $PROJECT_BIN_DIR..."

# Vosk launcher
cat > "$SCRIPT_DIR/vosk-dictate" << 'EOF'
#!/bin/bash
# Vosk Dictation (fast, real-time)

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
echo "✓ Created vosk-dictate"

# Vosk stop command
cat > "$SCRIPT_DIR/vosk-dictate-stop" << 'EOF'
#!/bin/bash
# Stop Vosk dictation
nerd-dictation end
EOF
chmod +x "$SCRIPT_DIR/vosk-dictate-stop"
ln -sf "$SCRIPT_DIR/vosk-dictate-stop" "$PROJECT_BIN_DIR/vosk-dictate-stop"
echo "✓ Created vosk-dictate-stop"

# Whisper dictation script
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
echo "✓ Created whisper-dictate"

echo ""
echo "✅ All launcher scripts created!"
echo ""
echo "Launchers location: $SCRIPT_DIR/"
echo "Symlinks location:  $PROJECT_BIN_DIR/"
echo ""
echo "Available commands:"
echo "  vosk-dictate        - Fast real-time dictation"
echo "  vosk-dictate-stop   - Stop Vosk dictation"
echo "  whisper-dictate     - Accurate Whisper dictation"
echo ""
echo "Try: vosk-dictate"

