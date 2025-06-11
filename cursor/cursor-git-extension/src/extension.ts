import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

let statusBarItem: vscode.StatusBarItem;

// Message types that can be configured
type MessageType = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG' | 'OK';

// Display types available
type DisplayType = 'status' | 'popup' | 'notification' | 'output' | 'none';

interface ExtensionConfig {
    displayMappings: Record<MessageType, DisplayType>;
    submodules: string[];
    scriptPath: string;
    showOnStartup: boolean;
    autoRefreshInterval: number;
}

let outputChannel: vscode.OutputChannel;

// Debug logging function
function debugLog(message: string) {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] ${message}\n`;
    const logFile = '/home/gypsy/dev/gypsys-cli-tools/cursor/activation-test.log';
    
    try {
        fs.appendFileSync(logFile, logMessage);
        console.log(`Cursor Git Extension: ${message}`);
    } catch (error) {
        console.error('Failed to write to log file:', error);
        console.log(`Cursor Git Extension: ${message}`);
    }
}

export function activate(context: vscode.ExtensionContext) {
    debugLog('=== EXTENSION ACTIVATION STARTED ===');
    debugLog('Cursor Git Extension is now active!');
    console.log('Cursor Git Extension is now active!');
    
    try {
        // Create output channel
        debugLog('Creating output channel...');
        outputChannel = vscode.window.createOutputChannel('Cursor Git Setup');
        context.subscriptions.push(outputChannel);
        debugLog('Output channel created successfully');
        
        // Create status bar item
        debugLog('Creating status bar item...');
        statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
        statusBarItem.command = 'cursor-git-extension.showStatus';
        context.subscriptions.push(statusBarItem);
        debugLog('Status bar item created successfully');
        
        // Register commands
        debugLog('Registering commands...');
        registerCommands(context);
        debugLog('Commands registered successfully');
        
        // Update status initially
        debugLog('Updating initial git status...');
        updateGitStatus();
        debugLog('Initial git status update completed');
        
        // Show git status on workspace opening if configured
        const config = getConfiguration();
        debugLog(`Configuration loaded - showOnStartup: ${config.showOnStartup}`);
        debugLog(`Script path: ${config.scriptPath}`);
        
        if (config.showOnStartup) {
            debugLog('Scheduling git setup script to run in 1 second...');
            setTimeout(() => {
                debugLog('Running git setup script now...');
                runGitSetupScript();
            }, 1000);
        } else {
            debugLog('Workspace script disabled in configuration');
        }
        
        // Set up auto-refresh if configured
        if (config.autoRefreshInterval > 0) {
            debugLog(`Setting up auto-refresh every ${config.autoRefreshInterval} seconds`);
            setInterval(() => {
                updateGitStatus();
            }, config.autoRefreshInterval * 1000);
        } else {
            debugLog('Auto-refresh disabled');
        }
        
        // Show a test notification to confirm extension is working
        debugLog('Showing test notification...');
        vscode.window.showInformationMessage('🚀 Cursor Git Extension activated successfully!');
        
        debugLog('=== EXTENSION ACTIVATION COMPLETED SUCCESSFULLY ===');
        
    } catch (error) {
        debugLog(`ERROR during activation: ${error}`);
        console.error('Cursor Git Extension activation error:', error);
        vscode.window.showErrorMessage(`Cursor Git Extension activation failed: ${error}`);
    }
}

function registerCommands(context: vscode.ExtensionContext) {
    // Show git status command
    let showStatusCommand = vscode.commands.registerCommand('cursor-git-extension.showStatus', () => {
        showGitStatus();
    });
    context.subscriptions.push(showStatusCommand);
    
    // Run git setup script command
    let runScriptCommand = vscode.commands.registerCommand('cursor-git-extension.runScript', () => {
        runGitSetupScript();
    });
    context.subscriptions.push(runScriptCommand);
    
    // Open settings command
    let openSettingsCommand = vscode.commands.registerCommand('cursor-git-extension.openSettings', () => {
        vscode.commands.executeCommand('workbench.action.openSettings', 'cursor-git-extension');
    });
    context.subscriptions.push(openSettingsCommand);
    
    // Test command
    let testCommand = vscode.commands.registerCommand('cursor-git-extension.test', () => {
        testDisplayTypes();
    });
    context.subscriptions.push(testCommand);
}

function getConfiguration(): ExtensionConfig {
    const config = vscode.workspace.getConfiguration('cursor-git-extension');
    
    return {
        displayMappings: config.get('displayMappings', {
            'INFO': 'notification',
            'WARN': 'popup',
            'ERROR': 'popup',
            'DEBUG': 'output',
            'OK': 'status'
        }),
        submodules: config.get('submodules', ['ai-best-practices']),
        scriptPath: config.get('scriptPath', '/home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-setup.sh'),
        showOnStartup: config.get('showOnStartup', true),
        autoRefreshInterval: config.get('autoRefreshInterval', 0)
    };
}

// Display Functions for different message types
function displayStatus(message: string, tooltip?: string) {
    if (statusBarItem) {
        statusBarItem.text = `$(git-branch) ${message}`;
        statusBarItem.tooltip = tooltip || message;
        statusBarItem.show();
    }
}

function displayPopup(message: string, type: MessageType = 'INFO') {
    const options: vscode.MessageOptions = { modal: true };
    
    switch (type) {
        case 'ERROR':
            vscode.window.showErrorMessage(message, options);
            break;
        case 'WARN':
            vscode.window.showWarningMessage(message, options);
            break;
        case 'INFO':
        case 'OK':
        case 'DEBUG':
        default:
            vscode.window.showInformationMessage(message, options);
            break;
    }
}

function displayNotification(message: string, type: MessageType = 'INFO') {
    switch (type) {
        case 'ERROR':
            vscode.window.showErrorMessage(message);
            break;
        case 'WARN':
            vscode.window.showWarningMessage(message);
            break;
        case 'INFO':
        case 'OK':
        case 'DEBUG':
        default:
            vscode.window.showInformationMessage(message);
            break;
    }
}

function displayOutput(message: string, type: MessageType = 'INFO') {
    const timestamp = new Date().toLocaleTimeString();
    const prefix = `[${timestamp}] [${type}]`;
    outputChannel.appendLine(`${prefix} ${message}`);
    
    // Auto-show output channel for errors
    if (type === 'ERROR') {
        outputChannel.show(true);
    }
}

// Main message router
function displayMessage(message: string, type: MessageType = 'INFO') {
    const config = getConfiguration();
    const displayType = config.displayMappings[type] || 'notification';
    
    // Always log to output channel for debugging
    displayOutput(message, type);
    
    switch (displayType) {
        case 'status':
            displayStatus(message);
            break;
        case 'popup':
            displayPopup(message, type);
            break;
        case 'notification':
            displayNotification(message, type);
            break;
        case 'output':
            // Already logged above
            outputChannel.show(false);
            break;
        case 'none':
            // Only logged to output channel above
            break;
        default:
            displayNotification(message, type);
            break;
    }
}

function updateGitStatus() {
    debugLog('updateGitStatus() called');
    
    if (!vscode.workspace.workspaceFolders) {
        debugLog('No workspace folders found, hiding status bar');
        statusBarItem.hide();
        return;
    }
    
    const workspaceRoot = vscode.workspace.workspaceFolders[0].uri.fsPath;
    debugLog(`Workspace root: ${workspaceRoot}`);
    
    // Check if we're in a git repository
    cp.exec('git rev-parse --is-inside-work-tree', { cwd: workspaceRoot }, (error, stdout, stderr) => {
        if (error) {
            debugLog(`Not in git repository: ${error.message}`);
            statusBarItem.hide();
            return;
        }
        
        debugLog('In git repository, getting status...');
        
        // Get git status
        cp.exec('git status --porcelain', { cwd: workspaceRoot }, (error, stdout, stderr) => {
            if (error) {
                debugLog(`Git status error: ${error.message}`);
                displayStatus('Git Error', 'Error getting git status');
                return;
            }
            
            const changes = stdout.trim().split('\n').filter(line => line.length > 0);
            const changeCount = changes.length;
            debugLog(`Found ${changeCount} git changes`);
            
            // Get current branch
            cp.exec('git branch --show-current', { cwd: workspaceRoot }, (error, branchStdout, stderr) => {
                const branch = error ? 'unknown' : branchStdout.trim();
                debugLog(`Current branch: ${branch}`);
                
                if (changeCount === 0) {
                    debugLog(`Displaying status: ${branch} (clean)`);
                    displayStatus(branch, `Git: ${branch} (clean)`);
                } else {
                    debugLog(`Displaying status: ${branch} (${changeCount} changes)`);
                    displayStatus(`${branch} (${changeCount})`, `Git: ${branch} with ${changeCount} changes`);
                }
            });
        });
    });
}

function runGitSetupScript() {
    debugLog('runGitSetupScript() called');
    
    if (!vscode.workspace.workspaceFolders) {
        debugLog('No workspace folder open for script execution');
        displayMessage('No workspace folder open', 'WARN');
        return;
    }
    
    const workspaceRoot = vscode.workspace.workspaceFolders[0].uri.fsPath;
    const config = getConfiguration();
    const scriptPath = config.scriptPath;
    
    debugLog(`Workspace root: ${workspaceRoot}`);
    debugLog(`Script path: ${scriptPath}`);
    
    // Check if script exists
    if (!fs.existsSync(scriptPath)) {
        debugLog(`Script not found at path: ${scriptPath}`);
        displayMessage(`Git setup script not found at: ${scriptPath}`, 'ERROR');
        return;
    }
    
    debugLog('Script exists, executing...');
    displayMessage('Running git setup script...', 'INFO');
    
    // Set environment variables for the script to use our submodule configuration
    const env = { 
        ...process.env, 
        CURSOR_EXT_SUBMODULES: config.submodules.join(','),
        DEBUG_LEVEL: '2' // Enable info level logging
    };
    
    debugLog(`Environment variables: CURSOR_EXT_SUBMODULES=${env.CURSOR_EXT_SUBMODULES}, DEBUG_LEVEL=${env.DEBUG_LEVEL}`);
    
    cp.exec(`bash "${scriptPath}"`, { cwd: workspaceRoot, env }, (error, stdout, stderr) => {
        if (error) {
            debugLog(`Script execution error: ${error.message}`);
            displayMessage(`Git Setup Script Error: ${error.message}`, 'ERROR');
            if (stderr) {
                debugLog(`Script stderr: ${stderr}`);
                displayMessage(`Script stderr: ${stderr}`, 'DEBUG');
            }
            return;
        }
        
        debugLog('Script executed successfully, parsing output...');
        debugLog(`Script stdout: ${stdout}`);
        if (stderr) {
            debugLog(`Script stderr: ${stderr}`);
        }
        
        // Parse script output and route messages appropriately
        parseScriptOutput(stdout, stderr);
        
        // Update status after script runs
        debugLog('Script completed, updating git status...');
        updateGitStatus();
    });
}

function parseScriptOutput(stdout: string, stderr: string) {
    const lines = stdout.split('\n').concat(stderr.split('\n')).filter(line => line.trim());
    
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        
        // Parse different message types from script output
        if (trimmed.match(/^\[ERROR\]/)) {
            displayMessage(trimmed.replace(/^\[ERROR\]\s*/, ''), 'ERROR');
        } else if (trimmed.match(/^\[WARN\]/)) {
            displayMessage(trimmed.replace(/^\[WARN\]\s*/, ''), 'WARN');
        } else if (trimmed.match(/^\[INFO\]/)) {
            displayMessage(trimmed.replace(/^\[INFO\]\s*/, ''), 'INFO');
        } else if (trimmed.match(/^\[OK\]/)) {
            displayMessage(trimmed.replace(/^\[OK\]\s*/, ''), 'OK');
        } else if (trimmed.match(/^\[DEBUG\]/)) {
            displayMessage(trimmed.replace(/^\[DEBUG\]\s*/, ''), 'DEBUG');
        } else if (trimmed.includes('NOTIFICATION:')) {
            const message = trimmed.replace(/.*NOTIFICATION:\s*/, '');
            displayMessage(message, 'INFO');
        } else if (trimmed.length > 0) {
            // Default to info for other output
            displayMessage(trimmed, 'INFO');
        }
    }
    
    displayMessage('Git setup script completed', 'OK');
}

function showGitStatus() {
    if (!vscode.workspace.workspaceFolders) {
        displayMessage('No workspace folder open', 'WARN');
        return;
    }
    
    const workspaceRoot = vscode.workspace.workspaceFolders[0].uri.fsPath;
    
    cp.exec('git status', { cwd: workspaceRoot }, (error, stdout, stderr) => {
        if (error) {
            displayMessage('Not in a git repository or git error occurred', 'ERROR');
            return;
        }
        
        // Show git status in a new document
        vscode.workspace.openTextDocument({ content: stdout, language: 'git-output' }).then(doc => {
            vscode.window.showTextDocument(doc);
        });
    });
}

function testDisplayTypes() {
    displayMessage('This is an INFO message', 'INFO');
    setTimeout(() => displayMessage('This is a WARNING message', 'WARN'), 1000);
    setTimeout(() => displayMessage('This is an ERROR message', 'ERROR'), 2000);
    setTimeout(() => displayMessage('This is a DEBUG message', 'DEBUG'), 3000);
    setTimeout(() => displayMessage('This is an OK message', 'OK'), 4000);
}

export function deactivate() {
    console.log('Cursor Git Extension deactivated');
    if (statusBarItem) {
        statusBarItem.dispose();
    }
    if (outputChannel) {
        outputChannel.dispose();
    }
} 