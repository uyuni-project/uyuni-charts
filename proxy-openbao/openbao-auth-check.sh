#!/bin/bash
# SPDX-FileCopyrightText: 2026 SUSE LLC
# SPDX-FileContributor: Cédric Bosdonnat
#
# SPDX-License-Identifier: MIT

# --- DEFAULT VALUES ---
SA_NAME="openbao-issuer-sa"
SA_NS="cert-manager"
ISSUER_NAME="uyuni-openbao-issuer"
BAO_ROLE="uyuni-issuer-role"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Mandatory Parameters:"
    echo "  -p, --primary-ctx   Kubernetes context for the Primary cluster (where OpenBao runs)"
    echo "  -s, --secondary-ctx Kubernetes context for the Secondary cluster (Proxy cluster)"
    echo "  -a, --openbao-addr  The full URL of the OpenBao server"
    echo "  -m, --mount         The internal OpenBao mount path (e.g., kubernetes/uyuni-proxy-cluster)"
    echo ""
    echo "Optional Parameters:"
    echo "  -r, --role          The OpenBao role name (default: uyuni-issuer-role)"
    echo "  -n, --namespace     The namespace where cert-manager is installed (default: cert-manager)"
    echo "  -i, --issuer        The name of the ClusterIssuer to verify (default: uyuni-openbao-issuer)"
    echo "  -h, --help          Show this help message"
    exit 1
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--primary-ctx) PRIMARY_CTX="$2"; shift ;;
        -s|--secondary-ctx) SECONDARY_CTX="$2"; shift ;;
        -a|--bao-addr) BAO_ADDR="$2"; shift ;;
        -m|--mount) BAO_MOUNT="$2"; shift ;;
        -r|--role) BAO_ROLE="$2"; shift ;;
        -n|--namespace) SA_NS="$2"; shift ;;
        -i|--issuer) ISSUER_NAME="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate mandatory parameters
if [[ -z "$PRIMARY_CTX" || -z "$SECONDARY_CTX" || -z "$BAO_ADDR" || -z "$BAO_MOUNT" ]]; then
    echo "❌ ERROR: Missing mandatory parameters."
    usage
fi

# Set defaults for optional parameters if not provided
BAO_ROLE=${BAO_ROLE:-"uyuni-issuer-role"}
BAO="kubectl --context $PRIMARY_CTX exec -ti -n openbao-system openbao-0 -- bao"

echo "--------------------------------------------------------"
echo "🔍 Starting OpenBao Multi-Cluster Auth Verification"
echo "--------------------------------------------------------"

# ClusterIssuer mountPath Alignment
echo "Validating ClusterIssuer 'mountPath' configuration..."
ISSUER_MOUNT=$(kubectl --context "$SECONDARY_CTX" get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.vault.auth.kubernetes.mountPath}')
EXPECTED_MOUNT="/v1/auth/$BAO_MOUNT"

if [ "$ISSUER_MOUNT" != "$EXPECTED_MOUNT" ]; then
    echo "  ❌ ERROR: ClusterIssuer mountPath mismatch!"
    echo "     Found:    $ISSUER_MOUNT"
    echo "     Expected: $EXPECTED_MOUNT"
    echo "     Action: Update the 'openbao.auth.mountPath' value in your helm chart."
else
    echo "  ✅ Success: ClusterIssuer mountPath correctly points to $EXPECTED_MOUNT."
fi

# Network Connectivity
echo "Checking connectivity from Secondary Cluster to OpenBao..."
if ! kubectl --context "$SECONDARY_CTX" run net-test --image=curlimages/curl --rm -it --restart=Never -- \
    curl -k -s -o /dev/null -w "%{http_code}" "$BAO_ADDR/v1/sys/health" | grep -q "200"; then
    echo "  ❌ ERROR: Secondary cluster cannot reach OpenBao at $BAO_ADDR"
else
    echo "  ✅ Success: Network path to OpenBao is open."
fi

