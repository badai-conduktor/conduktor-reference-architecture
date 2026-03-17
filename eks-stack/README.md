# Conduktor Platform on AWS EKS

Deploy the Conduktor platform (Console + Gateway) and all dependencies to an AWS EKS cluster.

This stack mirrors the `local-stack/` deployment but replaces local-only components:

- **AWS ALB** instead of Nginx Ingress (HTTPS for Console, Gateway admin, Keycloak)
- **AWS NLB** for Kafka TCP traffic (Gateway SNI routing on port 9092)
- **AWS S3** instead of MinIO for Cortex monitoring storage
- **IRSA** for S3 access (no static credentials)

All other components (Kafka, PostgreSQL, Keycloak, Vault, Schema Registry, Prometheus, Grafana) run self-hosted on EKS.

## Prerequisites

Install the following tools on your machine:

```bash
brew install awscli kubectl helm terraform yq gettext openjdk openssl eksctl
```

Configure the AWS CLI:

```bash
aws configure          # enter Access Key, Secret Key, region, output=json
aws sts get-caller-identity   # verify your identity
```

## Quick Start

### 1. Deploy AWS infrastructure with Terraform

```bash
cd eks-stack/infrastructure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — set your AWS region, cluster name, and S3 bucket name (must be globally unique). Then:

```bash
terraform init
terraform apply
```

This creates: VPC, EKS cluster (with managed node group), EBS CSI driver, S3 bucket, OIDC provider, IAM roles for ALB controller and Cortex, and a self-signed ACM certificate. Takes ~15-20 minutes.

### 2. Configure `config.env`

```bash
cd ..   # back to eks-stack/
cp config.env.example config.env
```

Populate it with the Terraform outputs:

```bash
terraform -chdir=infrastructure output -raw config_env
```

Copy the printed block into `config.env`. Then configure kubectl:

```bash
$(terraform -chdir=infrastructure output -raw kubeconfig_command)
```

### 3. Set your Conduktor license

```bash
export LICENSE="your-conduktor-license-key"
# or:
echo "LICENSE=your-conduktor-license-key" > .env
```

### 4. Deploy infrastructure

```bash
make start-eks-stack
```

Installs cert-manager, trust-manager, AWS Load Balancer Controller, PostgreSQL (x2), Kafka, Vault, Prometheus, Grafana, Schema Registry, Keycloak, and creates ALB/NLB ingress resources.

### 5. Install Conduktor platform

```bash
make install-conduktor-platform
```

### 6. Set up `/etc/hosts`

```bash
./get-hosts.sh
```

Copy and paste the output into `/etc/hosts` (requires `sudo`). This maps the `.test` domains to the ALB and NLB IP addresses so your machine can resolve them.

> **Using real domains?** Create DNS records instead: point `console.yourdomain.com`, `gateway.yourdomain.com`, `oidc.yourdomain.com` to the ALB, and `*.gateway.yourdomain.com` to the NLB.

### 7. Provision platform resources

```bash
make init-conduktor-platform
```

Runs Terraform to create users, groups, clusters, interceptors, and self-service configurations.

### 8. Verify

- Console: `https://console.conduktor.test` — accept the self-signed cert warning
- Gateway admin API: `https://gateway.conduktor.test:8888`
- Kafka proxy: `gateway.conduktor.test:9092`
- Keycloak admin: `https://oidc.conduktor.test/admin`

#### Credentials

| Account | Username | Password | Groups |
|---|---|---|---|
| local | admin@demo.dev | adminP4ss! | admin |
| sso (keycloak) | conduktor-admin | conduktor | admin |
| sso (keycloak) | alice | alice | project-a |
| sso (keycloak) | bob | bob | project-b |

#### Gateway

```bash
curl -k -u admin:adminP4ss! 'https://gateway.conduktor.test:8888/gateway/v2/interceptor'
```

