#!/usr/bin/env node

// Test to verify that Cursor can display notifications
console.log('Testing notification system...');

// Create a visible notification using node-notifier if available
try {
    const notifier = require('node-notifier');
    notifier.notify({
        title: 'Cursor Git Test',
        message: 'This is a test notification to verify the system works!',
        icon: null, // Use default icon
        sound: true,
        wait: false
    });
    console.log('✅ Notification sent successfully!');
} catch (error) {
    console.log('⚠️ node-notifier not available, trying alternative method...');
    
    // Try using desktop notifications via notify-send
    const { exec } = require('child_process');
    exec('notify-send "Cursor Git Test" "Testing notification system" 2>/dev/null', (error) => {
        if (error) {
            console.log('❌ Desktop notifications not available');
            console.log('This might explain why VSCode/Cursor notifications aren\'t showing');
        } else {
            console.log('✅ Desktop notification sent via notify-send!');
        }
    });
}

console.log('If you see a notification popup, the system is working.');
console.log('If not, there might be a system-level notification issue.'); 