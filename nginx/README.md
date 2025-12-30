# Nginx Local Server

A simple Docker-based nginx server for serving local directories.

## Quick Start

From any directory containing web files:

```bash
nginx
```

This will:
- Kill any existing nginx server on port 8080 and restart with new directory
- Mount the current directory to nginx
- Serve it on http://localhost:8080 (runs in background)
- Use custom `nginx.conf` if present in the directory
- Show live changes (files are mounted, not copied)

**Background Mode**: The server runs in the background - your terminal is free to use immediately!

**Single Instance Behavior**: Running the script again automatically stops the previous server and starts a new one. No need to manually stop old instances!

## Stopping the Server

The server runs until you stop it or reboot. To stop manually:

```bash
docker stop local-nginx-8080
```

Or just run `nginx` in a different directory to automatically replace it.

## Custom Configuration

To use a custom nginx configuration, create an `nginx.conf` file in the directory you want to serve. The script will automatically detect and use it.

Example custom `nginx.conf`:

```nginx
server {
    listen 8080;
    server_name localhost;
    
    root /usr/share/nginx/html;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## Building the Docker Image

The image is built automatically when you first run `nginx`. To rebuild manually:

```bash
cd /home/gypsy/dev/stable-dev/gypsys-cli-tools/nginx
docker build -t local-nginx .
```

## Port Management

The default port is 8080. To use a different port:

```bash
nginx 3000
```

Each port can have one nginx instance. Running the script on the same port will automatically stop the old instance and start a new one with the current directory.

## Manual Usage

```bash
# Serve current directory
docker run --rm -p 8080:8080 -v "$(pwd):/usr/share/nginx/html:ro" local-nginx

# Serve with custom config
docker run --rm -p 8080:8080 \
  -v "$(pwd):/usr/share/nginx/html:ro" \
  -v "$(pwd)/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  local-nginx
```

## Features

- **Live reload**: Changes to files are immediately visible
- **Directory listing**: Automatically enabled if no index file exists
- **CORS enabled**: For local API development
- **No caching**: Perfect for development
- **Auto-detection**: Uses custom nginx.conf if present