# Token Reviewer RBAC
echo "Verifying Token Reviewer RBAC on Secondary Cluster..."
REVIEWER_SA=$(kubectl --context "$SECONDARY_CTX" -n "$SA_NS" get secret openbao-reviewer-token -o jsonpath='{.metadata.annotations.kubernetes\.io/service-account\.name}' 2>/dev/null)

if [ -z "$REVIEWER_SA" ]; then
    echo "  ❌ ERROR: Secret 'openbao-reviewer-token' not found in namespace $SA_NS."
else
    CAN_I=$(kubectl --context "$SECONDARY_CTX" auth can-i create tokenreviews.authentication.k8s.io -A --as "system:serviceaccount:$SA_NS:$REVIEWER_SA")
    if [ "$CAN_I" != "yes" ]; then
        echo "  ❌ ERROR: Reviewer SA '$REVIEWER_SA' lacks 'system:auth-delegator' permissions."
    else
        echo "  ✅ Success: Reviewer SA has correct RBAC permissions."
    fi
fi

# OpenBao Mount Config
echo "Verifying OpenBao Auth Mount Config (auth/$BAO_MOUNT)..."
CONFIG_DATA=$($BAO read -format=json "auth/$BAO_MOUNT/config" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "  ❌ ERROR: Could not read config for auth/$BAO_MOUNT. Check if 'kubernetes/' prefix is correct."
else
    REV_SET=$(echo "$CONFIG_DATA" | jq -r '.data.token_reviewer_jwt_set')
    ISS_VAL=$(echo "$CONFIG_DATA" | jq -r '.data.disable_iss_validation')
    [[ "$REV_SET" == "true" ]] && echo "  ✅ Success: Reviewer JWT is set." || echo "  ❌ ERROR: token_reviewer_jwt is NOT set."
    [[ "$ISS_VAL" == "true" ]] && echo "  ✅ Success: Issuer validation is disabled." || echo "  ⚠️  WARN: disable_iss_validation is false."
fi

# Role Audience
echo "Checking Role Audience..."
ROLE_AUDIENCE=$($BAO read -format=json "auth/$BAO_MOUNT/role/$BAO_ROLE" | jq -r '.data.audience // empty')
if [[ -z "$ROLE_AUDIENCE" ]]; then
    echo "  ⚠️  WARN: No audience set in role."
else
    echo "  ✅ Success: Role audience set to '$ROLE_AUDIENCE'."
fi

# PKI Role Verification
echo "Verifying PKI Role..."
PKI_ROLE=$(kubectl --context $SECONDARY_CTX get clusterissuer -o "jsonpath={.spec.vault.path}" $ISSUER_NAME)
ROLE_CONFIG_PATH=$(echo "$PKI_ROLE" | sed 's/\/sign\//\/roles\//')
PKI_CONFIG=$($BAO read -format=json "$ROLE_CONFIG_PATH" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "  ❌ ERROR: Could not read PKI role at $PKI_ROLE. Check pkiPath."
else
    ALLOWED_DOMAINS=$(echo "$PKI_CONFIG" | jq -r '.data.allowed_domains[]')
    echo "  ✅ Success: PKI role exists. Allowed domains: $(echo $ALLOWED_DOMAINS | tr '\n' ' ')"
fi

# Simulated Login
echo "Performing Manual Login Test with Fresh Token..."
TEST_TOKEN=$(kubectl --context "$SECONDARY_CTX" -n "$SA_NS" create token "$SA_NAME" --audience "$ROLE_AUDIENCE")
LOGIN_RESULT=$(curl -s -k --request POST \
    --data "{\"jwt\": \"$TEST_TOKEN\", \"role\": \"$BAO_ROLE\"}" \
    "$BAO_ADDR/v1/auth/$BAO_MOUNT/login")

if echo "$LOGIN_RESULT" | grep -q "client_token"; then
    echo "  ✨ SUCCESS: Manual login verified! The authentication chain is fully functional."
else
    echo "  ❌ ERROR: Login failed. Response:"
    echo "$LOGIN_RESULT" | jq .
fi
