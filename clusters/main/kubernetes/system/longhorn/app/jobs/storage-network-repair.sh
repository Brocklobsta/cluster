#!/bin/sh
set -eu

longhorn_namespace="longhorn-system"
multus_namespace="kube-system"
expected_network="longhorn-system/storage-network"
expected_network_namespace="longhorn-system"
expected_network_name="storage-network"
expected_interface="lhnet1"
instance_manager_selector="longhorn.io/component=instance-manager,longhorn.io/data-engine=v1,longhorn.io/managed-by=longhorn-manager"
multus_selector="app.kubernetes.io/instance=multus-cni,app.kubernetes.io/name=multus-cni"
service_account_dir="${SERVICE_ACCOUNT_DIR:-/var/run/secrets/kubernetes.io/serviceaccount}"

pod_is_candidate() {
  printf '%s' "$1" | jq -e \
    --arg network_namespace "${expected_network_namespace}" \
    --arg network_name "${expected_network_name}" \
    --arg interface "${expected_interface}" '
      (.metadata.deletionTimestamp == null) and
      (.status.phase == "Running") and
      (any(.status.conditions[]?; .type == "Ready" and .status == "True")) and
      ((now - (.metadata.creationTimestamp | fromdateiso8601)) >= 300) and
      ((.metadata.annotations["k8s.v1.cni.cncf.io/networks"] // "[]" | fromjson) |
        any(.[];
          .namespace == $network_namespace and
          .name == $network_name and
          .interface == $interface
        ))
    ' >/dev/null
}

pod_has_storage_network() {
  printf '%s' "$1" | jq -e \
    --arg network "${expected_network}" \
    --arg interface "${expected_interface}" '
      ((.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] // "[]" | fromjson) |
        any(.[]; .name == $network and .interface == $interface))
    ' >/dev/null
}

multus_is_stable() {
  node="$1"
  multus_json=$(kubectl --namespace "${multus_namespace}" get pods \
    --selector "${multus_selector}" --field-selector "spec.nodeName=${node}" \
    --output json) || return 2
  printf '%s' "${multus_json}" | jq -e '
    any(.items[];
      .metadata.deletionTimestamp == null and
      .status.phase == "Running" and
      (([.status.containerStatuses[]?] | length) > 0) and
      all(.status.containerStatuses[]?; .ready == true) and
      (([.status.initContainerStatuses[]?] | length) > 0) and
      all(.status.initContainerStatuses[]?;
        .state.terminated.exitCode == 0) and
      (any(.status.conditions[]?;
        .type == "Ready" and
        .status == "True" and
        ((now - (.lastTransitionTime | fromdateiso8601)) >= 120)
      ))
    )
  ' >/dev/null
}

volumes_are_healthy() {
  volumes_json=$(kubectl --namespace "${longhorn_namespace}" get volumes.longhorn.io --output json) || return 2
  printf '%s' "${volumes_json}" | jq -e '
    all(.items[];
      (.status.state == "detached") or
      (.status.state == "attached" and .status.robustness == "healthy")
    )
  ' >/dev/null
}

setting_json=$(kubectl --namespace "${longhorn_namespace}" get settings.longhorn.io storage-network --output json)
printf '%s' "${setting_json}" | jq -e \
  --arg network "${expected_network}" \
  '.value == $network and .status.applied == true' >/dev/null || {
    echo "Longhorn storage-network setting is not applied as ${expected_network}" >&2
    exit 1
  }
kubectl --namespace "${longhorn_namespace}" get network-attachment-definition storage-network >/dev/null

for resource in $(kubectl --namespace "${longhorn_namespace}" get pods \
  --selector "${instance_manager_selector}" --output name); do
  pod="${resource#pod/}"
  candidate_json=$(kubectl --namespace "${longhorn_namespace}" get pod "${pod}" --output json)

  if pod_is_candidate "${candidate_json}"; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && continue
    echo "Unable to parse candidate state for ${pod}" >&2
    exit "${rc}"
  fi

  if pod_has_storage_network "${candidate_json}"; then
    continue
  else
    rc=$?
    if [ "${rc}" -ne 1 ]; then
      echo "Unable to parse network-status for ${pod}" >&2
      exit "${rc}"
    fi
  fi

  node=$(printf '%s' "${candidate_json}" | jq -er '.spec.nodeName')
  owner=$(printf '%s' "${candidate_json}" | jq -er '
    .metadata.ownerReferences[] |
    select(.controller == true and .kind == "InstanceManager") |
    .name
  ')
  instance_manager_json=$(kubectl --namespace "${longhorn_namespace}" get \
    instancemanagers.longhorn.io "${owner}" --output json)
  printf '%s' "${instance_manager_json}" | jq -e --arg node "${node}" '
    .spec.nodeID == $node and .status.currentState == "running"
  ' >/dev/null || {
    echo "Skipping ${pod}: owning InstanceManager is not running on ${node}"
    continue
  }

  if multus_is_stable "${node}"; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && echo "Skipping ${pod}: Multus is not stably Ready on ${node}" && continue
    exit "${rc}"
  fi
  if volumes_are_healthy; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && echo "Skipping ${pod}: Longhorn volumes are not in safe states" && continue
    exit "${rc}"
  fi

  echo "Safety sample passed for ${pod}; rechecking in 30 seconds"
  sleep 30

  final_json=$(kubectl --namespace "${longhorn_namespace}" get pod "${pod}" --output json)
  old_uid=$(printf '%s' "${candidate_json}" | jq -er '.metadata.uid')
  final_uid=$(printf '%s' "${final_json}" | jq -er '.metadata.uid')
  if [ "${final_uid}" != "${old_uid}" ]; then
    echo "Skipping ${pod}: candidate UID changed before deletion"
    continue
  fi
  if pod_is_candidate "${final_json}"; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && echo "Skipping ${pod}: candidate is no longer eligible" && continue
    exit "${rc}"
  fi
  if pod_has_storage_network "${final_json}"; then
    echo "Skipping ${pod}: storage network appeared before deletion"
    continue
  else
    rc=$?
    if [ "${rc}" -ne 1 ]; then
      echo "Unable to parse final network-status for ${pod}" >&2
      exit "${rc}"
    fi
  fi
  final_setting_json=$(kubectl --namespace "${longhorn_namespace}" get \
    settings.longhorn.io storage-network --output json)
  printf '%s' "${final_setting_json}" | jq -e --arg network "${expected_network}" '
    .value == $network and .status.applied == true
  ' >/dev/null || {
    echo "Storage-network setting changed before deletion" >&2
    exit 1
  }
  kubectl --namespace "${longhorn_namespace}" get \
    network-attachment-definition storage-network >/dev/null
  final_instance_manager_json=$(kubectl --namespace "${longhorn_namespace}" get \
    instancemanagers.longhorn.io "${owner}" --output json)
  if ! printf '%s' "${final_instance_manager_json}" | jq -e --arg node "${node}" '
    .spec.nodeID == $node and .status.currentState == "running"
  ' >/dev/null; then
    echo "Skipping ${pod}: owning InstanceManager changed before deletion"
    continue
  fi
  if multus_is_stable "${node}"; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && echo "Skipping ${pod}: Multus readiness changed before deletion" && continue
    exit "${rc}"
  fi
  if volumes_are_healthy; then
    :
  else
    rc=$?
    [ "${rc}" -eq 1 ] && echo "Skipping ${pod}: volume health changed before deletion" && continue
    exit "${rc}"
  fi

  delete_body=$(jq -cn --arg uid "${old_uid}" '
    {apiVersion: "v1", kind: "DeleteOptions", preconditions: {uid: $uid}}
  ')
  token=$(cat "${service_account_dir}/token")
  api_server="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS:-443}"
  response_file="/tmp/delete-response.json"
  http_code=$(curl --silent --show-error \
    --cacert "${service_account_dir}/ca.crt" \
    --oauth2-bearer "${token}" \
    --header "Content-Type: application/json" \
    --request DELETE \
    --data "${delete_body}" \
    --output "${response_file}" \
    --write-out '%{http_code}' \
    "${api_server}/api/v1/namespaces/${longhorn_namespace}/pods/${pod}")
  case "${http_code}" in
    200|202)
      echo "Recreating ${pod} on ${node}: requested ${expected_network} is missing"
      ;;
    409)
      echo "Skipping ${pod}: UID precondition rejected a stale candidate"
      exit 0
      ;;
    *)
      echo "Pod deletion failed with HTTP ${http_code}:" >&2
      cat "${response_file}" >&2
      exit 1
      ;;
  esac

  for attempt in $(seq 1 60); do
    sleep 5
    replacement_json=$(kubectl --namespace "${longhorn_namespace}" get pod "${pod}" \
      --ignore-not-found --output json)
    [ -n "${replacement_json}" ] || continue
    new_uid=$(printf '%s' "${replacement_json}" | jq -er '.metadata.uid')
    [ "${new_uid}" != "${old_uid}" ] || continue

    if pod_has_storage_network "${replacement_json}" && \
      printf '%s' "${replacement_json}" | jq -e '
        any(.status.conditions[]?; .type == "Ready" and .status == "True")
      ' >/dev/null; then
      echo "${pod} is Ready with ${expected_network}"
      # Only repair one instance-manager per run to avoid simultaneous disruption.
      exit 0
    fi
    echo "Waiting for replacement ${pod} (${attempt}/60)"
  done

  echo "Replacement ${pod} did not become Ready with ${expected_network}" >&2
  exit 1
done

echo "All Longhorn instance-managers use ${expected_network}"
