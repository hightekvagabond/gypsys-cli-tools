
### 📝 TODO: Set Up Desktop & Browser Backup

#### ✅ KDE Plasma Desktop Preferences (Safe for Live Backup)

* Backup these directories:

  * `~/.config/`
  * `~/.local/share/`
* Focus files:

  * `plasma-org.kde.plasma.desktop-appletsrc` — panels, widgets
  * `kwinrc` — virtual desktops
  * `kdeglobals`, `plasmarc` — appearance
  * `kglobalshortcutsrc`, `khotkeysrc` — shortcuts

#### ✅ Brave Browser (Needs Care)

* Backup directory:

  * `~/.config/BraveSoftware/Brave-Browser/`
* Best to **close Brave before backup**
* Optionally use Brave’s own [profile backup flags](https://github.com/brave/brave-browser/wiki/Backing-up-Brave-Data) if scripting:

  ```bash
  brave --user-data-dir=... --backup
  ```

#### ⚙️ Tool Choices

* Use `Syncthing`, `rsync`, `restic`, or `borgbackup`
* Add `.stignore` or exclude patterns for `.cache/`, `*.lock`


