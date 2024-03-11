#!/bin/bash

# ######################
#
#   USER CONFIGURATION
#
# change the below values to match your kentik plan number, your email/token
# associated with your kentik account, and the device in question (e.g., a
# kubernetes cluster)
#
# ######################
#
# You must set these four as appropriate for your account and device
#
ACCOUNTREGION=US
PLAN=0123456789
EMAIL=customer_email@example.com
TOKEN=123abc_your_customer_kentik_token_cba321
CLOUDPROVIDER=aws_or_gcp_or_azure_or_prem
CLOUDREGION=eg_us-west-2_or_something_custom_for_prem
ENVIRONMENT=free_form_such_as_production_or_staging_or_dev_or_custom
CLUSTER=your_cluster_name
#
# Don't change the below values unless you know for sure it's what you want.
#
CAPTURE='en*|veth.*|eth*'
KUBEMETA_VERSION=sha-6589ba8
MAX_PAYLOAD_SIZE_MB=16
KAPPA_SAMPLE_RATIO=1:4
# ######################
#
#   END CONFIGURATION
#
# ######################

K8S_CONTEXT=""
KUBECONFIG_FILE=""

function display_help() {
    echo "Usage: $0 [-c <k8s context>] [-f <k8s config file>]"
    echo "  -c  Specify the Kubernetes context. (optional)"
    echo "  -f  Specify the kubeconfig file to use. (optional)"
    echo "  -h  Display this help message."
    exit 1
}

get_or_create_cluster_uuid() {
  local config_map_name="kentik-config"
  local uuid_key="cluster-uuid"
  local lock_name="kentik-config-lock"
  local lock_timeout=300 # Adjust the lock timeout as needed (e.g., 5 minutes)

  # Attempt to retrieve the UUID from the config map
  local uuid=$(kubectl get configmap "$config_map_name" -o jsonpath="{.data.$uuid_key}" 2>/dev/null)

  if [[ -n "$uuid" ]]; then
    echo "$uuid"
    return 0
  fi

  # UUID not found in the config map, generate a new one
  local new_uuid=$(uuidgen)

  # Safely create or update the config map using a lock
  if kubectl create configmap "$lock_name" --from-literal=lock=true &>/dev/null; then
    # Lock acquired, proceed with creating or updating the config map
    kubectl create configmap "$config_map_name" --from-literal="$uuid_key"="$new_uuid" 2>/dev/null || \
      kubectl patch configmap "$config_map_name" --type=merge -p "{\"data\":{\"$uuid_key\":\"$new_uuid\"}}"

    # Release the lock
    kubectl delete configmap "$lock_name"

    echo "$new_uuid"
    return 0
  else
    # Lock not acquired. First make sure we're not dealing with a stale lock.
    local lock_info=$(kubectl get configmap "$lock_name" -o jsonpath="{.metadata.creationTimestamp} {.metadata.uid}" 2>/dev/null)

    if [[ -n "$lock_info" ]]; then
      local lock_creation_timestamp=$(echo "$lock_info" | awk '{print $1}')
      local lock_uid=$(echo "$lock_info" | awk '{print $2}')
      local current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      local lock_age=$(($(date -d "$current_timestamp" +%s) - $(date -d "$lock_creation_timestamp" +%s)))

      if ((lock_age > lock_timeout)); then
        # Stale lock detected, attempt to delete it using the UID
        kubectl delete configmap --uid="$lock_uid"

        # Retry the whole process from the beginning
        get_or_create_cluster_uuid
        return $?
      fi
    fi

    # Lock is still valid or has been deleted, wait and retry
    local retry_interval=1
    local max_retries=5

    for ((i=1; i<=max_retries; i++)); do
      sleep "$retry_interval"

      uuid=$(kubectl get configmap "$config_map_name" -o jsonpath="{.data.$uuid_key}" 2>/dev/null)

      if [[ -n "$uuid" ]]; then
        echo "$uuid"
        return 0
      fi
    done

    echo "Failed to retrieve or create the cluster UUID after $max_retries retries" >&2
    exit 1
  fi
}

