#!/bin/bash

# Docker Registry Management Script for AppDeploy Platform

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

print_header() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

# Get node IP
get_node_ip() {
    kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}

# Check if registry is running
check_registry_status() {
    if kubectl get pods -n docker-registry -l app=docker-registry 2>/dev/null | grep -q Running; then
        return 0
    else
        return 1
    fi
}

# Create user credentials for registry
create_registry_user() {
    local username=$1
    local password=$2
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        error "Username and password required. Usage: $0 create-user <username> <password>"
    fi
    
    # Create a temporary container to generate the htpasswd file
    log "Creating user $username for Docker registry..."
    
    # Check if the secret already exists
    if kubectl get secret -n docker-registry docker-registry-htpasswd 2>/dev/null; then
        # Get existing htpasswd content
        local htpasswd=$(kubectl get secret -n docker-registry docker-registry-htpasswd -o jsonpath="{.data.htpasswd}" | base64 -d)
        
        # Create a temporary container to update the htpasswd file
        local temp_htpasswd=$(docker run --rm -i xmartlabs/htpasswd -Bbn "$username" "$password")
        
        if [ -z "$htpasswd" ]; then
            htpasswd="$temp_htpasswd"
        else
            # Check if user already exists
            if echo "$htpasswd" | grep -q "^$username:"; then
                # Replace the existing user
                htpasswd=$(echo "$htpasswd" | grep -v "^$username:" || echo)
                if [ -n "$htpasswd" ]; then
                    htpasswd="${htpasswd}"$'\n'"${temp_htpasswd}"
                else
                    htpasswd="${temp_htpasswd}"
                fi
            else
                # Append the new user
                htpasswd="${htpasswd}"$'\n'"${temp_htpasswd}"
            fi
        fi
        
        # Update the secret
        echo "$htpasswd" | kubectl create secret generic docker-registry-htpasswd --from-file=htpasswd=/dev/stdin -n docker-registry --dry-run=client -o yaml | kubectl apply -f -
    else
        # Create new htpasswd file
        docker run --rm -i xmartlabs/htpasswd -Bbn "$username" "$password" |
        kubectl create secret generic docker-registry-htpasswd --from-file=htpasswd=/dev/stdin -n docker-registry
    fi
    
    # Patch the registry to use htpasswd authentication
    kubectl patch configmap docker-registry-config -n docker-registry --type=merge -p '{
        "data": {
            "config.yml": "version: 0.1\nlog:\n  fields:\n    service: registry\nstorage:\n  filesystem:\n    rootdirectory: /var/lib/registry\nauth:\n  htpasswd:\n    realm: Registry Realm\n    path: /auth/htpasswd\nhttp:\n  addr: :5000"
        }
    }'
    
    # Mount the htpasswd file
    kubectl patch deployment docker-registry -n docker-registry --type=json -p '[
        {
            "op": "add",
            "path": "/spec/template/spec/volumes/-",
            "value": {
                "name": "auth",
                "secret": {
                    "secretName": "docker-registry-htpasswd"
                }
            }
        },
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/volumeMounts/-",
            "value": {
                "name": "auth",
                "mountPath": "/auth",
                "readOnly": true
            }
        }
    ]'
    
    log "User $username created successfully. Registry will restart to apply changes."
}

# Print registry information
get_registry_info() {
    local node_ip=$(get_node_ip)
    
    if check_registry_status; then
        print_header "DOCKER REGISTRY INFORMATION"
        
        echo "Registry URL: $node_ip:30500"
        echo -e "\nUsage:"
        echo -e "  ${YELLOW}docker login $node_ip:30500${NC}"
        echo -e "  ${YELLOW}docker tag myimage:latest $node_ip:30500/myimage:latest${NC}"
        echo -e "  ${YELLOW}docker push $node_ip:30500/myimage:latest${NC}"
        echo -e "  ${YELLOW}docker pull $node_ip:30500/myimage:latest${NC}"
        
        echo -e "\nIn Kubernetes manifests:"
        echo -e "  image: $node_ip:30500/myimage:latest"
        
        echo -e "\nRegistry Status:"
        kubectl get pods -n docker-registry -l app=docker-registry
        
        # Check for user credentials
        if kubectl get secret -n docker-registry docker-registry-htpasswd 2>/dev/null; then
            echo -e "\nAuthentication: Enabled (htpasswd)"
            echo -e "Users configured: $(kubectl get secret -n docker-registry docker-registry-htpasswd -o jsonpath='{.data.htpasswd}' | base64 -d | grep -v '^$' | wc -l)"
        else
            echo -e "\nAuthentication: Disabled (anonymous access)"
        fi
    else
        warn "Docker registry is not running. Please check the deployment status."
        kubectl get pods -n docker-registry
    fi
}

# Add insecure registry to Docker daemon
configure_insecure_registry() {
    local node_ip=$(get_node_ip)
    
    log "Configuring local Docker daemon to trust insecure registry at $node_ip:30500..."
    
    if [ ! -f /etc/docker/daemon.json ]; then
        sudo mkdir -p /etc/docker
        echo '{"insecure-registries": ["'$node_ip':30500"]}' | sudo tee /etc/docker/daemon.json
    else
        # Check if insecure-registries already exists in the daemon.json file
        if grep -q "insecure-registries" /etc/docker/daemon.json; then
            # Add our registry to the existing list if it doesn't already exist
            if ! grep -q "$node_ip:30500" /etc/docker/daemon.json; then
                sudo sed -i -e 's/\"insecure-registries\": \[/\"insecure-registries\": \[\"'$node_ip':30500\", /g' /etc/docker/daemon.json
            fi
        else
            # Add the insecure-registries field to the daemon.json file
            sudo sed -i -e 's/{/{\"insecure-registries\": \[\"'$node_ip':30500\"\], /g' /etc/docker/daemon.json
        fi
    fi
    
    log "Restarting Docker daemon..."
    sudo systemctl restart docker
    
    log "Docker daemon configured to trust insecure registry at $node_ip:30500"
    log "You can now use the registry without TLS verification."
}

# Show usage information
show_usage() {
    echo -e "Docker Registry Management for AppDeploy Platform\n"
    echo -e "Usage: $0 [command]\n"
    echo "Commands:"
    echo "  info                  Show Docker registry information and status"
    echo "  create-user <username> <password>  Create/update a user for the registry"
    echo "  configure-insecure    Configure local Docker daemon to trust insecure registry"
    echo "  help                  Show this help message"
}

# Main script logic
main() {
    cmd="${1:-help}"
    
    case "$cmd" in
        info)
            get_registry_info
            ;;
        create-user)
            create_registry_user "$2" "$3"
            ;;
        configure-insecure)
            configure_insecure_registry
            ;;
        help|*)
            show_usage
            ;;
    esac
}

main "$@"
