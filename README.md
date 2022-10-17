# Registry Notary Count

Measure the number of repos and tags within a registry that have signed artifacts.

## Measurement Criteria

An artifact is considered signed if it has an OCI Reference Artifact with `artifactType` `application/vnd.cncf.notary.v2.signature`.

A repo is included in the count as long as a single artifact within the repo is signed.

A tag is included in the count as long as the artifact associated with the tag is signed.

Note: This may result in duplicate counts if a single artifact digest is associated with multiple tags. E.g. if a signed artifact is associated with 3 tags (`tag:v1`, `tag:v1-stable`, `tag:latest`), then the tag count counted 3 times.

## Requirements

* Docker CLI – https://docs.docker.com/get-docker/
  * Please ensure that the Docker CLI has registry read permissions and is authenticated. See https://docs.docker.com/engine/reference/commandline/login/
* ORAS CLI – https://oras.land/cli/
  * Please ensure that the ORAS CLI has registry read permissions and is authenticated. See https://oras.land/cli/0_authentication/
* A container registry that is compliant with the [Docker Registry HTTP API V2 protocol](https://docs.docker.com/registry/spec/api/).

## Running the Script

To count (1) the number of repos with signed artifacts and (2) the number of tags associated with a signed artifact:

`./measure.sh <registry-url.com>`

To count only the number of repos with signed artifacts:

`./measure.sh <registry-url.com> --early-exit`
