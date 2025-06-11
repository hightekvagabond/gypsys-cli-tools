# Development Setup Guide

This guide explains how to set up the development environment for the Cursor Git Integration Tools project.

## Prerequisites

### Node.js Environment Management

Unlike Python's virtual environments, Node.js uses **nvm** (Node Version Manager) to manage different Node.js versions:

#### Install nvm (if not already installed)

**Linux/macOS:**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
# Reload your shell configuration
source ~/.bashrc  # or ~/.zshrc
```

**Windows:**
```bash
# Install nvm-windows from: https://github.com/coreybutler/nvm-windows
```

#### Use the correct Node.js version
```bash
# Install and use the project's Node.js version
nvm install 18.19.1
nvm use 18.19.1

# Or simply use the .nvmrc file
nvm use
```

## Project Setup

### 1. Clone and Install Dependencies

```bash
# Clone the repository
git clone https://github.com/Imagination-Guild-LLC/gypsys-cli-tools.git
cd gypsys-cli-tools/cursor

# Install all dependencies (root + extension)
npm install
```

### 2. Node.js Dependency Management

**Files equivalent to Python's requirements.txt:**

| Python | Node.js | Purpose |
|--------|---------|---------|
| `requirements.txt` | `package.json` | Lists dependencies and project metadata |
| `pip freeze > requirements.txt` | `package-lock.json` | Locks exact versions |
| `python -m venv venv` | `nvm use` + local `node_modules` | Environment isolation |
| `pip install -r requirements.txt` | `npm install` | Install dependencies |

### 3. Available NPM Scripts

```bash
# Setup git integration
npm run setup

# Development workflow
npm run dev                 # Watch mode for extension development
npm run build-extension     # Build the VSCode extension
npm run install-extension   # Install extension in Cursor
npm run test-extension      # Test the extension

# Maintenance
npm run rebuild-extension   # Rebuild and reinstall extension
```

### 4. Extension Development

The VSCode/Cursor extension is located in `cursor-git-extension/`:

```bash
cd cursor-git-extension

# Install extension-specific dependencies
npm install

# Development commands
npm run compile    # Compile TypeScript
npm run watch      # Watch mode for development
npm run lint       # Run ESLint
npm run test       # Run tests
```

## Dependency Management Best Practices

### Adding Dependencies

```bash
# Add runtime dependency
npm install package-name

# Add development dependency
npm install --save-dev package-name

# Add to extension specifically
cd cursor-git-extension
npm install package-name
```

### Lock File Management

- **`package-lock.json`** - Commit this file (like `requirements.txt` with pinned versions)
- Never manually edit `package-lock.json`
- Use `npm ci` in CI/CD (equivalent to `pip install -r requirements.txt`)

### Cross-Platform Development

```bash
# On a new machine:
nvm use                    # Use correct Node.js version
npm ci                     # Install exact dependency versions
npm run setup              # Configure git integration
```

## Environment Variables

Create a `.env` file for local development:

```bash
# Development settings
NODE_ENV=development
DEBUG=cursor-git-extension:*
```

## Troubleshooting

### Node Version Issues
```bash
nvm ls                     # List installed versions
nvm use 18.19.1           # Switch to project version
node --version            # Verify current version
```

### Permission Issues
```bash
# Fix npm permissions (Linux/macOS)
npm config set prefix ~/.npm-global
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
```

### Clean Install
```bash
# Remove all dependencies and reinstall
rm -rf node_modules package-lock.json
rm -rf cursor-git-extension/node_modules cursor-git-extension/package-lock.json
npm install
```

## IDE Integration

### VSCode/Cursor Settings

Add to `.vscode/settings.json`:
```json
{
  "typescript.preferences.useAliasesForRenames": false,
  "eslint.workingDirectories": ["cursor-git-extension"],
  "typescript.preferences.noSemicolons": "off"
}
```

This setup ensures consistent development environments across different machines, similar to Python's virtual environments but using Node.js native tools. 