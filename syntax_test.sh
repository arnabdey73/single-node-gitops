#!/bin/bash

# Extract the specific section around the else statement to test
if ! kubectl get service deployment-platform -n deployment-platform &> /dev/null; then
    echo "service not found"
    kubectl rollout status deployment/deployment-platform -n deployment-platform --timeout=60s || true
else
    echo "service exists"
fi

echo "Test completed"