# some optional commandline args
while getopts 'c:f:h' flag; do
    case "${flag}" in
        c) K8S_CONTEXT="${OPTARG}" ;;
        f) KUBECONFIG_FILE="${OPTARG}" ;;
        h) display_help ;;
        *) display_help ;;
    esac
done

# Check for valid CLOUDPROVIDER value
valid_providers=("aws" "gcp" "azure" "prem")
is_valid_provider=false

for provider in "${valid_providers[@]}"; do
    if [[ "$CLOUDPROVIDER" == "$provider" ]]; then
        is_valid_provider=true
        break
    fi
done

if [[ "$is_valid_provider" == false ]]; then
    echo
    echo "Error: Invalid CLOUDPROVIDER value ($CLOUDPROVIDER). Must be one of: aws, gcp, azure, or prem"
    echo
    exit 1
fi

# convert MAX_PAYLOAD_SIZE_MB to bytes
MAX_PAYLOAD_SIZE_BYTES=$((MAX_PAYLOAD_SIZE_MB * 1024 * 1024))


echo "Going to apply the kube yaml configuration with the following values:"
echo
echo "Account Region: $ACCOUNTREGION"
echo "Plan:           $PLAN"
echo "Email:          $EMAIL"
echo "Token:          $TOKEN"
echo "Cloud:          $CLOUDPROVIDER"
echo "Cluster:        $CLUSTER"
echo "Cloud Region:   $CLOUDREGION"
echo "Environment:    $ENVIRONMENT"
echo
echo "Capture:        $CAPTURE"
echo "Kappa Sample:   $KAPPA_SAMPLE_RATIO"
echo "Kubemeta:       $KUBEMETA_VERSION"
echo "MaxPayload:     ${MAX_PAYLOAD_SIZE_MB}MB"
echo
read -p "Do you want to proceed (y/n)? " confirmation

if [[ ! "${confirmation}" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 1
fi

case $ACCOUNTREGION in
    US)
        GRPCENDPOINT="grpc.api.kentik.com"
        ;;
    EU)
        GRPCENDPOINT="grpc.api.kentik.eu"
        ;;
    *)
        echo "Unknown account region: $ACCOUNTREGION"
        exit 1
        ;;
esac

echo
echo "Generating UUID for this installation..."
UUID=$(get_or_create_cluster_uuid)
echo "UUID: $UUID"
echo

sed \
    -e 's/__ACCOUNTREGION__/'"$ACCOUNTREGION"'/g' \
    -e 's/__CAPTURE__/'\"$CAPTURE\"'/g' \
    -e 's/__CLOUDPROVIDER__/'"$CLOUDPROVIDER"'/g' \
    -e 's/__CLOUDREGION__/'"$CLOUDREGION"'/g' \
    -e 's/__CLUSTER__/'"$CLUSTER"'/g' \
    -e 's/__EMAIL__/'"$EMAIL"'/g' \
    -e 's/__ENVIRONMENT__/'"$ENVIRONMENT"'/g' \
    -e 's/__GRPCENDPOINT__/'"$GRPCENDPOINT"'/g' \
    -e 's/__KAPPA_SAMPLE_RATIO__/'"$KAPPA_SAMPLE_RATIO"'/g' \
    -e 's/__KUBEMETA_VERSION__/'\"$KUBEMETA_VERSION\"'/g' \
    -e 's/__MAXGRPCPAYLOAD__/'"$MAX_PAYLOAD_SIZE_BYTES"'/g' \
    -e 's/__PLAN__/'"$PLAN"'/g' \
    -e 's/__TOKEN__/'"$TOKEN"'/g' \
    -e 's/__UUID__/'"$UUID"'/g' \
    kustomization-template.yml > kustomization.yml

# Set kubeconfig and context variables if provided
KUBECONF=""
KUBECONTEXT=""
[[ -n "$KUBECONFIG_FILE" ]] && KUBECONF="KUBECONFIG=\"$KUBECONFIG_FILE\""
[[ -n "$K8S_CONTEXT" ]] && KUBECONTEXT="--context=\"$K8S_CONTEXT\""

eval $KUBECONF kubectl apply -k . $KUBECONTEXT
