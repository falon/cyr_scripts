#!/bin/sh -xe

# This script starts docker and systemd (if el7)

if [ "${OS_TYPE}" = "ubuntu" ]; then
	travis/test_suite.sh

elif [ "${OS_VERSION}" -eq "6" ]; then

# Run tests in Container
# We use `--privileged` for cgroup compatability
    sudo docker run --privileged --rm=true \
         --volume /sys/fs/cgroup:/sys/fs/cgroup \
         --volume `pwd`:/setup:rw \
         centos:centos${OS_VERSION} \
         /bin/bash -c "bash -xe /setup/travis/test_inside_docker.sh ${OS_VERSION}"

elif [ "${OS_VERSION}" -eq "7" ]; then

    sudo docker run --privileged --detach --tty --interactive --env "container=docker" \
           --volume /sys/fs/cgroup:/sys/fs/cgroup \
           --volume `pwd`:/setup:rw  \
           centos:centos${OS_VERSION} \
           /usr/sbin/init

    export DOCKER_CONTAINER_ID=$(sudo docker ps | grep centos | awk '{print $1}')
    sudo docker logs $DOCKER_CONTAINER_ID
    sudo docker exec --tty --interactive $DOCKER_CONTAINER_ID \
           /bin/bash -xc "bash -x /setup/travis/test_inside_docker.sh ${OS_TYPE} ${OS_VERSION};
    	   test_exit=$?
           echo -ne \"------\nEND CYRUS SCRIPTS TESTS\n\";"

    sudo docker ps -a
    sudo docker stop $DOCKER_CONTAINER_ID
    sudo docker rm -v $DOCKER_CONTAINER_ID

fi
exit $test_exit
