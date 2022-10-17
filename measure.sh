#!/bin/bash

set -aeo pipefail

notary_signature_artifact_type="application/vnd.cncf.notary.v2.signature"

if [ -z "$1" ]; then
    echo "Measure the number of repos and tags within a registry that have signed artifacts."
    echo "An artifact is considered signed if it has an OCI Reference Artifact with artifactType '$notary_signature_artifact_type'."
    echo "Supply an optional flag [--early-exit] to exit early each time the first signed artifact"
    echo "is found within each repo (if you want to only measure the number of repos with signed artifacts)."
    echo "[*] Usage: $0 <registry-url.com> [--early-exit], e.g. $0 abc.registry.io [--early-exit]"
    exit 1
fi

if [ "$2" == "--early-exit" ]; then
    early_exit=true
else
    early_exit=false
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
skipped_repos_due_to_error=0

total_tags=0
tags_with_signatures=0
skipped_tags_due_to_error=0

total_signatures=0

for repo in $repos; do
    total_repos=$(( total_repos + 1 ))

    is_signed_artifact_found_in_repo=0

    echo "[*] repo: $repo"
    if ! tags=$(curl -sSL "$registry_url/v2/$repo/tags/list" | jq -r '.tags[]'); then
        skipped_repos_due_to_error=$(( skipped_repos_due_to_error + 1 ))
        echo "[!] Unable to get tags for repo '$repo'. Skipping..."
        continue
    fi

    # Reverse iterate through tags because later tags (such as v9) are more likely to be associated
    # with a signed artifact than earlier tags (such as v8).
    for tag in $(echo "$tags" | tac); do
        total_tags=$(( total_tags + 1 ))

        # Check if the tag's artifact has an associated signature.
        # If so, then the tag's artifact is considered signed.
        # Also check the exit code of the piped command because `oras discover` has a tendency to randomly fail with a server error.
        if ! n_signature_reference_artifacts=$(oras discover --artifact-type application/vnd.cncf.notary.v2.signature -o json "$registry_url/$repo:$tag" | jq -r '.references' | jq length); then
            skipped_tags_due_to_error=$(( skipped_tags_due_to_error + 1 ))
            echo "[!] Unable to get reference artifacts for repo '$repo' and tag '$tag'. Skipping..."
            continue
        fi

        total_signatures=$(( total_signatures + n_signature_reference_artifacts ))

        if (( n_signature_reference_artifacts > 0 )); then
            tags_with_signatures=$(( tags_with_signatures + 1 ))
            is_signed_artifact_found_in_repo=1
            if [ "$early_exit" = "true" ]; then
                break
            fi
        fi
    done

    if [ $is_signed_artifact_found_in_repo -eq 1 ]; then
        repos_with_signatures=$(( repos_with_signatures + 1 ))
    fi
done

echo "***************************************"
echo "                Summary                "
echo "***************************************"
echo "[*] registry: $registry_url"
echo "***************************************"
echo "[*] total_repos: $total_repos"
echo "[*] repos_with_signatures: $repos_with_signatures"
echo "[*] skipped_repos_due_to_error: $skipped_repos_due_to_error"
echo "***************************************"
if [ "$early_exit" = "false" ]; then
    echo "[*] total_tags: $total_tags"
    echo "[*] tags_with_signatures: $tags_with_signatures"
    echo "[*] skipped_tags_due_to_error: $skipped_tags_due_to_error"
    echo "***************************************"
    echo "[*] total_signatures from 'oras discover --artifact-type application/vnd.cncf.notary.v2.signature -o json $registry_url/<repo>:<tag>': $total_signatures"
    echo "***************************************"
fi
