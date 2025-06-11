#!/bin/bash

# Node.js Environment Setup Script
# Following ai-best-practices for Node.js CLI development

set -e

echo "🚀 Setting up Node.js Environment (ai-best-practices compliant)..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if nvm is installed
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    echo "📦 Installing nvm (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # Load nvm for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    print_success "nvm installed successfully"
else
    print_success "nvm is already installed"
    # Load nvm for current session
    source "$HOME/.nvm/nvm.sh"
fi

# Get required Node.js version from .nvmrc
if [ -f ".nvmrc" ]; then
    REQUIRED_VERSION=$(cat .nvmrc)
    echo "📋 Using Node.js version from .nvmrc: $REQUIRED_VERSION"
else
    REQUIRED_VERSION="20.18.1"
    echo "📋 Using default Node.js version: $REQUIRED_VERSION"
    echo "$REQUIRED_VERSION" > .nvmrc
    print_success "Created .nvmrc with version $REQUIRED_VERSION"
fi

# Install and use the required Node.js version
echo "🔧 Installing Node.js $REQUIRED_VERSION..."
nvm install "$REQUIRED_VERSION"
nvm use "$REQUIRED_VERSION"

# Verify installation
echo "✨ Environment setup complete!"
echo "📊 Versions:"
echo "   Node.js: $(node --version)"
echo "   npm: $(npm --version)"
echo "   nvm: $(nvm --version)"

# Install dependencies if package.json exists
if [ -f "package.json" ]; then
    echo "📦 Installing project dependencies..."
    npm install
    print_success "Dependencies installed"
fi

echo ""
echo "🎉 Node.js environment is ready!"
echo ""
echo "📚 Next steps:"
echo "   • Run 'nvm use' to activate the environment in new terminals"
echo "   • Add 'source ~/.nvm/nvm.sh' to your ~/.bashrc or ~/.zshrc"
echo "   • Use 'npm run rebuild-extension' to build the extension"
echo ""

# Add nvm to shell profile if not already there
if ! grep -q "nvm.sh" ~/.bashrc 2>/dev/null; then
    echo "🔧 Adding nvm to ~/.bashrc..."
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
    print_success "nvm added to ~/.bashrc"
fi

print_success "Node.js environment setup following ai-best-practices is complete!" 