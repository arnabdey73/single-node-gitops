# DevSecOps Integration Guide for AppDeploy Platform

This guide covers the DevSecOps components integrated into the AppDeploy platform, their configuration, and best practices.

## Overview

The AppDeploy platform incorporates DevSecOps principles through:
- Container vulnerability scanning
- Security policy enforcement
- Compliance benchmarking
- Security monitoring and alerting

## Components

### 1. Vulnerability Scanning with Trivy Operator

Trivy Operator continuously scans your container images and Kubernetes resources for vulnerabilities.

#### Key Features
- Automated vulnerability scanning of container images
- Integration with CI/CD pipeline
- Customizable severity thresholds
- Runtime vulnerability detection

#### Accessing Vulnerability Reports

```bash
# List vulnerability reports
kubectl get vulnerabilityreports --all-namespaces

# Get detailed report
kubectl describe vulnerabilityreport -n <namespace> <report-name>
```

### 2. Security Policy Enforcement with OPA Gatekeeper

Open Policy Agent (OPA) Gatekeeper enforces security policies across your cluster.

#### Included Policies
- Prevention of privileged containers
- Enforcement of resource limits
- Required labels and annotations
- Pod Security Standards enforcement

#### Managing Policies

```bash
# List constraints
kubectl get constraints -A

# List violations
kubectl get constraints -o json | jq '.items[] | select(.status.totalViolations > 0)'
```

### 3. CIS Kubernetes Benchmarking

Regular automated CIS benchmark checks to ensure Kubernetes security best practices are followed.

#### Benchmark Execution

```bash
# Run a one-time benchmark
kubectl create job --namespace security-tools cis-benchmark-$(date +%s) --from=cronjob/kube-bench

# View latest results
kubectl logs -n security-tools job/$(kubectl get job -n security-tools -o=jsonpath='{.items[-1:].metadata.name}')
```

### 4. Security Monitoring and Alerting

Integrated security monitoring dashboard with alerts for security events.

#### Dashboard Access

```bash
# Access security dashboard
kubectl port-forward svc/security-dashboard -n security-monitoring 8085:80
```

#### Alert Rules

Pre-configured alerts for:
- Critical vulnerabilities
- Security policy violations
- CIS benchmark failures
- Authentication anomalies

## DevSecOps Workflow

### 1. Development Phase
- Code is committed with security context requirements
- Pre-commit hooks run static analysis

### 2. Build Phase
- Container images are built and tagged
- Trivy performs vulnerability scanning
- Failed high-severity checks block the pipeline

### 3. Deployment Phase
- OPA Gatekeeper validates against security policies
- ArgoCD applies the configuration
- Policy violations are reported and can block deployment

### 4. Runtime
- Continuous vulnerability scanning
- CIS benchmark checks
- Network policy enforcement
- Runtime security monitoring

## Security Reports

Regular security reports can be generated using the container-security.sh script:

```bash
./scripts/container-security.sh
```

This generates a comprehensive security report including:
- Vulnerability summary
- Policy compliance status
- CIS benchmark results
- Remediation recommendations

## Best Practices

1. **Keep Base Images Updated**
   - Use the latest patched base images
   - Remove unnecessary packages

2. **Implement Least Privilege**
   - Use non-root users in containers
   - Apply restrictive security contexts
   - Use read-only file systems where possible

3. **Network Security**
   - Define explicit network policies
   - Isolate namespaces
   - Control ingress/egress traffic

4. **Secret Management**
   - Use sealed secrets for sensitive information
   - Rotate secrets regularly
   - Implement secret access controls

5. **Regular Auditing**
   - Review security reports weekly
   - Address critical vulnerabilities immediately
   - Perform regular security exercises

## Customization

### Adding Custom Security Policies

To add custom security policies, create new constraint templates in:
```
applications/security/policies/
```

### Customizing Vulnerability Thresholds

Edit the Trivy Operator configuration to adjust severity thresholds:
```
applications/security/scanning/trivy-operator.yaml
```

### Adding Security Dashboards

Add custom Grafana dashboard configurations to:
```
applications/security/dashboard/
```

## Troubleshooting

### Common Issues

1. **False Positives in Vulnerability Scanning**
   - Verify with `kubectl describe vulnerabilityreport`
   - Add exclusions to Trivy configuration

2. **Policy Violations Blocking Deployment**
   - Review constraint violations with `kubectl describe constraint`
   - Adjust policies or update deployments to comply

3. **CIS Benchmark Failures**
   - Check specific test failures in the logs
   - Apply recommended fixes from CIS documentation

### Getting Help

For security-related issues, use:

```bash
# Get security component status
kubectl get pods -n security-tools
kubectl get pods -n trivy-system
kubectl get pods -n gatekeeper-system

# Check logs
kubectl logs -n <namespace> <pod-name>
```

## Installation Options

When installing the AppDeploy platform, you can control which DevSecOps components are enabled using command line flags:

```bash
# Install with all security components (default)
./install.sh

# Install without vulnerability scanning
./install.sh --disable-vulnerability-scanning

# Install without policy enforcement
./install.sh --disable-policy-enforcement

# Install without CIS benchmarks
./install.sh --disable-cis-benchmarks

# Install without security dashboard
./install.sh --disable-security-dashboard

# Install without any security components
./install.sh --disable-all-security

# Show all options
./install.sh --help
```

During installation, an initial security assessment will be generated automatically in the background, with results saved to `security-initial-assessment.txt`.

## Conclusion

The DevSecOps integration in the AppDeploy platform provides a comprehensive security approach throughout the application lifecycle. Regular monitoring, adherence to security policies, and addressing vulnerabilities promptly will maintain a strong security posture for your applications.

The modular design allows you to customize the security components based on your specific requirements, making it suitable for both development environments and production deployments.
