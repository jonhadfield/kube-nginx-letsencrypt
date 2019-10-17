#/bin/bash
set -eo pipefail

echo "ACME authenticator: setting env vars"
ls /hooks
. /hooks/.env

if [[ -z $ACME_SECRETNAME || -z $NAMESPACE ]]; then
	echo "ACME_SECRETNAME or NAMESPACE not set"
    NAMESPACE="qa"
    ACME_SECRETNAME="qa-acmechallenge-secret"
fi

echo "ACME authenticator: preparing patch to update the challenge secret"

CERTBOT_VALIDATION_B64=$(echo $CERTBOT_VALIDATION | base64)

cat /challenge-secret-patch-template.json | \
	sed "s/ACME_SECRETNAME/${ACME_SECRETNAME}/" | \
	sed "s/ACME_SECRETNAMESPACE/${NAMESPACE}/" | \
    sed "s/ACME_TOKEN/${CERTBOT_TOKEN}/" | \
    sed "s/ACME_TOKEN_CONTENT/${CERTBOT_VALIDATION_B64}/" | \
	> /challenge-secret-patch.json

ls /challenge-secret-patch.json

echo "ACME authenticator: updating challenge secret '${ACME_SECRETNAME}' with token '${CERTBOT_TOKEN}'"
curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/challenge-secret-patch.json https://kubernetes/api/v1/namespaces/${NAMESPACE}/secrets/${ACME_SECRETNAME}

echo "ACME authenticator: waiting 5 seconds before attempting to read from secret"
sleep 5
