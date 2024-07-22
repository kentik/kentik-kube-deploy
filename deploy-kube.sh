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
# You must set these values as appropriate for your account and device
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
KUBEMETA_VERSION=sha-63a15e9
MAX_PAYLOAD_SIZE_MB=256
KAPPA_SAMPLE_RATIO=1:4

# ##############################################################################
#
#               OPTIONAL RAM / CPU resource configuration
#
#     --> UNCOMMENT ANY OF THE BELOW VALUES TO HAVE THOSE RESOURCES SET <--
#
#   'request' values are the minimum resources that the pod will be guaranteed
#   'limit' values are the maximum resources that the pod will be allowed to use
#
#   cpu is measured in millicores (m), memory is measured in bytes (e.g., 100Mi)
#
# KAPPA_AGG_CPU_REQUEST=5m        # default: 5m
# KAPPA_AGG_CPU_LIMIT=50m         # default: 50m
# KAPPA_AGG_MEM_REQUEST=100Mi     # default: 100Mi
# KAPPA_AGG_MEM_LIMIT=1Gi         # default: 1Gi

# KAPPA_AGENT_CPU_REQUEST=5m      # default: 5m
# KAPPA_AGENT_CPU_LIMIT=50m       # default: 50m
# KAPPA_AGENT_MEM_REQUEST=150Mi   # default: 150Mi
# KAPPA_AGENT_MEM_LIMIT=2Gi       # default: 2Gi

# KUBEINFO_CPU_REQUEST=5m         # default: 5m
# KUBEINFO_CPU_LIMIT=50m          # default: 50m
# KUBEINFO_MEM_REQUEST=100Mi      # default: 100Mi
# KUBEINFO_MEM_LIMIT=1Gi          # default: 1Gi

# KUBEMETA_CPU_REQUEST=5m         # default: 5m
# KUBEMETA_CPU_LIMIT=50m          # default: 50m
# KUBEMETA_MEM_REQUEST=100Mi      # default: 100Mi
# KUBEMETA_MEM_LIMIT=1Gi          # default: 1Gi

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
    kubectl create configmap "$config_map_name" --from-literal="$uuid_key"="$new_uuid" &>/dev/null || \
      kubectl patch configmap "$config_map_name" --type=merge -p "{\"data\":{\"$uuid_key\":\"$new_uuid\"}}" &>/dev/null

    # Release the lock
    kubectl delete configmap "$lock_name" &>/dev/null

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
        kubectl delete configmap --uid="$lock_uid" &>/dev/null

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

