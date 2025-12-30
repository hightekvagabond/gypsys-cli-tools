# Fix Brave Browser File Dialog Issue

## Problem
Brave browser hangs when trying to upload/download files because GTK applications (like Brave) can't properly use Dolphin's Qt file dialogs.

## Solution

I've already removed the problematic `GTK_USE_PORTAL` setting from your `~/.profile`. Now you need to:

### Step 1: Install Nautilus (GTK file manager)
This provides GTK file dialogs that Brave and other GTK apps can use:

```bash
sudo apt-get install -y nautilus
```

### Step 2: Restart your session
You need to log out and log back in (or reboot) for the changes to take effect.

### Step 3: Test
After restarting, try uploading/downloading a file in Brave. It should work now.

## What this fixes

- ✅ Removes `GTK_USE_PORTAL` which was causing GTK apps to try to use Qt dialogs
- ✅ Keeps Dolphin as your default file manager for opening folders
- ✅ GTK apps (like Brave) will use GTK file dialogs (Nautilus-based)
- ✅ Dolphin still works normally when you open it directly

## How it works

- **Dolphin** = Default for opening folders (when you double-click a folder)
- **Nautilus** = Provides GTK file dialogs for GTK applications (Brave, Firefox, etc.)
- Both can coexist - Dolphin for browsing, Nautilus dialogs for GTK apps

## Optional: If you don't want Nautilus

If you prefer not to install Nautilus, you can try:
1. Keep GTK_USE_PORTAL unset (already done)
2. Brave should use its own built-in file dialog

But installing Nautilus is the most reliable solution.

