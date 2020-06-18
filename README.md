# openshift-podman

Running a Fedora 33 container in a OpenShift 4.3.21 namespace called 'jenkins'.

The problem ("there might not be enough IDs available in the namespace") seems to be due to the uidmap size provided by OpenShift.

The old issue https://github.com/containers/libpod/issues/1092 suggests that it has been working, with the CAP_SETUID/CAP_SETGID being the most problematic issue (on OpenShift). This is an issue from 2018 though.

My podman invocation never gets that far.

Maybe because I need to configure the securitycontext differently? Or because it is a newer version of OpenShift?
Or the new version of podman?





## Build image to run on OpenShift

Build image and push it into the registry in the jenkins namespace to a IS named podman:

    $ repo=default-route-openshift-image-registry.apps....
    $ podman build -t $repo/jenkins/podman:latest -f Containerfile.openshift
    $ podman push $repo/jenkins/podman:latest


Run the image with a Deployment Config like this:

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
          #serviceAccount: podman-sa
          containers:
            - name: podman
              image: image-registry.openshift-image-registry.svc:5000/jenkins/podman
              ports:
                - containerPort: 8000

The container will run the python web server, and thus allowing interaction via `oc rsh dc/podman` or the terminal.

## Explore in-container podman/buildah problems

Base information:

````
$ id
uid=1000590000(1000590000) gid=0(root) groups=0(root),1000590000

$ uname -a
Linux podman-1-f9k4h 4.18.0-147.8.1.el8_1.x86_64 #1 SMP Wed Feb 26 03:08:15 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux

$ cat /proc/sys/user/max_user_namespaces
128361

# I am aware of the missing setuid/setgid capabilities - see later
$ capsh --print
Current: = cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot+i
Bounding set =cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot
Ambient set =
Securebits: 00/0x0/1'b0
 secure-noroot: no (unlocked)
 secure-no-suid-fixup: no (unlocked)
 secure-keep-caps: no (unlocked)
 secure-no-ambient-raise: no (unlocked)
uid=1000590000(???)
gid=0(root)
groups=1000590000(???)

$ ls -l /usr/bin/newuidmap /usr/bin/newgidmap
-rwxr-xr-x. 1 root root 48736 May 14 12:32 /usr/bin/newgidmap
-rwxr-xr-x. 1 root root 44624 May 14 12:32 /usr/bin/newuidmap

$ getfattr -d -m '.*' /usr/bin/newuidmap /usr/bin/newgidmap
getfattr: Removing leading '/' from absolute path names
# file: usr/bin/newuidmap
security.selinux="system_u:object_r:container_file_t:s0:c19,c24"

# file: usr/bin/newgidmap
security.selinux="system_u:object_r:container_file_t:s0:c19,c24"
````

Set subuid/subgid (or run ./init.sh):

````
$ echo "${USER:-default}:x:$(id -u):0:${USER:-default} user:${HOME}:/sbin/nologin" >> /etc/passwd
$ echo "$(whoami):10000:65536" > /etc/subuid
$ echo "$(whoami):10000:65536" > /etc/subgid
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
  hostname: podman-1-plsbt
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
  memFree: 1986027520
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
  uptime: 558h 25m 50.2s (Approximately 23.25 days)
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

Try to pull an image:

````
$ podman pull registry.fedoraproject.org/fedora
Trying to pull registry.fedoraproject.org/fedora...
Getting image source signatures
Copying blob 1657ffead824 done  
Copying config eb7134a03c done  
Writing manifest to image destination
Storing signatures
  Error processing tar file(exit status 1): there might not be enough IDs available in the namespace (requested 0:22 for /run/utmp): lchown /run/utmp: invalid argument
Error: unable to pull registry.fedoraproject.org/fedora: Error committing the finished image: error adding layer with blob "sha256:1657ffead82459c68a65ceb4dc6f619b010b96d257f860d7db578ec2b06080e8": Error processing tar file(exit status 1): t
here might not be enough IDs available in the namespace (requested 0:22 for /run/utmp): lchown /run/utmp: invalid argument
````

Try to follow suggestion in https://github.com/containers/libpod/blob/master/troubleshooting.md#20-error-creating-libpod-runtime-there-might-not-be-enough-ids-available-in-the-namespace

````
$ podman unshare cat /proc/self/uid_map
         0 1000590000          1
$ podman system migrate
$ podman unshare cat /proc/self/uid_map
ERRO[0000] cannot find mappings for user : No subuid ranges found for user "" in /etc/subuid 
         0 1000590000          1
````

Same problem when pulling image.


Similar problems reported in in https://github.com/containers/libpod/issues/2542, https://github.com/containers/libpod/issues/4921, and many others.




## Custom SecurityContext

Many of the issues I have read through suggest that the problem may be caused by lack of CAP_SETUID/CAP_SETGID.

So try again with a more lenient security context:

Create Service Account 'podman-sa'

Create a SCC configuration (see podman-scc.yaml):

````
$ oc get scc/restricted -o yaml > podman-scc.yaml
# Edit file
#  edit name: podman-scc
#  edit priority: 10
#  remove group match: - system:authenticated
#  add user match: - system:serviceaccount:jenkins:podman-sa
#  remove requiredDropCapabilities lines: SETUID, SETGID
$ oc create -f podman-scc.yaml
````

Uncomment the SA line in the Deployment Config:

  serviceAccount: podman-sa

When the Pod restarts, it now runs with 'podman-scc' (see its metadata annotations in the YAML).

And indeed:

````
capsh --print
Current: = cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot+i
Bounding set =cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot
Ambient set =
Securebits: 00/0x0/1'b0
 secure-noroot: no (unlocked)
 secure-no-suid-fixup: no (unlocked)
 secure-keep-caps: no (unlocked)
 secure-no-ambient-raise: no (unlocked)
uid=1000590000(???)
gid=0(root)
groups=1000590000(???)
````

Unfortunately I see no difference in output from Podman after this.
