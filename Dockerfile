# Multi-stage build for Shairport-Sync and Snapcast Server
FROM debian:bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    autoconf \
    automake \
    libtool \
    libpopt-dev \
    libconfig-dev \
    libasound2-dev \
    avahi-daemon \
    libavahi-client-dev \
    libssl-dev \
    libsoxr-dev \
    libplist-dev \
    libsodium-dev \
    libgcrypt-dev \
    xxd \
    cmake \
    pkg-config \
    libglib2.0-dev \
    libdbus-1-dev \
    libpulse-dev \
    libmosquitto-dev \
    libavutil-dev \
    libavcodec-dev \
    libavformat-dev \
    libflac-dev \
    libogg-dev \
    libvorbis-dev \
    libopus-dev \
    libexpat1-dev \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

# Build Shairport-Sync with AirPlay 2 support
WORKDIR /build
RUN git clone https://github.com/mikebrady/shairport-sync.git
WORKDIR /build/shairport-sync
RUN git submodule update --init --recursive
RUN autoreconf -i
RUN ./configure \
    --with-alsa \
    --with-avahi \
    --with-ssl=openssl \
    --with-soxr \
    --with-airplay-2 \
    --with-metadata \
    --with-mqtt-client \
    --with-dbus-interface \
    --with-mpris-interface \
    --with-pipe \
    --with-stdout \
    --sysconfdir=/etc
RUN make -j$(nproc)
RUN make install

# Build NQPTP for AirPlay 2 timing
WORKDIR /build
RUN git clone https://github.com/mikebrady/nqptp.git
WORKDIR /build/nqptp
RUN autoreconf -i
RUN ./configure
RUN make -j$(nproc)
RUN make install

# Build Snapcast Server
WORKDIR /build
RUN git clone https://github.com/badaix/snapcast.git
WORKDIR /build/snapcast
RUN cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CLIENT=OFF \
    -DBUILD_SERVER=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local
RUN cmake --build build --target snapserver -j$(nproc)
RUN cmake --install build
RUN echo "=== Checking install results ===" && \
    ls -la /usr/local/bin/ && \
    file /usr/local/bin/snapserver || echo "snapserver not found in /usr/local/bin"

