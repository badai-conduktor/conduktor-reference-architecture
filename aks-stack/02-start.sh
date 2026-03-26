#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

echo "Loading AKS configuration..."
loadConfig
checkKubeContext

echo
echo "00 - Creating namespaces and storage class"
kubectl apply -f ${SCRIPT_DIR}/manifests/00-namespaces.yaml

# Create Standard SSD StorageClass for AKS
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-standard-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: disk.csi.azure.com
parameters:
  skuName: StandardSSD_LRS
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

echo
echo "01 - Adding Helm repositories"
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo
echo "02 - Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.17.0 \
  -f ${SCRIPT_DIR}/helm-values/cert-manager.yaml \
  --wait

echo
echo "03 - Installing trust-manager"
helm upgrade --install trust-manager jetstack/trust-manager \
  --namespace cert-manager \
  --version v0.16.0 \
  -f ${SCRIPT_DIR}/helm-values/trust-manager.yaml \
  --wait

echo
echo "Waiting for base components to be ready"
waitAvailable cert-manager deployment/cert-manager
waitAvailable cert-manager deployment/trust-manager

echo
echo "04 - Installing cert-manager CRDs (certificates and issuers)"
envsubst '$CONSOLE_DOMAIN $GATEWAY_DOMAIN $OIDC_DOMAIN' < ${SCRIPT_DIR}/manifests/01-cert-manager-crds.yaml | kubectl apply -f -

echo
echo "Waiting for certificate secrets to be created"
waitSecretCreated cdk-deps pg-main-crt-secret
waitSecretCreated cdk-deps pg-sql-crt-secret

echo
echo "05 - Installing Conduktor dependencies"

echo "Installing main-postgresql..."
helm upgrade --install main-postgresql bitnami/postgresql \
  --namespace cdk-deps \
  --version 16.6.0 \
  -f ${SCRIPT_DIR}/helm-values/postgresql-main.yaml

echo "Installing sql-postgresql..."
helm upgrade --install sql-postgresql bitnami/postgresql \
  --namespace cdk-deps \
  --version 16.6.0 \
  -f ${SCRIPT_DIR}/helm-values/postgresql-sql.yaml

echo "Installing kafka..."
helm upgrade --install kafka bitnami/kafka \
  --namespace cdk-deps \
  --version 32.1.2 \
  -f ${SCRIPT_DIR}/helm-values/kafka.yaml

echo "Installing vault..."
helm upgrade --install vault hashicorp/vault \
  --namespace cdk-deps \
  --version 0.30.0 \
  -f ${SCRIPT_DIR}/helm-values/vault.yaml

echo "Installing prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 70.3.0 \
  -f ${SCRIPT_DIR}/helm-values/prometheus.yaml

echo "Installing grafana-operator..."
helm upgrade --install grafana-operator bitnami/grafana-operator \
  --namespace monitoring \
  --version 4.9.0 \
  -f ${SCRIPT_DIR}/helm-values/grafana-operator.yaml

echo
echo "Waiting for dependencies to be ready"
waitRollout cdk-deps sts/main-postgresql
waitRollout cdk-deps sts/kafka-controller

# generate truststore for Schema registry using Kafka certificates
echo
echo "06 - Setting up Schema Registry"
generate_schema_registry_jks_truststore
kubectl apply -f ${SCRIPT_DIR}/manifests/03-schema-registry.yaml

echo
echo "07 - Installing Keycloak"
# Use explicit variable list to avoid clobbering Keycloak's own ${role_default-roles} and ${profileScopeConsentText}
envsubst '$OIDC_DOMAIN $CONSOLE_DOMAIN' < ${SCRIPT_DIR}/manifests/02-keycloak.yaml | kubectl apply -f -

echo
echo "08 - Installing Grafana CRDs"
kubectl apply -f ${SCRIPT_DIR}/manifests/04-grafana-crds.yaml

echo
echo "09 - Update CoreDNS config for Gateway SNI routing"
# AKS supports coredns-custom ConfigMap for custom CoreDNS configuration
envsubst '$GATEWAY_DOMAIN_ESCAPED $OIDC_DOMAIN_ESCAPED' < ${SCRIPT_DIR}/manifests/05-coredns-custom.yaml | kubectl apply -f -
# Restart CoreDNS pods to pick up configuration changes
kubectl -n kube-system delete pod -l k8s-app=kube-dns

echo
echo "10 - Generating JKS truststore"
# Extract and package all certificates into a JKS truststore for Conduktor Gateway and Conduktor Console
generate_jks_truststore

