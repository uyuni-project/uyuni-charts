<!--
SPDX-FileCopyrightText: 2026 SUSE LLC
SPDX-FileContributor: Cédric Bosdonnat

SPDX-License-Identifier: MIT
-->

# Requirements

Before installing this helm chart, ensure that [cert-manager](https://cert-manager.io/docs/installation/helm/) and
[trust-manager](https://cert-manager.io/docs/trust/trust-manager/installation/#3-install-trust-manager) are installed in the cluster.
If they are not installed in the `cert-manager` namespace, set the `certManagerNamespace` value.

[OpenBao](https://openbao.org) or Hashicorp [Vault](https://developer.hashicorp.com/vault) needs to be installed and configured for PKI secrets.
It also needs to allow cert-manager to authenticate.
See the cert-manager [Vault issuer documentation](https://cert-manager.io/docs/configuration/vault/) for details.

Also read the requirements in the main [README](../) as they apply here too.

The following values need to be set:

```
credentials:
  db:
    admin:
      password: ...
    internal:
      password: ...
    reportdb:
      password: ...
  admin:
    password: ...

global:
  fqdn: "your.fq.dn"

server-helm:
  # All the values for server-helm should follow
```

The root CA certificate is expected to be stored in the `ca.crt` value of a secret in the cert-manager namespace.
By default, the `root-ca` secret will be looked for, but another name can be set using the `rootCA` value.

# OpenBao setup

## Test lab installation

This section describes how to install OpenBao on the same Kubernetes cluster than Uyuni and cert-manager with Kubernetes authentication, static seal key and a file storage.
The goal of this is to easily play with the helm chart for testing purpose.

**This is in no way a recommended setup for production!**

### Prepare the configuration

Create an `openbao-system` namespace to install OpenBao in:

```sh
kubectl create ns openbao-system
```

In this setup, OpenBao will also have TLS encrypted communication between the Ingress and the pod.
This means that it will need certificates.
Let's create them using cert-manager, apply the following definition after changing the FQDN:

```yaml
# Root issuer generating self-signed certificates
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: root-issuer
  namespace: cert-manager
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: root-ca
  namespace: cert-manager
spec:
  isCA: true
  subject:
    countries: ["DE"]
    provinces: ["Bayern"]
    localities: ["Nuernberg"]
    organizations: ["SUSE"]
    organizationalUnits: ["lab"]
  commonName: Root CA
  dnsNames:
    - FQDN
  duration: 518400h # 1 year
  secretName: root-ca
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  issuerRef:
    name: root-issuer
    kind: Issuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: main-issuer
spec:
  ca:
    secretName: root-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openbao-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: OpenBao CA
  issuerRef:
    kind: ClusterIssuer
    name: main-issuer
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    rotationPolicy: Always
    size: 2048
  secretName: openbao-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-server-cert
  namespace: openbao-system
spec:
  dnsNames:
  - 'openbao-internal'
  - 'openbao-internal.openbao-system'
  - 'openbao-internal.openbao-system.svc'
  - 'openbao-internal.openbao-system.svc.cluster.local'
  ipAddresses:
  - 127.0.0.1
  issuerRef:
    kind: ClusterIssuer
    name: main-issuer
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    rotationPolicy: Always
    size: 2048
  secretName: internal-server-tls
  subject:
    organizations:
    - SUSE
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: public-server-cert
  namespace: openbao-system
spec:
  dnsNames:
  - FQDN
  issuerRef:
    kind: ClusterIssuer
    name: main-issuer
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    rotationPolicy: Always
    size: 2048
  secretName: public-server-tls
  subject:
    organizations:
    - SUSE
```

Create an `openbao-values.yaml` with the following content and adjust the FQDNs too:

```yaml
global:
  enabled: true
  tlsDisable: false

server:
  extraEnvironmentVars:
    BAO_CACERT: /openbao/userconfig/openbao-server-tls/ca.crt

  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
      nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
      nginx.ingress.kubernetes.io/proxy-ssl-name: "openbao-internal"
      nginx.ingress.kubernetes.io/proxy-ssl-secret: "openbao-system/internal-server-tls"
    ingressClassName: "nginx"
    hosts:
      - host: FQDN
    tls:
      - secretName: public-server-tls
        hosts:
          - FQDN

  volumes:
    - name: unseal-key
      secret:
        secretName: unseal-key
    - name: userconfig-openbao-server-tls
      secret:
        defaultMode: 420
        secretName: internal-server-tls

  volumeMounts:
    - mountPath: /keys
      name: unseal-key
      readOnly: true
    - mountPath: /openbao/userconfig/openbao-server-tls
      name: userconfig-openbao-server-tls
      readOnly: true

  standalone:
    enabled: true
    config: |
      audit "file" "to-stdout" {
        description = "This audit device should never fail."
        options {
          file_path = "/dev/stdout"
          log_raw = "true"
        }
      }

      listener "tcp" {
        address = "[::]:8200"
        cluster_address = "[::]:8201"
        tls_cert_file = "/openbao/userconfig/openbao-server-tls/tls.crt"
        tls_key_file  = "/openbao/userconfig/openbao-server-tls/tls.key"
        tls_client_ca_file = "/openbao/userconfig/openbao-server-tls/ca.crt"
      }

      storage "file" {
        path = "/openbao/data"
      }

      seal "static" {
        current_key_id = "unseal-openbao-1"
        current_key = "file:///keys/unseal-openbao-1.key"
        disabled = false
      }
```

For the static unseal, a secret needs to be generated.
Run the following commands:

```sh
openssl rand -out unseal-openbao.key 32
kubectl create secret generic -n openbao-system unseal-key --from-file=unseal-openbao-1.key=./unseal-openbao.key
```

Keep this key safe: without it, the data are lost.

### openbao installation

Now install the OpenBao helm chart:

```sh
helm install -n openbao-system openbao --repo https://openbao.github.io/openbao-helm openbao -f openbao-values.yaml
```

For the first run, the OpenBao server needs to be initialized.
Run the following command for this and save the output recovery keys and root token safely.

```sh
kubectl exec -ti -n openbao-system openbao-0 -- bao operator init
```

### Authenticate as root

In order to perform the admin tasks in the next section, authenticate as root by running:

```sh
kubectl exec -ti -n openbao-system openbao-0 -- bao login
```

Enter the previously saved root token.


## OpenBao Configuration

In the following commands, `$BAO` needs to be changed to `kubectl exec -ti -n openbao-system openbao-0 -- bao` if OpenBao has been installed in the same Kubernetes cluster as the one we are installing Uyuni to.
This assumes, that the bao client is already logged in.

Run these commands on your OpenBao instance before installing:

### Enable PKI and Create Role

Set `$DOMAIN` to the domain name for the uyuni server and all its proxies.

```bash
   $BAO secrets enable pki
   $BAO write pki/roles/uyuni-role allowed_domains="$DOMAIN,db,reportdb" allow_bare_domains=true require_cn=false allow_subdomains=true max_ttl="720h"
```

*Note that the `db` and `reportdb` bare domains are required to generate the database TLS certificate.*

**The email address configured in the `ssl.email` value needs to be within a subdomain of the FQDN configured here, otherwise the certificate request will be rejected by OpenBao.**

### Configure Kubernetes Auth

**Note:** this example implements the Kubernetes authentication, but there are other possible with openbao and cert-manager.
See the possible ones in the [issuer documentation](https://cert-manager.io/docs/configuration/vault/#authenticating).
If another authentication is needed, modify the `uyuni-openbao-issuer` definition in the `templates/certificates.yaml` file.

Each Kubernetes cluster needs it own authentication path in OpenBao.
In the following commands change `CLUSTER_PATH` to be unique on the OpenBao server.

**Important:** the `CLUSTER_PATH` value needs to be set in the `openbao.auth.mountPath` value.

```bash
CLUSTER_PATH=kubernetes/uyuni-server-cluster
$BAO auth enable -path $CLUSTER_PATH kubernetes
CLUSTER_URL=`kubectl cluster-info | grep Kubernetes | sed 's/^.*\(http.*\)$/\1/'`
$BAO write auth/$CLUSTER_PATH/config kubernetes_host="$CLUSTER_URL"
```

### Create Policy & Bind Role: Create `uyuni-pki-policy.hcl`

```
path "pki/sign/uyuni-role" { capabilities = ["create", "update"] }
path "pki/*" { capabilities = ["read", "list"] }
```

Replace the `ISSUER_ROLE` with the value used for the server configuration if different from the default and run the following commands to apply the policy.
Also remember to reflect the `ISSUER_ROLE` value in the `openbao.auth.roleName` value.

`CERT_MANAGER_NAMESPACE` needs to be set to the namespace where cert-manager is installed.

```bash
ISSUER_ROLE=uyuni-issuer-role
CERT_MANAGER_NAMESPACE=cert-manager
cat uyuni-pki-policy.hcl | $BAO policy write uyuni-pki-policy -
$BAO write auth/$CLUSTER_PATH/role/$ISSUER_ROLE \
     bound_service_account_names=openbao-issuer-sa \
     bound_service_account_namespaces=$CERT_MANAGER_NAMESPACE \
     token_policies=uyuni-pki-policy
```

### The root CA

This helm chart assumes the root-ca is in a `root-ca` secret in the `cert-manager` namespace.
If this is not the case, adjust the values for trust-manager to pack it in config maps for Uyuni to use it.

**Note** that uploading the root CA to OpenBao would not prevent from installing it on the other clusters: the OpenBao issuer would need it to login and get the root CA certificate.
This is the chicken and egg problem.

### Generate the intermediate CA for OpenBao

A CA will be needed by OpenBao to generate the Uyuni certificates.
In this example an intermediate CSR is generated by OpenBao, signed by the root CA managed by cert-manager and the signed certificate is uploaded back to OpenBao.
There are other ways to get a CA on OpenBao, but an intermediate CA on OpenBao is safer.

Generate the CSR:

```sh
$BAO write -format=json pki/intermediate/generate/internal \
             common_name="OpenBao Intermediate CA" \
             ttl=43800h | jq -r '.data.csr' > openbao.csr
```

Create a YAML file for the cert-manager certificate request.
This file will be named `openbao-csr.yaml` and the result of `base64 -w0 openbao.csr` needs to be set in `spec.request`:

```yaml
apiVersion: cert-manager.io/v1
kind: CertificateRequest
metadata:
  name: openbao-intermediate-request
  namespace: cert-manager
spec:
  request: <BASE64_ENCODED_CSR_ON_ONE_LINE>
  isCA: true
  usages:
    - key encipherment
    - content commitment
    - digital signature
    - cert sign
    - crl sign
  issuerRef:
    name: main-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

Get the signed certificate and upload it to OpenBao:

```sh
kubectl apply -f openbao-csr.yaml
kubectl get cr -n cert-manager openbao-intermediate-request -o "jsonpath={.status.certificate}" | base64 -d >openbao.crt
$BAO write pki/config/urls \
             issuing_certificates="https://$OPENBAO_FQDN/v1/pki/ca" \
             crl_distribution_points="https://$OPENBAO_FQDN/v1/pki/crl"
cat openbao.crt | $BAO write pki/intermediate/set-signed certificate=-
```


## cert-manager RBAC

Cert-manager will have to request tokens for the service account to be able to authenticate to OpenBao.
This helm chart will add the necessary service account and add the cluster role and role binding for this: permissions will be needed for this.

# Uninstalling

**Uninstalling OpenBao doesn't remove the persistent volume and its claim, they need to be manually deleted.**

By default, `cert-manager` does not remove the created secrets.
In such a case, delete them after uninstalling the helm chart:

```
kubectl delete secrets -n cert-manager uyuni-ca
kubectl delete secrets -n <uyuni-namspace> db-cert uyuni-cert
```
