# openshift-podman

Running a Fedora 33 container in a OpenShift 4.3.21 namespace called 'jenkins'.


## Build image to run on OpenShift

Build image and push it into the registry in the jenkins namespace to a IS named podman:

    $ repo=default-route-openshift-image-registry.apps....
    $ podman build -t $repo/jenkins/podman:latest -f Containerfile.openshift
    $ podman push $repo/jenkins/podman:latest


Run the image with a Deployment Config like:

    apiVersion: apps.openshift.io/v1
    kind: DeploymentConfig
    metadata:
      name: podman
      namespace: jenkins
    spec:
      selector:
        app: podman
      replicas: 1
      template:
        metadata:
          labels:
            app: podman
        spec:
          containers:
            - name: podman
              image: image-registry.openshift-image-registry.svc:5000/jenkins/podman
              ports:
                - containerPort: 8000

The container will run the python web server, and thus allowing interaction via `oc rsh dc/podman` or the terminal.

## Probe content

Base information:

    $ id
    uid=1000590000(1000590000) gid=0(root) groups=0(root),1000590000

    $ uname -a
    Linux podman-1-f9k4h 4.18.0-147.8.1.el8_1.x86_64 #1 SMP Wed Feb 26 03:08:15 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux


Before setting subuid/subgid

````
$ podman info
ERRO[0000] cannot find mappings for user : No subuid ranges found for user "" in /etc/subuid 
host:
  arch: amd64
  buildahVersion: 1.15.0-dev
  cgroupVersion: v1
  ...
````

Set subuid/subgid:

````
$ echo "$(id -u):10000:65000" > /etc/subuid
$ echo "$(id -u):10000:65000" > /etc/subgid
````

Podman info:

````
$ podman info
host:
  arch: amd64
  buildahVersion: 1.15.0-dev
  cgroupVersion: v1
  conmon:
    package: conmon-2.0.18-0.6.dev.git50aeae4.fc33.x86_64
    path: /usr/bin/conmon
    version: 'conmon version 2.0.18-dev, commit: 51e91bbc42aaf0676bb4023fb86f00460bf7a0a2'
  cpus: 4
  distribution:
    distribution: fedora
    version: "33"
  eventLogger: file
  hostname: podman-1-f9k4h
  idMappings:
    gidmap:
    - container_id: 0
      host_id: 0
      size: 1
    uidmap:
    - container_id: 0
      host_id: 1000590000
      size: 1
  kernel: 4.18.0-147.8.1.el8_1.x86_64
  linkmode: dynamic
  memFree: 1967828992
  memTotal: 33726861312
  ociRuntime:
    name: runc
    package: runc-1.0.0-238.dev.git1b97c04.fc33.x86_64
    path: /usr/bin/runc
    version: |-
      runc version 1.0.0-rc10+dev
      commit: 1aa8febe14501045ff2a65ec0c01b0400245cb3c
      spec: 1.0.2-dev
  os: linux
  remoteSocket:
    path: /tmp/run-1000590000/podman/podman.sock
  rootless: true
  slirp4netns:
    executable: /usr/bin/slirp4netns
    package: slirp4netns-1.1.1-2.dev.git483e855.fc33.x86_64
    version: |-
      slirp4netns version 1.1.1+dev
      commit: 483e85547b22a6f8b9230e23b3e9815a41347771
      libslirp: 4.3.0
      SLIRP_CONFIG_VERSION_MAX: 3
  swapFree: 0
  swapTotal: 0
  uptime: 556h 49m 22.15s (Approximately 23.17 days)
registries:
  search:
  - registry.fedoraproject.org
  - registry.access.redhat.com
  - registry.centos.org
  - docker.io
store:
  configFile: /home/.config/containers/storage.conf
  containerStore:
    number: 0
    paused: 0
    running: 0
    stopped: 0
  graphDriverName: overlay
  graphOptions:
    overlay.mount_program:
      Executable: /usr/bin/fuse-overlayfs
      Package: fuse-overlayfs-1.0.0-3.dev.gitf3e4154.fc33.x86_64
      Version: |-
        fusermount3 version: 3.9.1
        fuse-overlayfs: version 1.0.0
        FUSE library version 3.9.1
        using FUSE kernel interface version 7.31
  graphRoot: /home/.local/share/containers/storage
  graphStatus:
    Backing Filesystem: overlayfs
    Native Overlay Diff: "false"
    Supports d_type: "true"
    Using metacopy: "false"
  imageStore:
    number: 0
  runRoot: /tmp/run-1000590000/containers
  volumePath: /home/.local/share/containers/storage/volumes
version:
  APIVersion: 1
  Built: 1591401600
  BuiltTime: Sat Jun  6 00:00:00 2020
  GitCommit: d857275901e8c1ea7515360631e5894018e17f30
  GoVersion: go1.14.3
  OsArch: linux/amd64
  Version: 2.0.0-dev
````

