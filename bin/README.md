# CLI Tools Bin Directory

This directory contains links to all the CLI tools I use regularly. Instead of having tools scattered across different directories, I keep them all here for easy PATH management.

## Setup

Add this directory to your PATH in `~/.bashrc`:

```bash
# Add CLI tools to PATH
export PATH="$HOME/dev/gypsys-cli-tools/bin:$PATH"
```

Then reload your shell:
```bash
source ~/.bashrc
```

## Current Tools

- **aws-findinstance.sh** - Find AWS instances
- **check-repos.sh** - Repository management
- **git-private2public.sh** - Convert private repos to public

## Usage

Once in your PATH, run any tool from anywhere:
```bash
aws-findinstance.sh
check-repos.sh
git-private2public.sh
``` 