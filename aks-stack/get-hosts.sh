#!/usr/bin/env sh
set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

loadConfig

# Application Gateway public IP (for Console, Gateway admin, Keycloak)
APPGW_IP=$(kubectl get ingress console-appgw-ingress -n conduktor -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
# Azure Load Balancer IP (for Gateway Kafka proxy)
LB_IP=$(kubectl get svc conduktor-gateway-external -n conduktor -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$APPGW_IP" ] || [ -z "$LB_IP" ]; then
  echo "Application Gateway or Load Balancer not ready yet. Please re-run this script later."
  [ -z "$APPGW_IP" ] && echo "  - App Gateway: not provisioned (check 'kubectl get ingress -n conduktor')"
  [ -z "$LB_IP" ] && echo "  - Load Balancer: not provisioned (check 'kubectl get svc -n conduktor')"
  exit 1
fi

# Import App Gateway certificate into local truststore
openssl s_client -connect "${APPGW_IP}:443" -servername "${CONSOLE_DOMAIN}" </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > "$SCRIPT_DIR/appgw-cert.crt"
keytool -importcert -noprompt \
  -alias appgw-self-signed \
  -file "$SCRIPT_DIR/appgw-cert.crt" \
  -keystore "$SCRIPT_DIR/truststore.jks" \
  -storepass conduktor 2>/dev/null || true
rm -f "$SCRIPT_DIR/appgw-cert.crt"
echo "App Gateway certificate imported into truststore.jks"

echo
echo "Add the following lines to /etc/hosts:"
echo
echo "$APPGW_IP  ${CONSOLE_DOMAIN} ${OIDC_DOMAIN}"
echo "$LB_IP  ${GATEWAY_DOMAIN} brokermain0.${GATEWAY_DOMAIN} brokermain1.${GATEWAY_DOMAIN} brokermain2.${GATEWAY_DOMAIN} brokermain3.${GATEWAY_DOMAIN}"
