# Voice Commands in Devcontainers

This guide explains how to use voice recognition with Cursor/VSCode when working in devcontainers.

## 🎯 TL;DR - The Easy Way (Recommended)

**Run voice tools on your HOST machine, not in the container.**

The voice recognition tools will send text as keyboard input to whatever has focus - including applications running in containers. This is the simplest and most reliable approach.

## 🔧 How It Works

### The Flow

```
┌─────────────────────────────────────────────────┐
│  HOST SYSTEM (Your Linux)                       │
│  ┌─────────────────────────────────┐            │
│  │ Voice Recognition Tool          │            │
│  │ (Vosk/Whisper/Talon)            │            │
│  │                                 │            │
│  │ Listens to microphone           │            │
│  │ Converts speech → text          │            │
│  │ Sends as keyboard input         │            │
│  └──────────────┬──────────────────┘            │
│                 │                                │
│                 │ Uses xdotool/ydotool           │
│                 │ to send keystrokes             │
│                 ▼                                │
│  ┌─────────────────────────────────┐            │
│  │ Cursor/VSCode Window            │            │
│  │ ┌─────────────────────────────┐ │            │
│  │ │   DEVCONTAINER              │ │            │
│  │ │                             │ │            │
│  │ │   Receives text as if       │ │            │
│  │ │   you typed it normally     │ │            │
│  │ └─────────────────────────────┘ │            │
│  └─────────────────────────────────┘            │
└─────────────────────────────────────────────────┘
```

### Why This Works

1. Voice recognition runs on **HOST** with access to your microphone
2. Tool converts speech to text
3. Tool uses **xdotool** (or similar) to simulate keyboard input
4. Cursor/VSCode window receives the keystrokes
5. **Devcontainer receives input exactly like regular typing**
6. No special configuration needed!

## 🚀 Usage Guide

### Step 1: Install Voice Tools on HOST

```bash
# On your HOST machine (not in devcontainer)
cd /path/to/gypsys-cli-tools/voice-commands
./install.sh
```

### Step 2: Start Your Devcontainer

```bash
# Open your project in Cursor/VSCode
cursor your-project/

# Open in devcontainer (Cmd+Shift+P → "Reopen in Container")
```

### Step 3: Use Voice Commands

**In a separate HOST terminal** (not the devcontainer terminal):

```bash
# Start dictation with Vosk (fast)
nerd-dictate-vosk

# OR use Whisper (more accurate)
nerd-dictate-whisper

# OR start Talon for advanced commands
talon-start
```

### Step 4: Focus & Speak

1. **Click in your Cursor editor window** (give it focus)
2. **Speak your text**
3. Watch it appear in your editor running in the devcontainer!

## 📋 Testing Checklist

Test that everything works:

- [ ] Install voice tools on HOST
- [ ] Start a devcontainer project
- [ ] Open a file in the editor
- [ ] Run `nerd-dictate-vosk` in HOST terminal
- [ ] Click in editor window (give focus)
- [ ] Say: "Hello world, this is a test"
- [ ] Press Ctrl+C to stop dictation
- [ ] Verify text appears in editor

If this works, you're all set! ✅

## 🔧 Advanced: Running Voice Tools INSIDE Devcontainer

**⚠️  Not Recommended** - but possible if you really need it.

### Why You Probably Don't Want This

- More complex setup
- Need to pass through audio devices
- Container must have access to X11/display
- Harder to debug
- Voice tools may not have permissions

### If You Really Want To Do This

Add to your `.devcontainer/devcontainer.json`:

```json
{
  "name": "Your Dev Container",
  
  "runArgs": [
    // Pass through sound devices
    "--device=/dev/snd",
    
    // Pass through PulseAudio/PipeWire
    "-v", "/run/user/1000/pipewire-0:/run/user/1000/pipewire-0",
    "-v", "/run/user/1000/pulse:/run/user/1000/pulse",
    
    // X11 for xdotool (if needed)
    "--env", "DISPLAY=${env:DISPLAY}",
    "-v", "/tmp/.X11-unix:/tmp/.X11-unix"
  ],
  
  "mounts": [
    // Mount PulseAudio socket
    "source=/run/user/${localEnv:UID}/pulse,target=/run/user/1000/pulse,type=bind",
    
    // Mount home directory with voice configs (optional)
    "source=${localEnv:HOME}/.local/share/vosk-models,target=/home/vscode/.local/share/vosk-models,type=bind,readonly"
  ],
  
  "containerEnv": {
    "PULSE_SERVER": "unix:/run/user/1000/pulse/native"
  },
  
  "postCreateCommand": "bash /workspaces/your-project/voice-commands/install.sh"
}
```