```bash
export KAFKA_OPTS="-Djava.security.manager=allow \
  -Djavax.net.ssl.trustStore=./truststore.jks \
  -Djavax.net.ssl.trustStorePassword=conduktor \
  -Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=https://oidc.conduktor.test/realms/conduktor-realm/protocol/openid-connect/token"

kafka-topics --list \
  --bootstrap-server gateway.conduktor.test:9092 \
  --command-config client.properties
```

#### Grafana

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
```

Open [http://localhost:3000](http://localhost:3000) — login with `admin` / `admin`.

## Teardown

```bash
make stop-eks-stack
```

Uninstalls all Helm releases, removes Kubernetes manifests, ALB/NLB resources, and cleans Terraform state. The EKS cluster itself is not deleted — destroy it with:

```bash
terraform -chdir=infrastructure destroy
```

## Tuning

### Resource Requests and Limits

Default values are set low for demo purposes. For production:

**Console** (`console-values.yaml`):
```yaml
platform:
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
platformCortex:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
```

**Gateway** (`gateway-values.yaml`):
```yaml
gateway:
  replicas: 3
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
```

**Kafka** (`helm-values/kafka.yaml`):
```yaml
controller:
  persistence:
    size: 100Gi
  resources:
    requests:
      cpu: 1000m
      memory: 4Gi
```

**PostgreSQL** (`helm-values/postgresql-main.yaml`, `helm-values/postgresql-sql.yaml`):
```yaml
primary:
  persistence:
    size: 50Gi
```

### Node Sizing

The default `m5.xlarge` (4 vCPU / 16 GB) works for demos. For production consider `m5.2xlarge` or larger. Change `node_instance_type` in `infrastructure/terraform.tfvars` before applying.

### Load Balancer Tuning

ALB settings are configured inline in `01-start.sh`. NLB settings for the Kafka proxy are in `gateway-values.yaml` under `service.external.annotations`.

## Architecture

```
                     Internet
                        │
            ┌───────────┼───────────┐
            │           │           │
         ┌──▼──┐    ┌──▼──┐    ┌──▼──┐
         │ ALB │    │ ALB │    │ NLB │
         │:443 │    │:443 │    │:9092│
         └──┬──┘    └──┬──┘    └──┬──┘
            │          │          │
    Console │  Keycloak│  Gateway │ (Kafka proxy)
            │          │          │
      ┌─────▼──┐  ┌───▼────┐ ┌──▼─────┐
      │Console │  │Keycloak│ │Gateway │
      │  +     │  │        │ │(x2)    │
      │Cortex  │  └───┬────┘ └──┬─────┘
      └──┬──┬──┘      │         │
         │  │    ┌─────▼─────────▼────┐
         │  │    │  Kafka (3 brokers) │
         │  │    └────────────────────┘
         │  │
    ┌────▼──▼────┐    ┌──────────┐
    │ PostgreSQL │    │  AWS S3  │
    │ (main+sql) │    │(Cortex)  │
    └────────────┘    └──────────┘
```

## File Reference

| File | Description |
|---|---|
| `infrastructure/` | Terraform for AWS infrastructure (VPC, EKS, IAM, S3, ACM) |
| `config.env.example` | Configuration template — copy to `config.env` |
| `kubernetes_utils.sh` | Shared shell functions (config loading, waits, truststore generation) |
| `01-start.sh` | Deploy all infrastructure and dependencies |
| `02-install-conduktor-platform.sh` | Install Conduktor Console and Gateway |
| `03-init-conduktor-platform.sh` | Terraform provisioning (users, groups, clusters) |
| `04-stop.sh` | Complete teardown |
| `console-values.yaml` | Console Helm values (S3, IRSA, OIDC) |
| `gateway-values.yaml` | Gateway Helm values (NLB, SNI routing) |
| `helm-values/` | Helm values for all dependencies |
| `manifests/` | Kubernetes manifests (parameterized with envsubst) |
| `provisioning/` | Terraform config for Conduktor resources (users, groups, clusters) |
