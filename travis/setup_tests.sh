#!/bin/sh -xe

# This script starts docker and systemd (if el7)

if [ "${OS_TYPE}" -eq "ubuntu" ]; then
	travis/test_suite.sh

elif [ "${OS_VERSION}" -eq 6 ]; then

# Run tests in Container
# We use `--privileged` for cgroup compatability
    sudo docker run --privileged --rm=true \
         --volume /sys/fs/cgroup:/sys/fs/cgroup \
         --volume `pwd`:/setup:rw \
         centos:centos${OS_VERSION} \
         /bin/bash -c "bash -xe /setup/travis/test_inside_docker.sh ${OS_VERSION}"

elif [ "${OS_VERSION}" -eq 7 ]; then

    docker run --privileged --detach --tty --interactive --env "container=docker" \
           --volume /sys/fs/cgroup:/sys/fs/cgroup \
           --volume `pwd`:/setup:rw  \
           centos:centos${OS_VERSION} \
           /usr/sbin/init

    DOCKER_CONTAINER_ID=$(docker ps | grep centos | awk '{print $1}')
    docker logs $DOCKER_CONTAINER_ID
    docker exec --tty --interactive $DOCKER_CONTAINER_ID \
           /bin/bash -xec "bash -xe /setup/travis/test_inside_docker.sh ${OS_VERSION};
           echo -ne \"------\nEND CYRUS SCRIPTS TESTS\n\";"

    docker ps -a
    docker stop $DOCKER_CONTAINER_ID
    docker rm -v $DOCKER_CONTAINER_ID

fi
