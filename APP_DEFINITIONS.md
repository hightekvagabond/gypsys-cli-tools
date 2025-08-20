# Application Definition: AI Best Practices Library

## App Type: CLI Tools & Library
This is a **CLI Tools & Library** project containing best practices, templates, and automation scripts for AI-assisted development.

## Project Characteristics
- **Primary Purpose**: Development best practices library and CLI automation tools
- **Technology Stack**: Shell scripts (bash), Python utilities, Markdown templates
- **Environment**: Cross-platform CLI tools and templates (Linux/macOS/Windows)
- **Deployment**: Git submodule integration, direct script execution
- **User Interaction**: Command-line interface and template consumption

## Current Tools
- **setup-cursor-rules.sh**: Automated cursor rules configuration
- **generate-cursor-rules.sh**: Dynamic rule generation from templates
- **validate-cursor-rules.sh**: Rule validation and compliance checking
- **smart-todo-merge.sh**: AI-assisted TODO.md merging
- **ai-todo-merge.py**: Automated AI API-based TODO merging
- **session-init.sh**: Development session initialization
- **promote-branch.sh**: Git workflow automation
- **Various templates**: Project setup and configuration templates

## Architecture Patterns
- Simple, standalone executable scripts
- Template-based configuration generation
- Modular rule system with numbered priority
- Cross-project reusability via git submodules
- Configuration via environment variables and templates
- Logging to stdout/stderr for pipeline integration
- Error handling with proper exit codes
- Help documentation with `-h/--help` flags

## Development Environment
- Primary development on Linux/bash
- Testing across multiple shell environments
- Version control with git
- Library/tool-focused development workflow

## Git Workflow: Library/CLI Tools
**Workflow**: `feature branch → dev → PR to main`

This is a **library/CLI tools project**, not a production system, so it uses:
- Feature branches for new capabilities
- Dev branch for integration and testing
- Pull requests to main for releases
- No staging/production environments needed
- Semantic versioning for releases

## Deployment Model
- **Distribution**: Git submodule in consuming projects
- **Installation**: Clone/pull submodule, run setup scripts
- **Updates**: Submodule update commands
- **Usage**: Direct script execution from consuming projects 