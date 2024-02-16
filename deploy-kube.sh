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
CLUSTER=your_cluster_name
#
# Don't change the below values unless you know for sure it's what you want.
#
CAPTURE='en*|veth.*|eth*'
KUBEMETA_VERSION=sha-6589ba8
MAX_PAYLOAD_SIZE_MB=8
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

sed \
    -e 's/__ACCOUNTREGION__/'"$ACCOUNTREGION"'/g' \
    -e 's/__CAPTURE__/'\"$CAPTURE\"'/g' \
    -e 's/__CLOUDPROVIDER__/'"$CLOUDPROVIDER"'/g' \
    -e 's/__CLUSTER__/'"$CLUSTER"'/g' \
    -e 's/__EMAIL__/'"$EMAIL"'/g' \
    -e 's/__GRPCENDPOINT__/'"$GRPCENDPOINT"'/g' \
    -e 's/__KAPPA_SAMPLE_RATIO__/'"$KAPPA_SAMPLE_RATIO"'/g' \
    -e 's/__KUBEMETA_VERSION__/'\"$KUBEMETA_VERSION\"'/g' \
    -e 's/__MAXGRPCPAYLOAD__/'"$MAX_PAYLOAD_SIZE_BYTES"'/g' \
    -e 's/__PLAN__/'"$PLAN"'/g' \
    -e 's/__TOKEN__/'"$TOKEN"'/g' \
    kustomization-template.yml > kustomization.yml

# Set kubeconfig and context variables if provided
KUBECONF=""
KUBECONTEXT=""
[[ -n "$KUBECONFIG_FILE" ]] && KUBECONF="KUBECONFIG=\"$KUBECONFIG_FILE\""
[[ -n "$K8S_CONTEXT" ]] && KUBECONTEXT="--context=\"$K8S_CONTEXT\""

eval $KUBECONF kubectl apply -k . $KUBECONTEXT
