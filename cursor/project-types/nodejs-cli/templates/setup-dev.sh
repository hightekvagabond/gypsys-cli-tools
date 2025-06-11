#!/bin/bash

# Node.js CLI Development Setup Script
# This script sets up a complete Node.js CLI development environment

set -e  # Exit on any error

echo "🚀 Setting up Node.js CLI Development Environment..."

# Check if nvm is installed
if ! command -v nvm &> /dev/null; then
    echo "⚠️  nvm (Node Version Manager) not found."
    echo "📦 Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    echo "✅ nvm installed successfully"
fi

# Use Node.js version from .nvmrc if it exists
if [ -f ".nvmrc" ]; then
    echo "📋 Using Node.js version from .nvmrc..."
    nvm install
    nvm use
else
    echo "📋 Installing recommended Node.js version (18.19.1)..."
    nvm install 18.19.1
    nvm use 18.19.1
fi

echo "🔧 Current Node.js version: $(node --version)"
echo "📦 Current npm version: $(npm --version)"

# Install dependencies
if [ -f "package.json" ]; then
    echo "📦 Installing project dependencies..."
    npm ci 2>/dev/null || npm install
    echo "✅ Dependencies installed successfully"
else
    echo "⚠️  No package.json found. Make sure to create one or copy from templates."
fi

# Set up git hooks (if pre-commit is configured)
if command -v pre-commit &> /dev/null && [ -f ".pre-commit-config.yaml" ]; then
    echo "🪝 Setting up git hooks with pre-commit..."
    pre-commit install
    echo "✅ Git hooks configured"
fi

# Create common directories if they don't exist
echo "📁 Creating project directories..."
mkdir -p src/{commands,utils,types}
mkdir -p tests
mkdir -p bin
mkdir -p dist

# Make CLI executable if it exists
if [ -f "bin/cli.js" ]; then
    chmod +x bin/cli.js
    echo "✅ CLI script made executable"
fi

# Run type checking
if [ -f "tsconfig.json" ] && command -v tsc &> /dev/null; then
    echo "🔍 Running TypeScript type check..."
    npm run typecheck 2>/dev/null || npx tsc --noEmit || echo "⚠️  Type check failed - review your TypeScript setup"
fi

# Run linting
if command -v eslint &> /dev/null || [ -f "node_modules/.bin/eslint" ]; then
    echo "🧹 Running ESLint..."
    npm run lint 2>/dev/null || npx eslint src --ext .ts || echo "⚠️  Linting found issues - run 'npm run lint:fix' to auto-fix"
fi

# Run tests if they exist
if [ -d "tests" ] && [ "$(ls -A tests)" ]; then
    echo "🧪 Running tests..."
    npm test 2>/dev/null || echo "⚠️  Tests failed - review your test setup"
fi

echo ""
echo "🎉 Development environment setup complete!"
echo ""
echo "🚀 Next steps:"
echo "   1. Review and customize package.json"
echo "   2. Start development with: npm run dev"
echo "   3. Build the project with: npm run build"
echo "   4. Run tests with: npm test"
echo ""
echo "📚 Useful commands:"
echo "   npm run dev          - Start development server"
echo "   npm run build        - Build for production"
echo "   npm run test         - Run tests"
echo "   npm run lint         - Check code style"
echo "   npm run lint:fix     - Fix code style issues"
echo "   npm run format       - Format code with Prettier"
echo ""

# Display current Node.js and npm versions
echo "🔧 Environment:"
echo "   Node.js: $(node --version)"
echo "   npm: $(npm --version)"
echo "   TypeScript: $(npx tsc --version 2>/dev/null || echo 'Not installed')"
echo ""

# Check if project is ready to run
if [ -f "package.json" ] && [ -d "node_modules" ]; then
    echo "✅ Project is ready for development!"
    
    # Try to show available npm scripts
    echo ""
    echo "📋 Available npm scripts:"
    npm run 2>/dev/null | grep -E "^\s+[a-zA-Z]" || echo "   Run 'npm run' to see available scripts"
else
    echo "⚠️  Project setup incomplete. Make sure package.json exists and dependencies are installed."
fi 