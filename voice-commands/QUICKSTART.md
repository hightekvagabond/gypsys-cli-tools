# Voice Commands Quick Start

Get up and running with voice dictation in 5 minutes.

## Install

```bash
cd voice-commands
./install.sh
```

**⚠️ Do NOT use sudo!** Script will prompt when needed.

**Time:** ~10-15 minutes (downloads speech models)

After install completes:

```bash
source ~/.bashrc
```

## Try It Out

### Quick Test (Vosk - Fast)

1. Open any text editor (Cursor, VSCode, gedit, etc.)
2. Click in the editor window
3. In a terminal, run:
   ```bash
   nerd-dictate-vosk
   ```
4. Say: "Hello world, this is a test"
5. Press `Ctrl+C`
6. Text should appear! ✨

### Better Accuracy (Whisper)

```bash
nerd-dictate-whisper
```

Say your text, press `Ctrl+C`, wait 2-3 seconds for processing, then text appears.

### Advanced Coding (Talon)

```bash
talon-start
```

Talon runs in background. Say coding commands like:
- "go to line fifty"
- "select function"
- "new line above"

Stop with:
```bash
talon-stop
```

## Devcontainers

Voice tools work with devcontainers automatically!

1. Run voice tool on **HOST** (your Linux machine)
2. Open your project in Cursor with devcontainer
3. Click in editor
4. Start dictating

The voice tool sends keystrokes to whatever has focus, including containerized editors.

See `DEVCONTAINER_SETUP.md` for details.

## Tips

- **Give focus:** Click in the window before dictating
- **Punctuation:** Say "comma", "period", "new line"
- **Fast dictation:** Use Vosk (`nerd-dictate-vosk`)
- **Accurate dictation:** Use Whisper (`nerd-dictate-whisper`)
- **Coding commands:** Use Talon (`talon-start`)

## Commands Reference

```bash
# Vosk (fast, real-time)
nerd-dictate-vosk

# Whisper (accurate, processes after)
nerd-dictate-whisper

# Talon (advanced)
talon-start      # Start Talon
talon-stop       # Stop Talon
talon-status     # Check if running
talon-logs       # View logs
```

## Troubleshooting

**Text not appearing?**
- Click in the window to give it focus
- Check voice tool is running: `ps aux | grep nerd`

**Poor accuracy?**
- Use Whisper instead of Vosk
- Check microphone levels in system settings
- Make sure room is quiet

**Command not found?**
- Run: `source ~/.bashrc`
- Check PATH: `echo $PATH | grep .local/bin`

## More Info

- Full documentation: `README.md`
- Devcontainer setup: `DEVCONTAINER_SETUP.md`
- Uninstall: `./uninstall.sh`

## Examples

### Writing a function comment

```bash
nerd-dictate-vosk
```

Say: "slash slash This function validates user input and returns true if valid"

Result:
```python
// This function validates user input and returns true if valid
```

### Writing documentation

```bash
nerd-dictate-whisper
```

Say a longer paragraph about your code, press Ctrl+C when done.

### Using Talon for code

```bash
talon-start
```

Say: "go to line fifty" → cursor jumps to line 50  
Say: "select word" → selects current word  
Say: "delete line" → deletes current line

---

**That's it!** You're ready to code by voice. 🎤

