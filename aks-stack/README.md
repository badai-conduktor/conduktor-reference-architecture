# Conduktor Platform on Azure AKS

Deploy the Conduktor platform (Console + Gateway) and all dependencies to an Azure AKS cluster.

This stack mirrors the `eks-stack/` deployment but uses Azure-managed services:

- **Azure Application Gateway (AGIC)** instead of AWS ALB (HTTPS for Console, Gateway admin, Keycloak)
- **Azure Load Balancer (L4)** for Kafka TCP traffic (Gateway SNI routing on port 9092)
- **Azure Blob Storage** instead of AWS S3 for Cortex monitoring storage
- **Azure Workload Identity** instead of IRSA for Blob Storage access
- **Azure Key Vault** for wildcard TLS certificate management
- **Azure Managed Disks (Standard SSD)** for persistent storage

All other components (Kafka, PostgreSQL, Keycloak, Vault, Schema Registry, Prometheus, Grafana) run self-hosted on AKS.

## Prerequisites

- Azure CLI (`az`) installed and authenticated (`az login`)
- Tools installed locally: `helm`, `kubectl`, `terraform`, `yq`, `envsubst`, `keytool`, `openssl`
- A valid Conduktor license key

## Quick Start

### 1. Deploy Azure infrastructure

```bash
cd aks-stack/infrastructure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your Azure-specific values (subscription ID, resource names, region).

```bash
cd ..
make infra
```

This creates the Resource Group, VNet, AKS cluster, Application Gateway, Storage Account, Key Vault (with wildcard certificate), and Workload Identity for Cortex. It also configures `kubectl`.

### 2. Configure

```bash
cp config.env.example config.env
```

Edit `config.env` with values from the Terraform outputs:

```bash
export AZURE_SUBSCRIPTION_ID=your-subscription-id
export AZURE_REGION=eastus
export AZURE_RESOURCE_GROUP=conduktor-aks-rg
export AKS_CLUSTER_NAME=conduktor-aks
export KUBE_CONTEXT="${AKS_CLUSTER_NAME}"

export CONSOLE_DOMAIN=console.conduktor.test
export GATEWAY_DOMAIN=gateway.conduktor.test
export OIDC_DOMAIN=oidc.conduktor.test

export STORAGE_ACCOUNT_NAME=conduktorstorage
export BLOB_CONTAINER_NAME=conduktor-monitoring
export KEY_VAULT_NAME=conduktor-kv
export KEY_VAULT_CERT_SECRET_ID=https://conduktor-kv.vault.azure.net/secrets/conduktor-wildcard-cert
export CORTEX_IDENTITY_CLIENT_ID=00000000-0000-0000-0000-000000000000
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
make start-aks-stack
```

This installs cert-manager, trust-manager, PostgreSQL (x2), Kafka, Vault, Prometheus, Grafana, Schema Registry, and Keycloak. It also creates AGIC Ingress resources for Console, Gateway admin, and Keycloak.

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

> **Using real domains?** If you own a domain, create DNS records instead: point `console.yourdomain.com`, `gateway.yourdomain.com`, `oidc.yourdomain.com` to the Application Gateway public IP, and `*.gateway.yourdomain.com` to the Azure Load Balancer IP.

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

You can reach the Conduktor Gateway Admin API at [https://gateway.conduktor.test](https://gateway.conduktor.test).

```bash
curl -k -u admin:adminP4ss! \
    'https://gateway.conduktor.test/gateway/v2/interceptor'
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
make stop-aks-stack
```

This uninstalls all Helm releases, removes Kubernetes manifests, AGIC Ingress resources, and cleans Terraform state. The AKS cluster itself is not deleted.

To also destroy the Azure infrastructure:

```bash
make destroy-infra
```

## Architecture

```
                     Internet
                        │
            ┌───────────┼───────────┐
            │           │           │
      ┌─────▼─────┐ ┌──▼──┐   ┌───▼───┐
      │ App       │ │ App │   │ Azure │
      │ Gateway   │ │ GW  │   │  LB   │
      │ :443      │ │:443 │   │ :9092 │
      └─────┬─────┘ └──┬──┘   └───┬───┘
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
    ┌────▼──▼────┐    ┌──────────────┐
    │ PostgreSQL │    │ Azure Blob   │
    │ (main+sql) │    │ Storage      │
    └────────────┘    │ (Cortex)     │
                      └──────────────┘
```

## File Reference

| File | Description |
|---|---|
| `infrastructure/` | Terraform for Azure infrastructure (AKS, App Gateway, Storage, Key Vault) |
| `config.env.example` | Configuration template — copy to `config.env` |
| `kubernetes_utils.sh` | Shared shell functions (config loading, waits, truststore generation) |
| `01-infra.sh` | Deploy Azure infrastructure via Terraform |
| `02-start.sh` | Deploy all K8s dependencies |
| `03-install-conduktor-platform.sh` | Install Conduktor Console and Gateway |
| `04-init-conduktor-platform.sh` | Terraform provisioning (users, groups, clusters) |
| `05-stop.sh` | Teardown K8s resources |
| `06-destroy-infra.sh` | Destroy Azure infrastructure |
| `console-values.yaml` | Console Helm values (Blob Storage, Workload Identity, OIDC) |
| `console-secrets.yaml` | Console secrets (empty Blob creds for Workload Identity) |
| `gateway-values.yaml` | Gateway Helm values (Azure LB, SNI routing) |
| `gateway-secrets.yaml` | Gateway secrets |
| `helm-values/` | Helm values for all dependencies |
| `manifests/` | Kubernetes manifests (parameterized with envsubst) |
| `provisioning/` | Terraform config for Conduktor resources (symlinks to local-stack modules) |