# if any of the cpu/mem resource values are set, generate patches for them
generate_patches() {
    local patches=""
    local targets=("kappa-agent" "kappa-agg" "kubeinfo" "kubemeta-deployment")
    local config_name=("KAPPA_AGENT" "KAPPA_AGG" "KUBEINFO" "KUBEMETA")
    local kinds=("DaemonSet" "Deployment" "Deployment" "Deployment")

    for i in "${!targets[@]}"; do
        local target="${targets[$i]}"
        local kind="${kinds[$i]}"

        local cpu_request="${config_name[$i]}_CPU_REQUEST"
        local cpu_limit="${config_name[$i]}_CPU_LIMIT"
        local mem_request="${config_name[$i]}_MEM_REQUEST"
        local mem_limit="${config_name[$i]}_MEM_LIMIT"

        # are any of the resource values set?
        if [[ -n "${!cpu_request}" || -n "${!cpu_limit}" || -n "${!mem_request}" || -n "${!mem_limit}" ]]; then
            patches+="  - target:\n      kind: $kind\n      name: $target\n    patch: |-\n"
            patches+="      - op: add\n        path: /spec/template/spec/containers/0/resources\n        value:\n"

            # add requests if either CPU or memory request is set
            if [[ -n "${!cpu_request}" || -n "${!mem_request}" ]]; then
                patches+="          requests:\n"
                [[ -n "${!cpu_request}" ]] && patches+="            cpu: ${!cpu_request}\n"
                [[ -n "${!mem_request}" ]] && patches+="            memory: ${!mem_request}\n"
            fi

            # add limits if either CPU or memory limit is set
            if [[ -n "${!cpu_limit}" || -n "${!mem_limit}" ]]; then
                patches+="          limits:\n"
                [[ -n "${!cpu_limit}" ]] && patches+="            cpu: ${!cpu_limit}\n"
                [[ -n "${!mem_limit}" ]] && patches+="            memory: ${!mem_limit}\n"
            fi
        fi
    done

    echo "$patches"
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
MAXGRPCPAYLOAD=$((MAX_PAYLOAD_SIZE_MB * 1024 * 1024))

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
echo "Kappa Agent CPU Request/Limit: ${KAPPA_AGENT_CPU_REQUEST:-"(unset)"}/${KAPPA_AGENT_CPU_LIMIT:-"(unset)"}"
echo "Kappa Agent Mem Request/Limit: ${KAPPA_AGENT_MEM_REQUEST:-"(unset)"}/${KAPPA_AGENT_MEM_LIMIT:-"(unset)"}"
echo "Kappa Agg CPU Request/Limit:   ${KAPPA_AGG_CPU_REQUEST:-"(unset)"}/${KAPPA_AGG_CPU_LIMIT:-"(unset)"}"
echo "Kappa Agg Mem Request/Limit:   ${KAPPA_AGG_MEM_REQUEST:-"(unset)"}/${KAPPA_AGG_MEM_LIMIT:-"(unset)"}"
echo "Kubeinfo CPU Request/Limit:    ${KUBEINFO_CPU_REQUEST:-"(unset)"}/${KUBEINFO_CPU_LIMIT:-"(unset)"}"
echo "Kubeinfo Mem Request/Limit:    ${KUBEINFO_MEM_REQUEST:-"(unset)"}/${KUBEINFO_MEM_LIMIT:-"(unset)"}"
echo "Kubemeta CPU Request/Limit:    ${KUBEMETA_CPU_REQUEST:-"(unset)"}/${KUBEMETA_CPU_LIMIT:-"(unset)"}"
echo "Kubemeta Mem Request/Limit:    ${KUBEMETA_MEM_REQUEST:-"(unset)"}/${KUBEMETA_MEM_LIMIT:-"(unset)"}"
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

UUID=$(get_or_create_cluster_uuid)
echo
echo "UUID: $UUID"
echo

vars=(
    "ACCOUNTREGION"
    "CAPTURE"
    "CLOUDPROVIDER"
    "CLOUDREGION"
    "CLUSTER"
    "EMAIL"
    "ENVIRONMENT"
    "GRPCENDPOINT"
    "KAPPA_SAMPLE_RATIO"
    "KUBEMETA_VERSION"
    "MAXGRPCPAYLOAD"
    "PLAN"
    "TOKEN"
    "UUID"
)

patches=$(generate_patches)

# Construct the sed command
sed_cmd="sed"
for var in "${vars[@]}"; do
    sed_cmd+=" -e 's/__${var}__/${!var}/g'"
done
sed_cmd+=" kustomization-template.yml > kustomization.yml"

# Execute the sed command
eval $sed_cmd

# Add the patches, if any
if [[ -n "$patches" ]]; then
    echo -e "patches:" >> kustomization.yml
    echo -e "$patches" >> kustomization.yml
fi

# Set kubeconfig and context variables if provided
KUBECONF=""
KUBECONTEXT=""
[[ -n "$KUBECONFIG_FILE" ]] && KUBECONF="KUBECONFIG=\"$KUBECONFIG_FILE\""
[[ -n "$K8S_CONTEXT" ]] && KUBECONTEXT="--context=\"$K8S_CONTEXT\""

eval $KUBECONF kubectl apply -k . $KUBECONTEXT
