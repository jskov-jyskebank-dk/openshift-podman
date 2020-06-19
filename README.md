# openshift-podman

We are trying to make it possible for the developer to provide a Dockerfile to be executed in a container on OpenShift. Output is an image they can deploy in their own namespace on OpenShift.

We want this to be done safely, so no one - through malice or accident - can wreck the OpenShift platform.

For this, we hope to get podman to run in its rootless mode.


This repository documents the problems found with this approach - and hopefully the path to a solution.
An issue has been filed on the issue, see https://github.com/containers/libpod/issues/6667

## Current Status

Running a Fedora 33 container in an OpenShift 4.3.21 namespace called 'jenkins'.

The problem ("there might not be enough IDs available in the namespace") seems to be due to the uidmap size provided by OpenShift.

The old issue https://github.com/containers/libpod/issues/1092 suggests that it has been working, with the CAP_SETUID/CAP_SETGID being the most problematic issue (on OpenShift). This is an issue from 2018 though.

My podman invocation never gets that far.

Maybe because I need to configure the securitycontext differently? Or because it is a newer version of OpenShift?
Or the new version of podman?

Daniel Walsh has provided some hints, that I will try to explore (see bottom of page).

Pulling images: *WORKS*

Running commands in an image: exploring...


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

# newXidmap files
# I am not sure of the selinux state - it is different from the output in issue #4921.
# So I have also tried an image with chmod u+s on these files, and it made no difference

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





## Try with SCC cloned from privileged

Create podman-priv like podman-scc, but base it on the 'privileged' SCC.

It does fail differently:

````
$ id
uid=0(root) gid=0(root) groups=0(root)

$ podman info             
Error: 'overlay' is not supported over overlayfs, a mount_program is required: backing file system is unsupported for this graph driver
````

So there is something to dig into.

I might do that later on, but a privileged container is not what we are looking for - we want to be able to let developers have control of a container to build images in it.

In a pinch it might be possible to use, if the container can be started with a bigger userid range. If that is indeed the root cause of my troubles.
If so, we'd have to run in a controlled image, that will drop all the dangerous capabilities, before passing control over to checked out user code.
Pretty much like S2I, I would imagine.

## Explore approach podman/buildah images

As per https://github.com/containers/libpod/issues/6667#issuecomment-646056867

Repository https://github.com/containers/libpod/tree/master/contrib/podmanimage

### Workstation

Followed `Sample Usage` instructions in https://github.com/containers/libpod/tree/master/contrib/podmanimage on *workstation* without problems.


Step 1: Start `podmanctr`:

````
$ podman pull docker://quay.io/podman/stable:latest

$ podman run --privileged stable podman version
Version:            1.9.1
RemoteAPI Version:  1  
Go Version:         go1.14.2                  
OS/Arch:            linux/amd64

$ podman run --detach --name=podmanctr --net=host --security-opt label=disable --security-opt seccomp=unconfined --device /dev/fuse:rw -v /opt/data/mycontainer:/var/lib/containers:Z --privileged  stable sh  -c 'while true ;do sleep 10
0000 ; done'                             
35f34d754cccd3c4486295df5bcc67808503b484eb62f310544fa56cea8d114c
$ podman exec -it podmanctr /bin/sh
````

Step 2: Inside `podmanctr`:

````
sh-5.0# podman pull alpine
Trying to pull registry.fedoraproject.org/alpine...
  invalid status code from registry 503 (Service Unavailable)
Trying to pull registry.access.redhat.com/alpine...
  name unknown: Repo not found
Trying to pull registry.centos.org/alpine...
  manifest unknown: manifest unknown
Trying to pull docker.io/library/alpine...
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e
sh-5.0# podman images
REPOSITORY                 TAG      IMAGE ID       CREATED       SIZE
docker.io/library/alpine   latest   a24bb4013296   2 weeks ago   5.85 MB
````

All is good.

### OpenShift

Two paths to take.

#### Start podmanctr like on workstation

This from my own plain Fedora 33 container, with SCC restricted+CAP_SETUID+CAP_SETGID.

````
$ podman pull docker://quay.io/podman/stable:latest
Trying to pull docker://quay.io/podman/stable:latest...
Getting image source signatures
Copying blob de816b60fe1b done  
Copying blob 608bed8e5c80 done  
Copying blob e9bc339e0a06 done  
Copying blob 910e4eb8e476 done  
Copying blob 03c837e31708 done  
Copying config baae4c0193 done  
Writing manifest to image destination
Storing signatures
  Error processing tar file(exit status 1): there might not be enough IDs available in the namespace (requested 0:22 for /run/utmp): lchown /run/utmp: invalid argument
Error: error pulling image "docker://quay.io/podman/stable:latest": unable to pull docker://quay.io/podman/stable:latest: unable to pull image: Error committing the finished image: error adding layer with blob "sha256:03c837e31708e15035b6c6f9a7a4b78b64f6bc10e6daec01684c077655becf95": Error processing tar file(exit status 1): there might not be enough IDs available in the namespace (requested 0:22 for /run/utmp): lchown /run/utmp: invalid argument
````

So this is (not surprisingly) back to the initial problem; the `podman` image is based on Fedora with multiple UIDs.


#### Run `podman` image on OpenShift

Use the stable `podman` image as a base for the container run on OpenShift, built with:

  $ podman build -t $repo/jenkins/podman:latest -f Containerfile.podman-stable

Then spun up on OpenShift:

````
$ ./init.sh 

$ podman version
Version:            1.9.1
RemoteAPI Version:  1
Go Version:         go1.14.2
OS/Arch:            linux/amd64

$ podman pull docker.io/library/alpine
Trying to pull docker.io/library/alpine...
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e
````

It works!


Update the image (with exclude of container-selinux), and it keeps working:

````
$ ./init.sh 

$ podman version
Version:            1.9.3
RemoteAPI Version:  1
Go Version:         go1.14.2
OS/Arch:            linux/amd64

$ podman pull docker.io/library/alpine
Trying to pull docker.io/library/alpine...
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e
````

## Test creation of images

Running an image fails:

````
$ podman run -it docker.io/library/alpine /bin/sh -c "echo 'hello world!'"
ERRO[0000] error unmounting /home/.local/share/containers/storage/overlay/a8e3377a8f75d187a906823f1d8da6bfe5d37771b2d0a4354444f86f722a854c/merged: invalid argument 
Error: error mounting storage for container c967d9189c3ca165788ca68d069cafd3a3f60fd95eb86c6726c6ef3215a20918: error creating overlay mount to /home/.local/share/containers/storage/overlay/a8e3377a8f75d187a906823f1d8da6bfe5d37771b2d0a4354444f86f722a854c/merged: using mount program /usr/bin/fuse-overlayfs: fuse: device not found, try 'modprobe fuse' first
fuse-overlayfs: cannot mount: No such file or directory
: exit status 1
````


Fuse-overlayfs is installed
  https://github.com/containers/libpod/blob/master/docs/tutorials/rootless_tutorial.md#ensure-fuse-overlayfs-is-installed

Kernel is 4.18+:

````
$ uname -a
Linux podman-3-27pvd 4.18.0-147.8.1.el8_1.x86_64 #1 SMP Wed Feb 26 03:08:15 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux
````

Says https://developers.redhat.com/blog/2019/08/14/best-practices-for-running-buildah-in-a-container/:

`Note that using Fuse requires people running the Buildah container to provide the /dev/fuse device`