# Final runtime image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libasound2 \
    libavahi-client3 \
    libavahi-common3 \
    avahi-daemon \
    libssl3 \
    libsoxr0 \
    libplist3 \
    libsodium23 \
    libgcrypt20 \
    libconfig9 \
    libpopt0 \
    libglib2.0-0 \
    libdbus-1-3 \
    dbus \
    libmosquitto1 \
    ffmpeg \
    flac \
    vorbis-tools \
    opus-tools \
    libexpat1 \
    libboost-system1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-program-options1.74.0 \
    mpv \
    mpg123 \
    sox \
    youtube-dl \
    libssl3 \
    openssl \
    alsa-utils \
    netcat-openbsd \
    curl \
    ca-certificates \
    file \
    procps \
    && rm -rf /var/lib/apt/lists/* && \
    update-ca-certificates

# Copy built binaries from builder stage
COPY --from=builder /usr/local/bin/shairport-sync /usr/local/bin/
COPY --from=builder /usr/local/bin/nqptp /usr/local/bin/
COPY --from=builder /usr/local/bin/snapserver /usr/local/bin/
COPY --from=builder /etc/shairport-sync.conf.sample /etc/shairport-sync.conf

# Create necessary directories (NOT snapfifo - it's a pipe, not a directory)
RUN mkdir -p /config /var/log /root/.config/snapserver

# Copy configuration files
COPY config/ /config/

# Create entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Function to handle shutdown' >> /entrypoint.sh && \
    echo 'cleanup() {' >> /entrypoint.sh && \
    echo '    echo "Shutting down services..."' >> /entrypoint.sh && \
    echo '    pkill -TERM snapserver 2>/dev/null || true' >> /entrypoint.sh && \
    echo '    pkill -TERM shairport-sync 2>/dev/null || true' >> /entrypoint.sh && \
    echo '    pkill -TERM avahi-daemon 2>/dev/null || true' >> /entrypoint.sh && \
    echo '    wait' >> /entrypoint.sh && \
    echo '    exit 0' >> /entrypoint.sh && \
    echo '}' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Set up signal handlers' >> /entrypoint.sh && \
    echo 'trap cleanup SIGTERM SIGINT' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start D-Bus service' >> /entrypoint.sh && \
    echo 'echo "Starting D-Bus..."' >> /entrypoint.sh && \
    echo 'mkdir -p /run/dbus' >> /entrypoint.sh && \
    echo 'dbus-daemon --system --fork' >> /entrypoint.sh && \
    echo 'sleep 2' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start Avahi daemon if not disabled' >> /entrypoint.sh && \
    echo 'if [ "${SKIP_AVAHI:-false}" != "true" ]; then' >> /entrypoint.sh && \
    echo '    echo "Starting Avahi daemon..."' >> /entrypoint.sh && \
    echo '    avahi-daemon --daemonize --no-drop-root' >> /entrypoint.sh && \
    echo '    sleep 2' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start NQPTP for AirPlay 2 timing' >> /entrypoint.sh && \
    echo 'echo "Starting NQPTP..."' >> /entrypoint.sh && \
    echo 'nqptp &' >> /entrypoint.sh && \
    echo 'NQPTP_PID=$!' >> /entrypoint.sh && \
    echo 'sleep 2' >> /entrypoint.sh && \
    echo 'if kill -0 $NQPTP_PID 2>/dev/null; then' >> /entrypoint.sh && \
    echo '    echo "NQPTP is running (PID: $NQPTP_PID)"' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '    echo "ERROR: NQPTP failed to start!"' >> /entrypoint.sh && \
    echo '    echo "Trying to run NQPTP to see error..."' >> /entrypoint.sh && \
    echo '    nqptp' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Function to start snapserver with auto-restart on crash' >> /entrypoint.sh && \
    echo 'start_snapserver() {' >> /entrypoint.sh && \
    echo '    while true; do' >> /entrypoint.sh && \
    echo '        echo "Starting Snapcast Server..."' >> /entrypoint.sh && \
    echo '        echo "Checking snapserver binary:"' >> /entrypoint.sh && \
    echo '        file /usr/local/bin/snapserver' >> /entrypoint.sh && \
    echo '        ldd /usr/local/bin/snapserver' >> /entrypoint.sh && \
    echo '        snapserver --config /config/snapserver.conf' >> /entrypoint.sh && \
    echo '        EXIT_CODE=$?' >> /entrypoint.sh && \
    echo '        echo "Snapserver exited with code $EXIT_CODE"' >> /entrypoint.sh && \
    echo '        if [ $EXIT_CODE -eq 0 ]; then' >> /entrypoint.sh && \
    echo '            echo "Snapserver stopped cleanly, exiting..."' >> /entrypoint.sh && \
    echo '            break' >> /entrypoint.sh && \
    echo '        fi' >> /entrypoint.sh && \
    echo '        echo "Snapserver crashed! Restarting in 5 seconds..."' >> /entrypoint.sh && \
    echo '        sleep 5' >> /entrypoint.sh && \
    echo '    done' >> /entrypoint.sh && \
    echo '}' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start Snapcast Server with auto-restart (will create pipe)' >> /entrypoint.sh && \
    echo 'start_snapserver &' >> /entrypoint.sh && \
    echo 'SNAPSERVER_PID=$!' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Wait for Snapcast to be ready and pipe to be created' >> /entrypoint.sh && \
    echo 'sleep 5' >> /entrypoint.sh && \
    echo 'echo "Waiting for pipe to be created..."' >> /entrypoint.sh && \
    echo 'for i in {1..15}; do' >> /entrypoint.sh && \
    echo '    if [ -p /tmp/snapfifo ]; then' >> /entrypoint.sh && \
    echo '        echo "Pipe /tmp/snapfifo is ready"' >> /entrypoint.sh && \
    echo '        break' >> /entrypoint.sh && \
    echo '    fi' >> /entrypoint.sh && \
    echo '    echo "Waiting for pipe... ($i/15)"' >> /entrypoint.sh && \
    echo '    sleep 1' >> /entrypoint.sh && \
    echo 'done' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start Shairport-Sync in background' >> /entrypoint.sh && \
    echo 'echo "Starting Shairport-Sync..."' >> /entrypoint.sh && \
    echo 'shairport-sync --configfile /etc/shairport-sync.conf &' >> /entrypoint.sh && \
    echo 'SHAIRPORT_PID=$!' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Wait for any process to exit' >> /entrypoint.sh && \
    echo 'wait $SNAPSERVER_PID $SHAIRPORT_PID' >> /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Create Shairport-Sync configuration
RUN echo 'general = {' > /etc/shairport-sync.conf && \
    echo '    name = "Snapcast";' >> /etc/shairport-sync.conf && \
    echo '    output_backend = "pipe";' >> /etc/shairport-sync.conf && \
    echo '    mdns_backend = "avahi";' >> /etc/shairport-sync.conf && \
    echo '    port = 5000;' >> /etc/shairport-sync.conf && \
    echo '    udp_port_base = 6001;' >> /etc/shairport-sync.conf && \
    echo '    udp_port_range = 10;' >> /etc/shairport-sync.conf && \
    echo '    drift_tolerance_in_seconds = 0.002;' >> /etc/shairport-sync.conf && \
    echo '    resync_threshold_in_seconds = 0.050;' >> /etc/shairport-sync.conf && \
    echo '    log_verbosity = 2;' >> /etc/shairport-sync.conf && \
    echo '    statistics = "yes";' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'sessioncontrol = {' >> /etc/shairport-sync.conf && \
    echo '    allow_session_interruption = "yes";' >> /etc/shairport-sync.conf && \
    echo '    session_timeout = 20;' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'alsa = {' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'pipe = {' >> /etc/shairport-sync.conf && \
    echo '    name = "/tmp/snapfifo";' >> /etc/shairport-sync.conf && \
    echo '    audio_backend_buffer_desired_length_in_seconds = 0.2;' >> /etc/shairport-sync.conf && \
    echo '    audio_backend_latency_offset_in_seconds = 0.0;' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'metadata = {' >> /etc/shairport-sync.conf && \
    echo '    enabled = "yes";' >> /etc/shairport-sync.conf && \
    echo '    include_cover_art = "yes";' >> /etc/shairport-sync.conf && \
    echo '    pipe_name = "/tmp/shairport-sync-metadata";' >> /etc/shairport-sync.conf && \
    echo '    pipe_timeout = 5000;' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'mqtt = {' >> /etc/shairport-sync.conf && \
    echo '    enabled = "no";' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf && \
    echo '' >> /etc/shairport-sync.conf && \
    echo 'dsp = {' >> /etc/shairport-sync.conf && \
    echo '};' >> /etc/shairport-sync.conf

# Expose ports
EXPOSE 1704 1705 1780 5000

# Health check
# Use HTTP check instead of TCP to avoid connection churn
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
    CMD curl -f http://localhost:1780/ || exit 1

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
