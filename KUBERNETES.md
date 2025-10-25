# Snapcast Server Kubernetes Deployment Guide

This guide covers deploying Snapcast Server on Kubernetes with MetalLB LoadBalancer support.

## Prerequisites

- Kubernetes cluster (1.19+)
- MetalLB configured for Layer 2 load balancing
- kubectl configured to access your cluster
- Container image built and available

## Quick Deployment

### 1. Build and Push Image

```bash
# Build the image
docker build -t snapcast-server:latest .

# Tag for your registry (adjust as needed)
docker tag snapcast-server:latest your-registry/snapcast-server:latest

# Push to registry
docker push your-registry/snapcast-server:latest
```

### 2. Update Image Reference

Edit `k8s-manifest.yaml` and update the image reference:

```yaml
containers:
- name: snapcast-server
  image: your-registry/snapcast-server:latest  # Update this line
```

### 3. Configure MetalLB IP

Edit the LoadBalancer service annotations in `k8s-manifest.yaml`:

```yaml
annotations:
  metallb.universe.tf/loadBalancerIPs: "192.168.1.100"  # Your desired IP
```

### 4. Deploy to Kubernetes

```bash
# Apply the manifest
kubectl apply -f k8s-manifest.yaml

# Check deployment status
kubectl get all -n snapcast

# Watch pods starting
kubectl get pods -n snapcast -w
```

## Configuration Options

### Networking Modes

The manifest includes two networking options:

#### Option 1: Host Network (Recommended for mDNS)
```yaml
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
```

#### Option 2: Standard Networking + LoadBalancer
```yaml
# Comment out hostNetwork and use LoadBalancer service
spec:
  # hostNetwork: true
  # dnsPolicy: ClusterFirstWithHostNet
```

### MetalLB Configuration

#### Using Specific IP
```yaml
annotations:
  metallb.universe.tf/loadBalancerIPs: "192.168.1.100"
```

#### Using Address Pool
```yaml
annotations:
  metallb.universe.tf/address-pool: snapcast-pool
```

## Customization

### Audio Sources Configuration

Edit the ConfigMap to configure audio sources:

```yaml
data:
  snapserver.conf: |
    [stream]
    # Pipe source (default)
    source = pipe:///tmp/snapfifo?name=default
    
    # Add Spotify Connect
    # Spotify Connect via librespot is not available in this build
    
    # Add AirPlay
    source = airplay:?name=AirPlay&port=5000
    
    # Add HTTP stream
    source = http://stream.example.com:8000/music.mp3?name=Radio
```

### Resource Limits

Adjust resource requests and limits based on your needs:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Storage Configuration

Configure persistent storage for configuration and audio pipes:

```yaml
# For dynamic provisioning
spec:
  storageClassName: your-storage-class
  
# For specific volume
spec:
  volumeName: snapcast-config-pv
```

### Node Selection

Deploy to specific nodes (e.g., audio-capable nodes):

```yaml
nodeSelector:
  kubernetes.io/arch: amd64
  audio-capable: "true"

# Or use tolerations
tolerations:
- key: "audio-node"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

## Monitoring and Troubleshooting

### Check Deployment Status

```bash
# Overall status
kubectl get all -n snapcast

# Pod details
kubectl describe pod -l app=snapcast-server -n snapcast

# Container logs
kubectl logs -f deployment/snapcast-server -n snapcast

# Service status
kubectl get svc snapcast-server-lb -n snapcast
```

### Test Connectivity

```bash
# Get LoadBalancer IP
LB_IP=$(kubectl get svc snapcast-server-lb -n snapcast -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test Snapcast port
nc -zv $LB_IP 1704

# Test web interface
curl http://$LB_IP:1780

# Test AirPlay port
nc -zv $LB_IP 5000
```

### Access Web Interface

```bash
# Get LoadBalancer IP
kubectl get svc snapcast-server-lb -n snapcast

# Access web interface at:
# http://<EXTERNAL-IP>:1780
```

### Common Issues

#### Pod Stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check storage provisioning
kubectl get pvc -n snapcast
```

#### Avahi/mDNS Not Working
```bash
# Ensure host networking is enabled
kubectl get pod -n snapcast -o yaml | grep hostNetwork

# Check if MetalLB assigned IP
kubectl get svc snapcast-server-lb -n snapcast
```

#### Audio Issues
```bash
# Check audio pipe permissions
kubectl exec -it deployment/snapcast-server -n snapcast -- ls -la /tmp/snapfifo

# Test pipe writing
kubectl exec -it deployment/snapcast-server -n snapcast -- sh
# echo "test" > /tmp/snapfifo
```

## Scaling and High Availability

### Multiple Replicas (Audio Conflicts)
```yaml
# Only use for redundancy, not load balancing
spec:
  replicas: 2  # Caution: May cause audio conflicts
```

### DaemonSet Deployment
For one instance per node:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: snapcast-server-ds
# ... rest of configuration
```

### Rolling Updates

```bash
# Update image
kubectl set image deployment/snapcast-server snapcast-server=snapcast-server:v2 -n snapcast

# Check rollout status
kubectl rollout status deployment/snapcast-server -n snapcast

# Rollback if needed
kubectl rollout undo deployment/snapcast-server -n snapcast
```

## Security Considerations

### Network Policies
The manifest includes a NetworkPolicy for basic security. Adjust as needed:

```yaml
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
```

### Pod Security
```yaml
securityContext:
  runAsNonRoot: false  # Required for avahi-daemon
  capabilities:
    add:
      - NET_ADMIN  # If needed for network operations
```

## Cleanup

```bash
# Remove all resources
kubectl delete -f k8s-manifest.yaml

# Or delete namespace
kubectl delete namespace snapcast
```

## Advanced Configuration

### Custom MetalLB Pool

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: snapcast-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.110
```

### Ingress (Alternative to LoadBalancer)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snapcast-ingress
  namespace: snapcast
spec:
  rules:
  - host: snapcast.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: snapcast-server-lb
            port:
              number: 1780
```

This deployment provides a production-ready Snapcast Server with proper networking, storage, monitoring, and scaling capabilities. 