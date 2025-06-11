import * as vscode from 'vscode';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as path from 'path';
import * as fs from 'fs';

const execAsync = promisify(exec);

async function getGitStatus(): Promise<string> {
    try {
        // Check if we're in a git repository
        const { stdout: gitCheck } = await execAsync('git rev-parse --is-inside-work-tree');
        if (!gitCheck.trim()) {
            return 'Not in a git repository';
        }

        // Get current branch
        const { stdout: branch } = await execAsync('git branch --show-current');
        const currentBranch = branch.trim();

        // Get status
        const { stdout: status } = await execAsync('git status --porcelain');
        const hasChanges = status.trim().length > 0;

        // Get remote status
        const { stdout: remoteStatus } = await execAsync('git remote -v');
        const hasRemote = remoteStatus.trim().length > 0;

        // Get commit status if remote exists
        let ahead = 0, behind = 0;
        if (hasRemote) {
            try {
                const { stdout: commitStatus } = await execAsync('git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null || echo "0\t0"');
                [ahead, behind] = commitStatus.trim().split('\t').map(Number);
            } catch (error) {
                // Ignore errors for commit status
            }
        }

        // Build status message
        let message = `🌿 Branch: ${currentBranch}`;
        if (hasChanges) {
            message += ` 📝 (modified)`;
        }
        if (hasRemote) {
            if (ahead > 0) message += ` ⬆️ ${ahead}`;
            if (behind > 0) message += ` ⬇️ ${behind}`;
        }

        return message;
    } catch (error) {
        console.error('Error getting git status:', error);
        return `❌ Git error: ${error}`;
    }
}

async function executeGitScript(): Promise<string> {
    try {
        // Path to the git setup script
        const scriptPath = '/home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-setup.sh';
        
        // Execute the script
        const { stdout, stderr } = await execAsync(`bash "${scriptPath}"`);
        
        if (stderr && stderr.trim()) {
            console.warn('Script stderr:', stderr);
        }
        
        return stdout || 'Script executed successfully';
    } catch (error) {
        console.error('Error executing git script:', error);
        return `Error executing script: ${error}`;
    }
}

export async function activate(context: vscode.ExtensionContext) {
    const timestamp = new Date().toISOString();
    console.log(`Cursor Git Extension activating at ${timestamp}...`);
    
    // Write to multiple test locations to confirm activation
    const testLocations = [
        '/home/gypsy/.cursor/extensions/gypsys-cli-tools.cursor-git-extension-0.0.1/activation-test.log',
        '/home/gypsy/dev/gypsys-cli-tools/cursor/activation-test.log'
    ];
    
    for (const testLogPath of testLocations) {
        try {
            const fs = require('fs');
            const logMessage = `Extension activated at: ${timestamp}\nExtension path: ${context.extensionPath}\n`;
            fs.writeFileSync(testLogPath, logMessage, { flag: 'a' });
            console.log(`Successfully wrote to: ${testLogPath}`);
        } catch (error) {
            console.error(`Error writing test log to ${testLogPath}:`, error);
        }
    }
    
    // Create status bar item
    const statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    context.subscriptions.push(statusBarItem);

    // Function to update status
    async function updateStatus() {
        try {
            const gitStatus = await getGitStatus();
            statusBarItem.text = gitStatus;
            statusBarItem.show();
            
            // Execute the script and get comprehensive output
            const scriptOutput = await executeGitScript();
            console.log('Script output:', scriptOutput);
            
            // Show the script output directly in a notification
            if (scriptOutput && scriptOutput.trim()) {
                // For multiline output, show in a new document
                const doc = await vscode.workspace.openTextDocument({
                    content: `Git Repository Status (${timestamp})\n${'='.repeat(50)}\n\n${scriptOutput}`,
                    language: 'plaintext'
                });
                await vscode.window.showTextDocument(doc, { preview: true });
                
                // Also show a brief notification
                vscode.window.showInformationMessage(`🔧 Git Repository Status Check Complete - ${new Date().toLocaleTimeString()}`);
            } else {
                vscode.window.showInformationMessage('✅ Git setup script executed successfully');
            }
            
        } catch (error) {
            console.error('Error updating status:', error);
            statusBarItem.text = '❌ Git Error';
            statusBarItem.show();
            vscode.window.showErrorMessage(`Git extension error: ${error}`);
        }
    }

    // Update status immediately
    await updateStatus();

    // Register command to manually refresh
    const refreshCommand = vscode.commands.registerCommand('cursor-git-extension.refresh', updateStatus);
    context.subscriptions.push(refreshCommand);

    console.log('Cursor Git Extension activated successfully!');
}

export function deactivate() {
    console.log('Cursor Git Extension deactivated');
} 