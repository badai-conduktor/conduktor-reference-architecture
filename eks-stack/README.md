# Conduktor Platform on AWS EKS

Deploy the Conduktor platform (Console + Gateway) and all dependencies to an AWS EKS cluster.

This stack mirrors the `local-stack/` deployment but replaces local-only components:

- **AWS ALB** instead of Nginx Ingress (HTTPS for Console, Gateway admin, Keycloak)
- **AWS NLB** for Kafka TCP traffic (Gateway SNI routing on port 9092)
- **AWS S3** instead of MinIO for Cortex monitoring storage
- **IRSA** for S3 access (no static credentials)

All other components (Kafka, PostgreSQL, Keycloak, Vault, Schema Registry, Prometheus, Grafana) run self-hosted on EKS.

## Prerequisites

- AWS CLI (`aws`) installed and configured (`aws configure`)
- Tools installed locally: `helm`, `kubectl`, `terraform`, `yq`, `envsubst`, `keytool`, `openssl`
- A valid Conduktor license key

```bash
brew install awscli kubectl helm terraform yq gettext openjdk openssl
```

## Quick Start

### 1. Deploy AWS infrastructure

```bash
cd eks-stack/infrastructure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your AWS-specific values (region, cluster name, S3 bucket name).

```bash
cd ..
make infra
```

This creates: VPC, EKS cluster (with managed node group), EBS CSI driver, S3 bucket, OIDC provider, IAM roles for ALB controller and Cortex, and a self-signed ACM certificate. Takes ~15-20 minutes.

### 2. Configure

```bash
cp config.env.example config.env
```

Edit `config.env` with values from the Terraform outputs:

```bash
terraform -chdir=infrastructure output -raw config_env
```

Configure kubectl:

```bash
$(terraform -chdir=infrastructure output -raw kubeconfig_command)
```

Set your license:

```bash
export LICENSE="your-conduktor-license-key"
```

Or create a `.env` file:

```bash
echo "LICENSE=your-conduktor-license-key" > .env
```

### 3. Deploy dependencies

```bash
make start-eks-stack
```

This installs cert-manager, trust-manager, AWS Load Balancer Controller, PostgreSQL (x2), Kafka, Vault, Prometheus, Grafana, Schema Registry, and Keycloak. It also creates ALB Ingress resources for Console, Gateway admin, and Keycloak.

### 4. Install Conduktor platform

```bash
make install-conduktor-platform
```

Deploys Conduktor Gateway and Console via Helm.

### 5. Set up `/etc/hosts`

```bash
./get-hosts.sh
```

Copy and paste the output into `/etc/hosts` (may need sudo access).

> **Using real domains?** If you own a domain, create DNS records instead: point `console.yourdomain.com`, `gateway.yourdomain.com`, `oidc.yourdomain.com` to the ALB address, and `*.gateway.yourdomain.com` to the NLB address.

### 6. Provision platform resources

```bash
make init-conduktor-platform
```

Runs Terraform to create users, groups, clusters, interceptors, and self-service configurations.

### Conduktor Console

You can then access Conduktor Console at [https://console.conduktor.test](https://console.conduktor.test)

You can then login using the following credentials :

| Account Type   | Username                                     | Password   | Groups    |
|----------------|----------------------------------------------|------------|-----------|
| local          | admin@demo.dev                               | adminP4ss! | admin     |
| sso (keycloak) | conduktor-admin / conduktor-admin@company.io | conduktor  | admin     |
| sso (keycloak) | alice / alice@company.io                     | alice      | project-a |
| sso (keycloak) | bob / alice@company.io                       | bob        | project-b |

You will be able to create topics and otherwise interact with both Kafka Cluster and Conduktor Gateway.

The connection to Conduktor Gateway uses SASL PLAIN with a credential generated earlier in the previous step.

### Conduktor Gateway

You can reach the Conduktor Gateway Admin API at [https://gateway.conduktor.test:8888](https://gateway.conduktor.test:8888).

```bash
curl -k -u admin:adminP4ss! \
    'https://gateway.conduktor.test:8888/gateway/v2/interceptor'
```

You can reach Kafka through Gateway using SASL OAuthbearer (see client.properties file). Here we assume `kafka-topics` is installed locally and is running Apache Kafka version 4 or greater.

```bash
# Need to set truststore at the JVM level to authenticate with OIDC
export KAFKA_OPTS="-Djava.security.manager=allow \
-Djavax.net.ssl.trustStore=./truststore.jks \
-Djavax.net.ssl.trustStorePassword=conduktor \
-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=https://oidc.conduktor.test/realms/conduktor-realm/protocol/openid-connect/token"
```

```bash
kafka-topics --list \
    --bootstrap-server gateway.conduktor.test:9092 \
    --command-config client.properties
```

Alternatively, to run a Kafka client on an older version, you can use this docker command:

```bash
docker run --rm --network host \
  -e KAFKA_OPTS="-Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=conduktor" \
  -v $PWD/truststore.jks:/tmp/truststore.jks \
  -v $PWD/client_pre_ak4.properties:/tmp/client.properties \
  apache/kafka:3.8.0 /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server gateway.conduktor.test:9092 \
    --command-config /tmp/client.properties \
    --list
```

### Identity Provider

You can also manage OIDC keycloak server at [https://oidc.conduktor.test](https://oidc.conduktor.test) with the following credentials `admin` / `conduktor`.

### Grafana Dashboards

Port forward grafana to take a look at the dashboards.

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
```

Go to [http://localhost:3000](http://localhost:3000) and log in with `admin` and `admin` for username, password to explore the dashboards that ship with the Conduktor helm charts.

Press `Ctrl+C` to kill the port forward.

## Teardown

```bash
make stop-eks-stack
```

This uninstalls all Helm releases, removes Kubernetes manifests, ALB/NLB resources, and cleans Terraform state. The EKS cluster itself is not deleted.

To also destroy the AWS infrastructure:

```bash
make destroy-infra
```

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
            │          │     :8888│
    Console │  Keycloak│  Gateway │
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
| `01-start.sh` | Deploy all K8s dependencies |
| `02-install-conduktor-platform.sh` | Install Conduktor Console and Gateway |
| `03-init-conduktor-platform.sh` | Terraform provisioning (users, groups, clusters) |
| `04-stop.sh` | Teardown K8s resources |
| `console-values.yaml` | Console Helm values (S3, IRSA, OIDC) |
| `console-secrets.yaml` | Console secrets (empty S3 creds for IRSA) |
| `gateway-values.yaml` | Gateway Helm values (NLB, SNI routing) |
| `gateway-secrets.yaml` | Gateway secrets |
| `helm-values/` | Helm values for all dependencies |
| `manifests/` | Kubernetes manifests (parameterized with envsubst) |
| `provisioning/` | Terraform config for Conduktor resources (users, groups, clusters) |