#!/bin/bash
echo "${USER:-default}:x:$(id -u):0:${USER:-default} user:${HOME}:/sbin/nologin" >> /etc/passwd
echo "$(whoami):10000:65536" > /etc/subuid
echo "$(whoami):10000:65536" > /etc/subgid
