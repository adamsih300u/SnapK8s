# Snapcast Server Docker Container

A containerized version of [Snapcast Server](https://github.com/badaix/snapcast) with multi-architecture support (AMD64/ARM64) and pre-installed audio streaming tools.

## Features

- **Multi-architecture support**: Works on both AMD64 and ARM64 platforms
- **Pre-installed audio tools**:
  
  - [mpv](https://mpv.io/) for streaming audio from various sources
  - [shairport-sync](https://github.com/mikebrady/shairport-sync) for AirPlay
- **Flexible configuration**: Mount your own config file or use the included default
- **GitHub Actions CI/CD**: Automated building and testing
- **Docker Compose ready**: Easy deployment with provided compose file

## Quick Start

### Using Docker Compose (Recommended)

1. Clone this repository:
```bash
git clone <your-repo-url>
cd snapk8s
```

2. Create a config directory and copy your configuration:
```bash
mkdir -p config
cp snapserver.conf config/
```

3. Start the service:
```bash
docker-compose up -d
```

### Using Docker Run

```bash
# Create a config directory
mkdir -p ./config
cp snapserver.conf config/

# Run the container
docker run -d \
  --name snapcast-server \
  --network host \
  -v ./config:/config \
  -v /tmp/snapfifo:/tmp/snapfifo \
  --device /dev/snd:/dev/snd \
  --cap-add SYS_NICE \
  --restart unless-stopped \
  ghcr.io/your-username/snapk8s:latest
```

### Using Pre-built Images

Pull from GitHub Container Registry:
```bash
docker pull ghcr.io/your-username/snapk8s:latest
```

## Configuration

### Default Configuration

The container includes your `snapserver.conf` as the default configuration. It supports:

- **MPV streaming**: For internet radio and audio streams

- **AirPlay**: Via shairport-sync
- **TCP streaming**: For external audio sources
- **Web interface**: Accessible on port 1780 (HTTP) and 1788 (HTTPS)

### Custom Configuration

Mount your own configuration file at `/config/snapserver.conf`:

```yaml
volumes:
  - ./your-config.conf:/config/snapserver.conf:ro
```

### Configuration Options

The included configuration supports these audio sources:

1. **Internet Radio Streams** (via MPV):
   - Family Life
   - Gentle Praise
   - Family Radio


   - Device name: "Snapcast"
   - Accessible through Spotify apps

3. **AirPlay**:
   - Device name: "Snapcast"
   - Port: 5000

4. **TCP Stream**:
   - Server listening on port 6000
   - Stream name: "Vinyl"

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 1704 | TCP | Snapcast server (audio streaming) |
| 1705 | TCP | Snapcast control (JSON-RPC API) |
| 1780 | HTTP | Web interface |
| 1788 | HTTPS | Web interface (SSL) |
| 5000 | TCP | AirPlay (shairport-sync) |

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Configuration directory |
| `/root/.config/snapserver` | Snapserver state (client settings, volumes, groups) |
| `/tmp/snapfifo` | Named pipe for audio input |
| `/dev/shm` | Shared memory for NQPTP timing |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | UTC | Timezone for the container |

## Building

### Local Build

```bash
# Build for your current architecture
docker build -t snapcast-server .

# Build for specific architecture
docker build --platform linux/amd64 -t snapcast-server:amd64 .
docker build --platform linux/arm64 -t snapcast-server:arm64 .
```

### Multi-architecture Build

```bash
# Create and use a new builder
docker buildx create --name mybuilder --use

# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t your-registry/snapcast-server:latest \
  --push .
```

## Clients

### Snapcast Clients

Connect Snapcast clients to your server:

```bash
# Linux/macOS
snapclient -h <server-ip>

# Android
# Install "Snapcast" from Google Play Store
# Connect to <server-ip>:1704

# Web Client
# Open http://<server-ip>:1780 in your browser
```

### Spotify Connect

1. Start the container
2. Open Spotify on any device
3. Look for "Snapcast" in the Connect devices list
4. Start playing music

### AirPlay

1. Start the container
2. On iOS/macOS, open Control Center
3. Select "Snapcast" as the AirPlay destination
4. Start playing audio

## Troubleshooting

### Check Container Status

```bash
# View logs
docker logs snapcast-server

# Check if services are running
docker exec snapcast-server ps aux

# Test connectivity
docker exec snapcast-server netcat -z localhost 1704
```

### Audio Issues

1. **No audio output**: Ensure `/dev/snd` is properly mounted
2. **Permission errors**: Add `--cap-add SYS_NICE` to docker run
3. **Network issues**: Use `--network host` for simplest setup

### Configuration Issues

1. **Config not loading**: Ensure your config file is mounted at `/config/snapserver.conf`
2. **Services not starting**: Check the logs for shairport-sync errors
3. **Permission denied**: Ensure config files are readable by the container

## Development

### Local Development

```bash
# Build and run locally
docker-compose up --build

# View logs
docker-compose logs -f

# Shell into container
docker-compose exec snapserver bash
```

### GitHub Actions

The repository includes automated CI/CD:

- **Multi-architecture builds** on push to main/develop
- **Automated testing** of the built images
- **Container registry publishing** to GitHub Packages
- **Semantic versioning** support with git tags

## License

This project follows the same license as Snapcast (GPL-3.0). See the [Snapcast repository](https://github.com/badaix/snapcast) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with both AMD64 and ARM64 (if possible)
5. Submit a pull request

## Acknowledgments

- [Snapcast](https://github.com/badaix/snapcast) by @badaix

- [shairport-sync](https://github.com/mikebrady/shairport-sync) by @mikebrady

## Audio Sources

The container includes three pre-configured audio sources:

1. **MPV Streams**: HTTP/HTTPS audio streams via MPV player

3. **AirPlay 2**: Via shairport-sync for receiving audio from Apple devices with enhanced multi-room support

### AirPlay 2 Features

- **Multi-room Audio**: Native iOS/macOS multi-room streaming
- **Lower Latency**: ~500ms vs 2+ seconds in classic AirPlay
- **Enhanced Discovery**: Improved device discovery and connection reliability
- **iOS 11.4+ Support**: Full compatibility with modern Apple devices
- **Precise Timing**: NQPTP provides sub-millisecond timing accuracy

### Component Versions

- **Snapserver**: Latest from Debian repository

- **Shairport-sync**: Version 4.3.7 (stable release) with **AirPlay 2 support**
- **NQPTP**: Latest from source (required for AirPlay 2 timing)
- **MPV**: Latest from Debian repository
- **Avahi**: Debian repository (for AirPlay service discovery)

## Networking

The container uses **host networking mode** (`network_mode: host`) for optimal performance and compatibility:

- **AirPlay Discovery**: Avahi daemon broadcasts mDNS announcements for AirPlay service discovery
- **Real-time Audio**: Reduces network latency for synchronized multi-room audio
- **Port Access**: Direct access to host network ports without NAT overhead

### Required Ports

- `1704`: Snapcast server (TCP)
- `1705`: Snapcast control (TCP)  
- `1780`: Web interface HTTP (TCP)
- `1788`: Web interface HTTPS (TCP)
- `5000`: AirPlay/shairport-sync (TCP)
- `5353`: mDNS/Bonjour service discovery (UDP) 