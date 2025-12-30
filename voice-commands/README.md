# Voice Commands for Cursor/VSCode

This directory contains setup scripts for three different speech recognition systems that work with Cursor, VSCode, and other applications - even when running in devcontainers.

## 🎯 Overview

All three systems work **100% offline** and run on your **HOST machine** (not in containers), sending keyboard input to whatever application has focus.

### The Three Systems

1. **Nerd Dictation + Vosk** (Fast & Light)
   - Best for: Quick dictation, comments, documentation
   - Speed: Fast (real-time)
   - Accuracy: Good (85-90%)
   - Resource usage: Light (< 500MB RAM)

2. **Nerd Dictation + Whisper** (Accurate & Smart)
   - Best for: Accurate dictation, complex text
   - Speed: Slower (processes after you finish speaking)
   - Accuracy: Excellent (95%+)
   - Resource usage: Heavy (1-2GB RAM, benefits from GPU)

3. **Talon Voice** (Power User & Coding)
   - Best for: Advanced coding commands, custom voice macros
   - Speed: Real-time
   - Accuracy: Excellent with training
   - Resource usage: Medium
   - Special: Supports custom commands for code navigation, refactoring, etc.

## 📋 Prerequisites

- Ubuntu/Debian-based Linux (you're on Ubuntu 24.04 ✅)
- Microphone (your Blue Yeti is detected ✅)
- Python 3.10+ (installed ✅)
- PipeWire/PulseAudio (you have PipeWire ✅)
- ~5GB disk space for models

## 🚀 Quick Start

### 1. Install Everything

```bash
cd voice-commands
./install.sh
```

**⚠️ Important:** Do NOT run with `sudo`! The script will ask for sudo when needed (only for apt packages). Audio won't work if you run the whole script as root.

This will:
- Install all dependencies
- Download speech models
- Set up all three systems
- Create convenient launcher scripts
- Back up any existing configurations

**Installation takes ~10-15 minutes** (mostly downloading speech models)

### 2. Test Your Setup

After installation, test each system:

```bash
# Test Nerd Dictation with Vosk (fast)
nerd-dictate-vosk

# Speak something, then press Ctrl+C to stop
# Your speech should appear as text wherever your cursor is
```

```bash
# Test Nerd Dictation with Whisper (accurate)
nerd-dictate-whisper

# Speak something, press Ctrl+C to finish
# Takes a moment to process, then text appears
```

```bash
# Test Talon Voice
talon-start

# Talon runs in background - say "help alphabet" to test
# Use "talon-stop" to stop it
```

## 🎮 Usage

### Nerd Dictation (Quick On/Off)

**With Vosk (fast, real-time):**
```bash
nerd-dictate-vosk        # Start listening
# Speak your text...
# Press Ctrl+C to stop
```

**With Whisper (accurate, processes after):**
```bash
nerd-dictate-whisper     # Start listening
# Speak your text...
# Press Ctrl+C to finish and process
```

**Pro tip:** Create keyboard shortcuts for these commands in your desktop environment!

### Talon Voice (Always-On Service)

```bash
talon-start              # Start Talon in background
talon-stop               # Stop Talon
talon-status             # Check if Talon is running
talon-logs               # View Talon logs
```

Talon is more sophisticated - learn commands at: https://talon.wiki/

## 🐳 Devcontainer Usage

### How It Works

When you're working in a devcontainer:
1. **Voice recognition runs on HOST** (your Linux system)
2. **Text is sent as keyboard input** to whatever has focus
3. **Devcontainer receives the text** just like regular typing
4. **No special configuration needed** in most cases!

### Why This Works

The voice tools use your system's input method to send text, so from the container's perspective, you're just typing really fast. Your cursor in Cursor/VSCode (even in a devcontainer) receives the text normally.

### Testing in Devcontainer

1. Open Cursor/VSCode with a devcontainer
2. Click in an editor window (give it focus)
3. Run `nerd-dictate-vosk` on your HOST terminal
4. Speak some text
5. Watch it appear in your container-based editor!

### Audio Device Passthrough (Optional)

If you want to run voice recognition **inside** a devcontainer (not recommended), you'd need to add to `.devcontainer/devcontainer.json`:

```json
{
  "runArgs": [
    "--device=/dev/snd",
    "-v", "/run/user/1000/pipewire-0:/run/user/1000/pipewire-0"
  ],
  "mounts": [
    "source=/run/user/1000/pulse,target=/run/user/1000/pulse,type=bind"
  ]
}
```

**However, we recommend running voice tools on the HOST** - it's simpler and more reliable.

## 🎯 Which One Should I Use?

### For Quick Comments/Documentation
→ **Nerd Dictation + Vosk**
- Fast, real-time
- Good enough accuracy
- Low resource usage

### For Important Text (Emails, Docs)
→ **Nerd Dictation + Whisper**
- Best accuracy
- Worth the extra processing time
- Can handle accents/complex speech better

### For Serious Voice Coding
→ **Talon Voice**
- Learn custom commands
- Navigate code by voice
- "go to line 50", "select function", etc.
- Requires investment in learning
- Very powerful once mastered

## 🔧 Configuration

### Nerd Dictation

Config location: `~/.config/nerd-dictation/`

```bash
# Edit Vosk settings
nano ~/.config/nerd-dictation/nerd-dictation-vosk.conf

# Edit Whisper settings
nano ~/.config/nerd-dictation/nerd-dictation-whisper.conf
```

### Talon Voice

Config location: `~/.talon/`

Visit https://talon.wiki/ for extensive customization guides.

### Choosing Different Whisper Models

Whisper comes in different sizes (tradeoff: speed vs accuracy):
- `tiny` - Fastest, least accurate
- `base` - Fast, decent accuracy
- `small` - Balanced (default install)
- `medium` - Slow, very accurate
- `large` - Slowest, best accuracy

To change model:
```bash
# Edit the whisper model in launcher script
nano $(which nerd-dictate-whisper)
# Change --model small to --model medium, etc.
```

## 🗑️ Uninstallation

```bash
cd voice-commands
./uninstall.sh
```

This will:
- Remove all installed packages
- Clean up configuration files
- Restore backed-up configurations
- Remove downloaded models

## 🐛 Troubleshooting

### "No microphone detected"

```bash
# List audio sources
pactl list sources short

# Test recording
arecord -d 5 test.wav && aplay test.wav
```

### "Nerd Dictation not found"

```bash
# Check if it's in PATH
echo $PATH | grep .local/bin

# Add to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### "Talon won't start"

```bash
# Check logs
talon-logs

# Verify installation
ls -la ~/.talon/
```

### "Text not appearing in devcontainer"

- Make sure the devcontainer window has **focus** (click in it)
- Check if voice tool is actually running on HOST
- Try in a regular editor first to verify setup

## 📚 Resources

- **Nerd Dictation:** https://github.com/ideasman42/nerd-dictation
- **Vosk Models:** https://alphacephei.com/vosk/models
- **Whisper:** https://github.com/openai/whisper
- **Talon Voice:** https://talonvoice.com/
- **Talon Wiki:** https://talon.wiki/

## 💡 Pro Tips

1. **Use keyboard shortcuts** - Bind `nerd-dictate-vosk` to a hotkey for instant dictation
2. **Create custom Talon commands** - "insert todo comment", "new function", etc.
3. **Punctuation in Vosk/Whisper** - Say "comma", "period", "new line" explicitly
4. **Background noise** - Whisper handles it better than Vosk
5. **Training Talon** - Spend time training it with your voice for best results

## 🤝 Contributing

Found a better configuration or useful Talon commands for coding? Feel free to add them to this directory!

---

**Note:** All voice recognition happens on your local machine. No voice data is sent to external servers.

