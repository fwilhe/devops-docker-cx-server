#!/bin/bash
set -o errexit
set -o nounset

if [[ "$#" -ne 1 ]]; then
	echo "Usage: $(basename "$0") (latest || v*)"
	exit 1
fi

VERSION=$1

if [[ ${VERSION} != latest ]] && [[ ${VERSION} != "v"* ]]; then
    echo "Error: Version must be 'latest' or 'v*'"
    exit 1
fi

build_image() {
    local TAG=$1
    local DIR=$2

    if [ "${VERSION}" = latest ]; then
        # Create a backup of the image to allow rollback in case of failure
        docker pull "${TAG}":latest
        docker tag "${TAG}":latest "${TAG}":backup-of-latest
    fi

    # Build the Release Candidate
    docker build "${DIR}" --tag "${TAG}":"${VERSION}"-RC
}

smoke_test() {
    # Test Jenkins master image
    docker run --name cx-jenkins-master-test --detach --publish 8080:8080 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ppiper/jenkins-master:"${VERSION}"-RC
    # Wait up to 5 minutes for Jenkins to be up and fail if it does not return 200 after this time
    docker exec cx-jenkins-master-test timeout 300 bash -c "until curl --fail http://localhost:8080/api/json; do sleep 5; done"
    # Check for 'SEVERE' messages in Jenkins log (usually caused by a plugin or configuration issues)
    # Note: This will exit with code 1 if a finding of SEVERE exists
    docker logs cx-jenkins-master-test 2> >(grep --quiet SEVERE)
}

push_image() {
    local TAG=$1

    docker tag "${TAG}":"${VERSION}"-RC "${TAG}":"${VERSION}"

    if [ "${VERSION}" = latest ]; then
        docker push "${TAG}":backup-of-latest
    fi

    docker push "${TAG}":"${VERSION}"
}

build_image ppiper/jenkins-master jenkins-master
build_image ppiper/jenkins-agent jenkins-agent
build_image ppiper/jenkins-agent-k8s jenkins-agent-k8s
build_image ppiper/cx-server-companion cx-server-companion
build_image ppiper/action-runtime project-piper-action-runtime

smoke_test

if [[ ${GITHUB_REF##*/} != master ]] && [[ ${GITHUB_REF##*/} != "v"* ]]; then
    echo "Not pushing on ref ${GITHUB_REF}"
    exit 0
fi

push_image ppiper/jenkins-master
push_image ppiper/jenkins-agent
push_image ppiper/jenkins-agent-k8s
push_image ppiper/cx-server-companion
push_image ppiper/action-runtime