# Download the truststore to the local machine
kubectl get secret bundle-truststore -n conduktor -o jsonpath='{.data.truststore\.jks}' | base64 --decode > $SCRIPT_DIR/truststore.jks
kubectl get secret root-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 --decode > $SCRIPT_DIR/ca.crt

echo
echo "11 - Uploading wildcard certificate to Azure Key Vault"
# Export the cert-manager wildcard cert and key, convert to PFX, and import to Key Vault
# This replaces the Terraform-generated self-signed placeholder with a CA-signed cert
wildcard_temp=$(mktemp -d)
waitSecretCreated conduktor wildcard-crt-secret
kubectl get secret wildcard-crt-secret -n conduktor -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$wildcard_temp/tls.crt"
kubectl get secret wildcard-crt-secret -n conduktor -o jsonpath="{.data['tls\.key']}" | base64 --decode > "$wildcard_temp/tls.key"
kubectl get secret root-ca-secret -n cert-manager -o jsonpath="{.data['ca\.crt']}" | base64 --decode > "$wildcard_temp/ca.crt"
cat "$wildcard_temp/tls.crt" "$wildcard_temp/ca.crt" > "$wildcard_temp/fullchain.crt"
openssl pkcs12 -export \
  -inkey "$wildcard_temp/tls.key" \
  -in "$wildcard_temp/fullchain.crt" \
  -out "$wildcard_temp/wildcard.pfx" \
  -passout pass:
az keyvault certificate import \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "conduktor-wildcard-cert" \
  --file "$wildcard_temp/wildcard.pfx"
rm -rf "${wildcard_temp:?Missing temp dir}"

echo
echo "12 - Uploading trusted root CA certificate to Application Gateway"
az network application-gateway root-cert create \
  --gateway-name "${AKS_CLUSTER_NAME}-appgw" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name local-selfsigned-ca \
  --cert-file "$SCRIPT_DIR/ca.crt"

echo
echo "13 - Creating AGIC Ingress resources"

# AGIC Ingress for Console
envsubst '$CONSOLE_DOMAIN $KEY_VAULT_CERT_SECRET_ID' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: console-appgw-ingress
  namespace: conduktor
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "conduktor-wildcard-cert"
    appgw.ingress.kubernetes.io/appgw-trusted-root-certificate: "local-selfsigned-ca"
    appgw.ingress.kubernetes.io/backend-protocol: "https"
    appgw.ingress.kubernetes.io/backend-hostname: "${CONSOLE_DOMAIN}"
    appgw.ingress.kubernetes.io/health-probe-path: "/"
spec:
  rules:
    - host: ${CONSOLE_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: conduktor-console
                port:
                  number: 80
INGRESS_EOF

# AGIC Ingress for Gateway admin API
envsubst '$GATEWAY_DOMAIN $KEY_VAULT_CERT_SECRET_ID' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateway-admin-appgw-ingress
  namespace: conduktor
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "conduktor-wildcard-cert"
    appgw.ingress.kubernetes.io/appgw-trusted-root-certificate: "local-selfsigned-ca"
    appgw.ingress.kubernetes.io/backend-protocol: "https"
    appgw.ingress.kubernetes.io/backend-hostname: "${GATEWAY_DOMAIN}"
    appgw.ingress.kubernetes.io/health-probe-path: "/"
spec:
  rules:
    - host: ${GATEWAY_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: conduktor-gateway-external
                port:
                  number: 8888
INGRESS_EOF

# AGIC Ingress for Keycloak
envsubst '$OIDC_DOMAIN $KEY_VAULT_CERT_SECRET_ID' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-appgw-ingress
  namespace: cdk-deps
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "conduktor-wildcard-cert"
    appgw.ingress.kubernetes.io/appgw-trusted-root-certificate: "local-selfsigned-ca"
    appgw.ingress.kubernetes.io/backend-protocol: "https"
    appgw.ingress.kubernetes.io/backend-hostname: "${OIDC_DOMAIN}"
    appgw.ingress.kubernetes.io/health-probe-path: "/"
spec:
  rules:
    - host: ${OIDC_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak
                port:
                  name: https
INGRESS_EOF

cat <<EOF

AKS stack deployment complete!

Next steps:
  1. make install-conduktor-platform

  2. Copy the output of the following command into /etc/hosts
     ./get-hosts.sh

  3. make init-conduktor-platform

  4. Have fun with Console and Gateway!!
EOF
