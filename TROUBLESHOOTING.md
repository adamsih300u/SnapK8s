# Snapcast Server Crash Fix

## Problem
The snapserver container was crashing with this error:
```
terminate called after throwing an instance of 'boost::wrapexcept<boost::system::system_error>'
  what():  remote_endpoint: Transport endpoint is not connected
```

This is a known bug in snapserver where it doesn't properly handle exceptions when clients disconnect unexpectedly.

## Root Causes
1. **TCP health probes creating connection churn**: Kubernetes TCP probes were connecting/disconnecting every 5-10 seconds, triggering the snapserver bug
2. **No crash recovery**: When snapserver crashed, the entire pod would restart, losing state
3. **Insufficient resources**: Multiple audio streams need more memory/CPU
4. **Missing HTTP interface**: The web interface wasn't enabled, so we couldn't use HTTP health checks

## Solutions Implemented

### 1. Changed Health Probes (k8s-manifest.yaml)
- **Before**: TCP socket checks on port 1704 (audio stream port)
- **After**: HTTP GET requests to port 1780 (web interface)
- **Why**: HTTP checks don't create/drop connections on the audio port, avoiding the bug trigger
- Made checks less aggressive: every 30s instead of 5-10s

### 2. Added Auto-Restart Loop (Dockerfile)
- Added a bash function that wraps snapserver in a while loop
- If snapserver crashes (non-zero exit), it automatically restarts after 5 seconds
- Clean exits (exit code 0) still stop the container normally
- The pod stays running, maintaining network accessibility

### 3. Enabled HTTP Interface (snapserver.conf)
```ini
[http]
enabled = true
bind_to_address = 0.0.0.0
port = 1780
```
This allows HTTP-based health checks and provides a web UI.

### 4. Added Connection Timeout (snapserver.conf)
```ini
[streaming_client]
timeout = 30000
```
30-second timeout helps prevent stale connection issues.

### 5. Increased Resources (k8s-manifest.yaml)
- Memory: 256Mi → 512Mi (request), 512Mi → 1Gi (limit)
- CPU: 100m → 200m (request), 500m → 1000m (limit)
- Better handles 6 concurrent audio streams

## Deployment

### Step 1: Rebuild the Docker Image
```bash
make build
make push
# or
docker build -t ghcr.io/adamsih300u/snapk8s:latest .
docker push ghcr.io/adamsih300u/snapk8s:latest
```

### Step 2: Apply the Updated Kubernetes Manifest
```bash
kubectl apply -f k8s-manifest.yaml
```

### Step 3: Force Pod Restart (if needed)
```bash
kubectl rollout restart deployment/snapcast-server -n snapcast
```

### Step 4: Monitor Logs
```bash
# Watch for crashes and auto-restarts
kubectl logs -f deployment/snapcast-server -n snapcast

# You should see this if a crash occurs:
# "Snapserver exited with code 134"
# "Snapserver crashed! Restarting in 5 seconds..."
```

## Verification

### Check Health
```bash
# Check pod status
kubectl get pods -n snapcast

# Check if HTTP interface is accessible
kubectl port-forward -n snapcast svc/snapcast-server-lb 1780:1780
# Then visit http://localhost:1780 in browser
```

### Test Resilience
If you want to test the auto-restart:
```bash
# Kill snapserver process inside the container
kubectl exec -n snapcast deployment/snapcast-server -- pkill snapserver

# Check logs - you should see it restart
kubectl logs -f deployment/snapcast-server -n snapcast
```

## Expected Behavior

### Before Fix
- Snapserver crashes → Pod exits → Kubernetes restarts pod (30+ seconds downtime)
- Clients lose connection and can't reconnect for a while
- Network endpoint becomes inaccessible

### After Fix
- Snapserver crashes → Auto-restarts in 5 seconds (pod stays running)
- HTTP interface remains accessible
- Clients may briefly lose audio but can reconnect quickly
- Pod status remains "Running"

## Additional Recommendations

### 1. Update Snapserver (Future)
Consider building from the latest snapserver source to get bug fixes:
```bash
# In Dockerfile, change:
RUN git clone https://github.com/badaix/snapcast.git
# To:
RUN git clone --depth 1 --branch vX.X.X https://github.com/badaix/snapcast.git
```

### 2. Monitor Crash Frequency
If crashes still occur frequently:
```bash
# Count crashes in logs
kubectl logs deployment/snapcast-server -n snapcast | grep "Snapserver crashed" | wc -l
```

If you see many crashes, this indicates:
- Clients are disconnecting abruptly (network issues?)
- The snapserver bug needs upstream fix
- Consider reducing number of concurrent streams

### 3. Consider Connection Pooling
If you have many clients connecting/disconnecting frequently, you might want to:
- Use a reverse proxy (nginx) in front of snapserver
- Implement connection keepalive
- Tune TCP keepalive settings in Kubernetes

## Troubleshooting

### Pod is in CrashLoopBackOff
```bash
# Check logs
kubectl logs deployment/snapcast-server -n snapcast --previous

# Check events
kubectl describe pod -n snapcast -l app=snapcast-server
```

### HTTP Health Check Failing
```bash
# Test HTTP endpoint manually
kubectl exec -n snapcast deployment/snapcast-server -- curl -v http://localhost:1780/

# Check if HTTP is enabled in config
kubectl exec -n snapcast deployment/snapcast-server -- cat /config/snapserver.conf | grep -A 5 "\[http\]"
```

### Snapserver Still Crashing
```bash
# Check for resource constraints
kubectl top pod -n snapcast

# Increase memory/CPU limits in k8s-manifest.yaml if needed
```

## Files Changed
1. `k8s-manifest.yaml` - Health probes and resources
2. `config/snapserver.conf` - HTTP interface and timeouts
3. `Dockerfile` - Auto-restart loop and HTTP healthcheck

