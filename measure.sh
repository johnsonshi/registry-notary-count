#!/bin/bash

set -aeo pipefail

notary_signature_artifact_type="application/vnd.cncf.notary.v2.signature"

if [ -z "$1" ]; then
    echo "Measure the number of repos and tags within a registry that have signed artifacts."
    echo "An artifact is considered signed if it has an OCI Reference Artifact with artifactType '$notary_signature_artifact_type'."
    echo "[*] Usage: $0 <registry-url.com>, e.g. $0 abc.registry.io"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "[*] Docker CLI not found! Please ensure that it is installed. See https://docs.docker.com/get-docker/"
fi

if ! command -v oras &> /dev/null; then
    echo "[*] ORAS CLI not found! Please ensure that it is installed. See https://oras.land/cli/"
fi

# Remove http:// or https:// prefix.
registry_url=$(echo "$1" | sed -E "s/^https?:\/\///")

repos=$(curl -sSL "$registry_url/v2/_catalog" | jq -r '.repositories[]')

total_repos=0
repos_with_signatures=0

total_tags=0
tags_with_signatures=0

total_signatures=0

for repo in $repos; do
    total_repos=$(( total_repos + 1 ))

    is_signed_artifact_found_in_repo=0

    tags=$(curl -sSL "$registry_url/v2/$repo/tags/list" | jq -r '.tags[]')

    for tag in $tags; do
        total_tags=$(( total_tags + 1 ))

        n_signature_reference_artifacts=$(oras discover --artifact-type application/vnd.cncf.notary.v2.signature -o json "$registry_url/$repo:$tag" | jq -r '.references' | jq length)

        total_signatures=$((total_signatures+n_signature_reference_artifacts))

        if (( n_signature_reference_artifacts > 0 )); then
            tags_with_signatures=$(( tags_with_signatures + 1 ))
            is_signed_artifact_found_in_repo=1
        fi
    done

    if [ $is_signed_artifact_found_in_repo -eq 1 ]; then
        repos_with_signatures=$(( repos_with_signatures + 1 ))
    fi
done

echo "total_repos: $total_repos"
echo "repos_with_signatures: $repos_with_signatures"
echo "total_tags: $total_tags"
echo "tags_with_signatures: $tags_with_signatures"
echo "total_signatures: $total_signatures"
