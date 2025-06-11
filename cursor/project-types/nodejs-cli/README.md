# Node.js CLI Project Best Practices

**For:** Command-line tools, automation scripts, build tools, and terminal-based applications

## 🎯 When to Use This Project Type

✅ **Perfect for:**
- Command-line utilities and tools
- Build and deployment automation
- Developer tools and CLIs
- API clients and testing tools
- File processing and transformation tools
- CI/CD pipeline tools

✅ **Key Identifiers:**
- Has `package.json` with dependencies
- Primary interface is command-line
- Uses Node.js CLI frameworks like `commander.js`, `yargs`, or `oclif`
- Focus on automation rather than web interfaces

## 🚀 Quick Setup

### 1. **Node Version Management (MANDATORY)**

**Every Node.js project MUST use a consistent Node.js version:**

```bash
# Install nvm (Node Version Manager) if not already installed
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Use project's Node.js version
nvm install 18.19.1
nvm use 18.19.1

# Or use .nvmrc file
nvm use
```

### 2. **Dependency Management**

```bash
# Install dependencies (equivalent to pip install -r requirements.txt)
npm install

# Or for exact version matching (CI/CD recommended)
npm ci
```

### 3. **Cursor Integration (Auto-configure environment)**

Copy the Cursor configuration for optimal Node.js development:

```bash
cp ai-best-practices/project-types/nodejs-cli/cursor-setup/.vscode/settings.json .vscode/
cp ai-best-practices/project-types/nodejs-cli/templates/.nvmrc ./
```

### 4. **Project Templates**

```bash
# Copy essential files
cp ai-best-practices/project-types/nodejs-cli/templates/package.json ./
cp ai-best-practices/project-types/nodejs-cli/templates/.gitignore ./
cp ai-best-practices/project-types/nodejs-cli/templates/.nvmrc ./
cp ai-best-practices/project-types/nodejs-cli/templates/tsconfig.json ./
```

## 📁 Recommended Project Structure

```
your-nodejs-cli/
├── node_modules/             # Dependencies (auto-created, never commit)
├── src/                      # Source code
│   ├── index.ts             # CLI entry point
│   ├── commands/            # CLI command modules
│   ├── utils/               # Utility functions
│   └── types/               # TypeScript type definitions
├── dist/                    # Compiled output (auto-created)
├── tests/                   # Test files
│   ├── index.test.ts
│   └── commands.test.ts
├── bin/                     # Executable scripts
│   └── cli.js              # CLI entry script
├── package.json             # Dependencies and scripts
├── package-lock.json        # Locked dependency versions
├── tsconfig.json           # TypeScript configuration
├── .nvmrc                  # Node.js version specification
├── .gitignore              # Ignores node_modules/ and build files
├── .vscode/settings.json   # Cursor/VSCode configuration
├── README.md               # Project documentation
└── DEVELOPMENT.md          # Development setup guide
```

## 🛠️ Essential Dependencies

### **Core CLI Dependencies**
```json
// package.json dependencies
{
  "dependencies": {
    "commander": "^11.0.0",      // CLI framework
    "chalk": "^5.3.0",           // Terminal colors
    "inquirer": "^9.2.0",        // Interactive prompts
    "ora": "^7.0.0",             // Loading spinners
    "fs-extra": "^11.1.0",       // Enhanced filesystem
    "axios": "^1.6.0",           // HTTP client
    "dotenv": "^16.3.0",         // Environment variables
    "zod": "^3.22.0"             // Schema validation
  }
}
```

### **Development Dependencies**
```json
// package.json devDependencies
{
  "devDependencies": {
    "@types/node": "^18.19.0",           // Node.js types
    "@types/fs-extra": "^11.0.0",        // fs-extra types
    "typescript": "^5.2.0",              // TypeScript compiler
    "ts-node": "^10.9.0",                // TypeScript execution
    "@typescript-eslint/eslint-plugin": "^6.0.0",  // TypeScript linting
    "@typescript-eslint/parser": "^6.0.0",         // TypeScript parser
    "eslint": "^8.50.0",                 // JavaScript linting
    "prettier": "^3.0.0",                // Code formatting
    "jest": "^29.7.0",                   // Testing framework
    "@types/jest": "^29.5.0",            // Jest types
    "ts-jest": "^29.1.0",                // TypeScript Jest
    "nodemon": "^3.0.0"                  // Development file watcher
  }
}
```

## 🎯 Node.js Environment Best Practices

### **🚨 CRITICAL: Node Version Management Rules**

1. **ALWAYS use `.nvmrc` to specify Node.js version**
2. **NEVER commit `node_modules/` directory to git**
3. **ALWAYS commit `package-lock.json` for version locking**
4. **Use `npm ci` in CI/CD for reproducible builds**

### **Cursor Auto-Configuration Setup**

The `.vscode/settings.json` file ensures:
- ✅ TypeScript compilation and IntelliSense
- ✅ ESLint and Prettier integration
- ✅ Node.js debugging configuration
- ✅ Auto-formatting on save
- ✅ Workspace-specific Node.js settings