### Testing Audio Passthrough

Inside the devcontainer:

```bash
# Test if sound devices are accessible
ls -la /dev/snd/

# Test recording (requires arecord in container)
arecord -d 3 test.wav && aplay test.wav

# Check PulseAudio/PipeWire
pactl list sources short
```

## 🐛 Troubleshooting

### Voice tool works on host but not in devcontainer

**Problem:** Text doesn't appear when dictating.

**Solution:**
1. Make sure editor window **has focus** (click in it)
2. Check voice tool is actually running: `ps aux | grep nerd-dictation`
3. Test in a regular text editor first (like gedit) to verify setup
4. Check xdotool is working: `xdotool type "test"`

### Can't access microphone in devcontainer

**Problem:** Running voice tools inside container, mic not found.

**Solution:**
1. **Recommended:** Run voice tools on HOST instead
2. If you must run in container:
   - Check device passthrough: `ls -la /dev/snd/`
   - Verify audio socket: `ls -la /run/user/1000/pulse/`
   - Check permissions on audio devices

### xdotool: command not found in devcontainer

**Problem:** Devcontainer doesn't have xdotool installed.

**Solution:**
```bash
# Inside devcontainer, install xdotool
sudo apt-get update && sudo apt-get install -y xdotool

# OR add to your Dockerfile/devcontainer features
```

### Text appears in wrong window

**Problem:** Dictated text goes to terminal instead of editor.

**Solution:**
- **Click in the editor** before starting to speak
- xdotool sends to whatever window has focus
- You can alt-tab to give focus before dictating

### Latency/delay in text appearance

**Problem:** Text appears slowly or with delay.

**Solution:**
- **Vosk** is real-time, should be instant
- **Whisper** processes after you finish speaking (this is normal)
- **Talon** is real-time
- If using Whisper and want real-time, switch to Vosk

### Voice recognition not working well

**Problem:** Poor accuracy or not recognizing words.

**Solution:**
1. Check microphone levels: `pavucontrol` or system settings
2. Test recording quality: `arecord -d 5 test.wav && aplay test.wav`
3. Try different microphone (your Blue Yeti should be excellent)
4. Use Whisper for better accuracy (but slower)
5. Train Talon with your voice for best results

## 💡 Pro Tips for Devcontainer Usage

### 1. Keyboard Shortcut for Voice

Create a system keyboard shortcut to run `nerd-dictate-vosk`:

```bash
# In KDE/Plasma System Settings:
# Shortcuts → Custom Shortcuts → Add Command
# Command: /home/gypsy/.local/bin/nerd-dictate-vosk
# Shortcut: Ctrl+Alt+V (or whatever you prefer)
```

### 2. Terminal vs Editor

- Voice tools send to **focused window**
- If you want text in terminal: click terminal, then dictate
- If you want text in editor: click editor, then dictate

### 3. Multiple Projects

- Voice tools run on **HOST** once
- Work across **all** devcontainers simultaneously
- No need to install per-project

### 4. Performance

- Voice recognition on HOST = better performance
- No overhead in devcontainer
- Doesn't consume container resources

### 5. Stopping/Starting

```bash
# Terminal 1: Your voice tool (HOST)
nerd-dictate-vosk

# Terminal 2: Your devcontainer work
# Both can run simultaneously

# Stop dictation: Ctrl+C in Terminal 1
```

## 📚 Examples

### Example 1: Writing Code Comments

```bash
# Start voice dictation
nerd-dictate-vosk

# Click in your editor, then say:
"slash slash This function calculates the fibonacci sequence"

# Press Ctrl+C to stop
# Result: // This function calculates the fibonacci sequence
```

### Example 2: Writing Documentation

```bash
# Use Whisper for better accuracy
nerd-dictate-whisper

# Say a longer paragraph, then Ctrl+C
# Whisper processes it and outputs high-quality text
```

### Example 3: Using Talon for Code Navigation

```bash
# Start Talon
talon-start

# In editor, say:
"go to line fifty"
"select function"
"delete line"
"new line above"

# Stop Talon
talon-stop
```

## 🔗 Related Documentation

- Main README: `README.md`
- Installation Script: `install.sh`
- Uninstall Script: `uninstall.sh`

## ❓ Still Having Issues?

1. Check the main README troubleshooting section
2. Test voice tools **outside** devcontainer first
3. Verify basic recording works: `arecord -d 5 test.wav`
4. Check focus is on correct window
5. Try with a simple text editor (gedit, etc.) to isolate the issue

---

**Remember:** HOST-based voice recognition → sends keystrokes → devcontainer receives them naturally. Keep it simple!

