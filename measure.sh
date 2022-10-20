#!/bin/bash

set -aeo pipefail

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

###############################################################################
# Get All Repositories in a Container or Artifact Registry
###############################################################################

# Remove http:// or https:// prefix.
registry_url=$(echo "$1" | sed -E "s/^https?:\/\///")

repos=$(curl -sSL "$registry_url/v2/_catalog" | jq -r '.repositories[]')

###############################################################################
# Define Metrics for Notary V2 Signatures in a Container or Artifact Registry
###############################################################################

NOTARY_V2_SIGNATURE_ARTIFACT_TYPE="application/vnd.cncf.notary.v2.signature"

total_repos=0
repos_with_signatures=0
skipped_repos_due_to_error=0

total_tags_across_all_repos=0
tags_across_all_repos_with_signatures=0
skipped_tags_due_to_error=0

total_signatures_across_all_repos_and_all_tags=0

###############################################################################
# Output Filename (.csv) for Notary V2 Signature Metrics
###############################################################################

# get current date
today=$(date --utc --iso-8601=date)

NOTARY_V2_SIGNATURE_METRICS_REPO_BREAKDOWN_FILE="notary-v2-signature-metrics-repo-breakdown-$today.csv"

# Write a new file (overwriting the previous one if it exists).
# After that, append rows to the output file.
echo "registry_url,repository,found_at_least_one_signature_for_any_tagged_artifact" > "$NOTARY_V2_SIGNATURE_METRICS_REPO_BREAKDOWN_FILE"
for repo in $repos; do
    total_repos=$(( total_repos + 1 ))

    is_signed_artifact_found_in_repo=0

    # DEBUG
    repo="oss/etcd-io/etcd"

    ###############################################################################
    # Get All Tags in a Repo and Iterate Through Each One
    ###############################################################################

    if ! tags=$(curl -sSL "$registry_url/v2/$repo/tags/list" | jq -r '.tags[]'); then
        skipped_repos_due_to_error=$(( skipped_repos_due_to_error + 1 ))
        logger --stderr "[!] Unable to get tags for repo '$repo'. Skipping..."
        continue
    fi

    # Reverse iterate through tags because later tags (such as v9) are more likely to be associated
    # with a signed artifact than earlier tags (such as v8).
    for tag in $(echo "$tags" | tac); do
        total_tags_across_all_repos=$(( total_tags_across_all_repos + 1 ))

        ###############################################################################
        # Try to Discover Notary V2 Signature References for the Tagged Artifact
        ###############################################################################

        # Check if the tag's artifact has an associated signature.
        # If so, then the tag's artifact is considered signed.
        # Also check the exit code of the piped command because `oras discover` has a tendency to randomly fail with a server error.
        if ! n_signature_reference_artifacts=$(oras discover --artifact-type "$NOTARY_V2_SIGNATURE_ARTIFACT_TYPE" -o json "$registry_url/$repo:$tag" | jq -r '.referrers' | jq length); then
            skipped_tags_due_to_error=$(( skipped_tags_due_to_error + 1 ))
            logger --stderr "[!] Unable to get reference artifacts for repo '$repo' and tag '$tag'. Skipping..."
            continue
        fi

        total_signatures_across_all_repos_and_all_tags=$(( total_signatures_across_all_repos_and_all_tags + n_signature_reference_artifacts ))

        if (( n_signature_reference_artifacts > 0 )); then
            tags_across_all_repos_with_signatures=$(( tags_across_all_repos_with_signatures + 1 ))
            is_signed_artifact_found_in_repo=1
            if [ "$early_exit" = "true" ]; then
                break
            fi
        fi
    done

    if [ $is_signed_artifact_found_in_repo -eq 1 ]; then
        repos_with_signatures=$(( repos_with_signatures + 1 ))
    fi

    echo "$registry_url,$repo,$is_signed_artifact_found_in_repo" >> "$NOTARY_V2_SIGNATURE_METRICS_REPO_BREAKDOWN_FILE"

    # DEBUG
    break
done

###############################################################################
# Summary of Notary V2 Signature Metrics in a Container or Artifact Registry
###############################################################################

NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE="notary-v2-signature-metrics-summary-$today.csv"

# Write a new file (overwriting the previous one if it exists).
# After that, append rows to the output file.
echo "property,value" > "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
echo "registry_url,$registry_url"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
echo "total_repos,$total_repos"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
echo "repos_with_signatures,$repos_with_signatures"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
echo "skipped_repos_due_to_error,$skipped_repos_due_to_error"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
if [ "$early_exit" = "false" ]; then
    echo "total_tags_across_all_repos,$total_tags_across_all_repos"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
    echo "tags_across_all_repos_with_signatures,$tags_across_all_repos_with_signatures"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
    echo "skipped_tags_due_to_error,$skipped_tags_due_to_error"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
    echo "total_signatures_across_all_repos_and_all_tags,$total_signatures_across_all_repos_and_all_tags"  >> "$NOTARY_V2_SIGNATURE_METRICS_SUMMARY_FILE"
fi