### **NPM Scripts (Development Workflow)**

Essential scripts in `package.json`:
```json
{
  "scripts": {
    "dev": "nodemon src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "jest",
    "test:watch": "jest --watch",
    "lint": "eslint src --ext .ts",
    "lint:fix": "eslint src --ext .ts --fix",
    "format": "prettier --write src/**/*.ts",
    "clean": "rm -rf dist",
    "prepublishOnly": "npm run build"
  }
}
```

## 🧪 Testing Strategy

### **Test Structure**
```bash
# Run tests
npm test                      # All tests
npm run test:watch           # Watch mode
npm test -- --coverage      # With coverage report
npm test -- --verbose       # Verbose output
```

### **Jest Configuration**
```typescript
// tests/commands.test.ts
import { execSync } from 'child_process';
import { myCommand } from '../src/commands/myCommand';

describe('CLI Commands', () => {
  test('should execute command successfully', () => {
    const result = myCommand(['--input', 'test.txt']);
    expect(result.exitCode).toBe(0);
  });

  test('should handle invalid options', () => {
    expect(() => {
      myCommand(['--invalid-option']);
    }).toThrow();
  });
});
```

## 📦 Package Management & Distribution

### **Development Workflow**
```bash
# Install new dependency
npm install new-package

# Install as dev dependency
npm install --save-dev new-dev-package

# Update all dependencies
npm update

# Audit for security issues
npm audit
npm audit fix
```

### **Making CLI Globally Installable**
```json
// package.json
{
  "name": "your-cli-tool",
  "version": "1.0.0",
  "bin": {
    "your-tool": "./bin/cli.js"
  },
  "files": [
    "dist/**/*",
    "bin/**/*",
    "README.md"
  ],
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts"
}
```

```javascript
#!/usr/bin/env node
// bin/cli.js
require('../dist/index.js');
```

## 🔧 Common CLI Patterns

### **Commander.js Framework Example**
```typescript
// src/index.ts
import { Command } from 'commander';
import chalk from 'chalk';

const program = new Command();

program
  .name('your-tool')
  .description('CLI tool description')
  .version('1.0.0');

program
  .command('process')
  .description('Process files')
  .option('-i, --input <file>', 'input file')
  .option('-o, --output <file>', 'output file')
  .action((options) => {
    console.log(chalk.green('Processing...'));
    // Command logic here
  });

program.parse();
```

### **Error Handling Pattern**
```typescript
// src/utils/errorHandler.ts
import chalk from 'chalk';

export function handleError(error: Error): never {
  console.error(chalk.red('Error:'), error.message);
  
  if (process.env.NODE_ENV === 'development') {
    console.error(chalk.gray(error.stack));
  }
  
  process.exit(1);
}

// Usage in commands
process.on('unhandledRejection', handleError);
process.on('uncaughtException', handleError);
```

## 🚀 TypeScript Configuration

### **Essential tsconfig.json**
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

## 🔒 Security Best Practices

### **Package Security**
```bash
# Regular security audits
npm audit

# Check for outdated packages
npm outdated

# Use exact versions for security-critical packages
npm install --save-exact package-name
```

### **Environment Variables**
```typescript
// src/config/env.ts
import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  API_KEY: z.string().optional(),
  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'debug']).default('info'),
});

export const env = envSchema.parse(process.env);
```

## 📊 Performance Optimization

### **Bundle Size Management**
- Use tree-shaking compatible imports
- Avoid large dependencies for simple tasks
- Consider native Node.js modules first

### **Memory Management**
```typescript
// Monitor memory usage
console.log(`Memory usage: ${Math.round(process.memoryUsage().heapUsed / 1024 / 1024)} MB`);

// Use streams for large file processing
import { createReadStream, createWriteStream } from 'fs';
import { pipeline } from 'stream/promises';

await pipeline(
  createReadStream('large-input.txt'),
  transformStream,
  createWriteStream('output.txt')
);
```

## 🌐 Cross-Platform Compatibility

### **Path Handling**
```typescript
import path from 'path';

// Always use path.join for cross-platform paths
const configPath = path.join(process.cwd(), 'config', 'settings.json');
```

### **Platform-Specific Logic**
```typescript
import os from 'os';

const isWindows = os.platform() === 'win32';
const homeDir = os.homedir();
```

## 📝 Documentation Standards

### **CLI Help Documentation**
```typescript
program
  .command('deploy')
  .description('Deploy application to specified environment')
  .argument('<environment>', 'deployment environment (dev, staging, prod)')
  .option('-f, --force', 'force deployment without confirmation')
  .option('--dry-run', 'simulate deployment without making changes')
  .example('$0 deploy staging', 'Deploy to staging environment')
  .example('$0 deploy prod --dry-run', 'Simulate production deployment');
```

This Node.js CLI project type provides the equivalent functionality to Python's virtual environments through Node Version Manager (nvm) and npm's package management system, ensuring consistent, reproducible development environments across different machines. 