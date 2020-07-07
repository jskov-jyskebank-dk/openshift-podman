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

Building a Containerfile using Buildah: *WORKS*

Building a Containerfile using Podman: *FAILS*


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

Create podman-priv like podman-scc, but base it on the 'privileged' SCC (see `podman-priv-scc.yaml`).

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

### /dev/fuse

Podman SCC changed to include hostPath mounting.

Deployment config (see dc.yaml) changed to include hostPath mounting of `/dev/fuse`.

Output is now:

````
$ podman run -it docker.io/library/alpine /bin/sh -c "echo 'hello world!'"
ERRO[0000] error unmounting /home/.local/share/containers/storage/overlay/a3f03decfadf8f4d9aa4d7b140b804cc06ffd10b4a975ea5dd65bab75ebfb96b/merged: invalid argument 
Error: error mounting storage for container 7c00a14f47d100702aaf24e9e6176b87a06e99e9e0aa3c95f1f124fbeb0e806a: error creating overlay mount to /home/.local/share/containers/storage/overlay/a3f03decfadf8f4d9aa4d7b140b804cc06ffd10b4a975ea5dd65bab75ebfb96b/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open /dev/fuse: Operation not permitted
fuse-overlayfs: cannot mount: Operation not permitted
````



Try updating the podman Fedora image since https://github.com/containers/fuse-overlayfs/issues/116 suggests there may be problems with podman 1.9.1.
No difference (and issue does end up with a fix of fuse, so not surprising)


````
$ podman --log-level debug run -it --device /dev/fuse:rw docker.io/library/alpine /bin/sh -c "echo 'hello'"                                                                                               DEBU[0000] Ignoring lipod.conf 
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP
_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/co
ntainers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /us
r/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 
/usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr
/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-ru
nc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/
volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGI
D CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp
.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr
/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podma
n/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-ru
ntime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/
current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/li
bexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver overlay                   
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] Not configuring container store              
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP
_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/co
ntainers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /us
r/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 
/usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr
/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-ru
nc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/
volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGI
D CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp
.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr
/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver overlay                   
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] No store required. Not opening container store. 
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
WARN[0000] Failed to detect the owner for the current cgroup: stat /sys/fs/cgroup/systemd/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-poda9f8876e_ec1a_4006_ba04_087e9dd82b67.slice/crio-e055ff42ac3d051c2efc897a6735e3f2743d617fa311f35bb80230427833e2ba.scope: no such file or directory 
DEBU[0000] Failed to add podman to systemd sandbox cgroup: exec: "dbus-launch": executable file not found in $PATH 
INFO[0000] running as rootless                          
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/containers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false false false false}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver overlay                   
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] [graphdriver] trying provided driver "overlay" 
DEBU[0000] overlay: mount_program=/usr/bin/fuse-overlayfs 
DEBU[0000] backingFs=overlayfs, projectQuotaSupported=false, useNativeDiff=false, usingMetacopy=false 
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] parsed reference into "[overlay@/home/.local/share/containers/storage+/tmp/run-1000590000/containers:overlay.mount_program=/usr/bin/fuse-overlayfs]docker.io/library/alpine:latest" 
DEBU[0000] parsed reference into "[overlay@/home/.local/share/containers/storage+/tmp/run-1000590000/containers:overlay.mount_program=/usr/bin/fuse-overlayfs]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] Using host netmode                           
DEBU[0000] Loading seccomp profile from "/usr/share/containers/seccomp.json" 
DEBU[0000] created OCI spec and options for new container 
DEBU[0000] Allocated lock 5 for container 9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca 
DEBU[0000] parsed reference into "[overlay@/home/.local/share/containers/storage+/tmp/run-1000590000/containers:overlay.mount_program=/usr/bin/fuse-overlayfs]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] created container "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" 
DEBU[0000] container "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" has work directory "/home/.local/share/containers/storage/overlay-containers/9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca/userdata" 
DEBU[0000] container "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" has run directory "/tmp/run-1000590000/containers/overlay-containers/9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca/userdata" 
DEBU[0000] New container created "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" 
DEBU[0000] container "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" has CgroupParent "/libpod_parent/libpod-9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca" 
DEBU[0000] Handling terminal attach                     
DEBU[0000] overlay: mount_data=lowerdir=/home/.local/share/containers/storage/overlay/l/NGDYABSPNXBHRYAV5S6CCPMLLI,upperdir=/home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/diff,workdir=/home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/work 
ERRO[0000] error unmounting /home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/merged: invalid argument 
DEBU[0000] failed to mount container "9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca": error creating overlay mount to /home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open /dev/fuse: Operation not permitted
fuse-overlayfs: cannot mount: Operation not permitted
: exit status 1 
DEBU[0000] Network is already cleaned up, skipping...   
DEBU[0000] Cleaning up container 9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca 
DEBU[0000] Network is already cleaned up, skipping...   
DEBU[0000] Container 9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca storage is already unmounted, skipping... 
DEBU[0000] ExitCode msg: "error mounting storage for container 9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca: error creating overlay mount to /home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open /dev/fuse: operation not permitted\nfuse-overlayfs: cannot mount: operation not permitted\n: exit status 1" 
ERRO[0000] error mounting storage for container 9ce45faf7719310972823ceeb3afaa4bc6c5b86fe1d59da60946fc12f42541ca: error creating overlay mount to /home/.local/share/containers/storage/overlay/580b977ba737d4ff7eb9e62a9f9ca0fe76cd6d463fbd0a5228cb0d62126e545f/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open /dev/fuse: Operation not permitted
fuse-overlayfs: cannot mount: Operation not permitted
: exit status 1 
````


### Works with privileged

Changing the SCC to allowPrivilegedContainer=true and the Deployment Config:

````
securityContext:
  privileged: true
````

it works:

````
$ podman run -it --device /dev/fuse:rw docker.io/library/alpine /bin/sh -c "echo 'hello'"
Trying to pull docker.io/library/alpine...
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
hello
````

#### Try to find out why /dev/fuse causes trouble

*** With privileged state ***

````
$ ls -l /dev/fuse
crw-rw-rw-. 1 root root 10, 229 Jun 22 11:11 /dev/fuse

$ id
uid=1000590000(builder) gid=0(root) groups=0(root),1000590000

$ podman info
...
  runRoot: /run/user/1000590000/containers
...

$ ls -lZ /dev/fuse
crw-rw-rw-. 1 root root system_u:object_r:fuse_device_t:s0 10, 229 Jun 22 11:11 /dev/fuse

$ stat /dev/fuse
  File: /dev/fuse
  Size: 0               Blocks: 0          IO Block: 4096   character special file
Device: 6h/6d   Inode: 13402       Links: 1     Device type: a,e5
Access: (0666/crw-rw-rw-)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2020-06-22 11:11:56.260120420 +0000
Modify: 2020-06-22 11:11:56.260120420 +0000
Change: 2020-06-22 11:11:56.260120420 +0000
 Birth: -


````


*** Without privileged state ***

All the same as privileged, except that `podman info` shows runRoot at another location.

````
$ ls -l /dev/fuse
crw-rw-rw-. 1 root root 10, 229 Jun 22 11:03 /dev/fuse

$ id
uid=1000590000(builder) gid=0(root) groups=0(root),1000590000

$ podman info
...
  runRoot: /tmp/run-1000590000/containers
...

sh-5.0$ ls -lZ /dev/fuse
crw-rw-rw-. 1 root root system_u:object_r:fuse_device_t:s0 10, 229 Jun 22 11:11 /dev/fuse

$ stat /dev/fuse
  File: /dev/fuse
  Size: 0               Blocks: 0          IO Block: 4096   character special file
Device: 6h/6d   Inode: 13402       Links: 1     Device type: a,e5
Access: (0666/crw-rw-rw-)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2020-06-22 11:11:56.260120420 +0000
Modify: 2020-06-22 11:11:56.260120420 +0000
Change: 2020-06-22 11:11:56.260120420 +0000
 Birth: -
````



## Run as root

Make sure DeployConfig has:

````
securityContext:
  privileged: false
````

Create new `podman-anyuid-scc.yaml` cloned from `anyuid` SCC, adding the hostPath element, and setting priority 20.

Load it:

````
$ oc create -f podman-anyid-scc.yaml
````



Restarting the pod, and it now runs with `openshift.io/scc: podman-anyuid`.

````
sh-5.0# id
uid=0(root) gid=0(root) groups=0(root)

sh-5.0# podman --log-level debug info
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 bridge false 2048 private /usr/share/containers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /var/run/libpod/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /var/lib/containers/storage/libpod 10 /var/run/libpod /var/lib/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /var/run/libpod/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /var/lib/containers/storage/libpod 10 /var/run/libpod /var/lib/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /var/lib/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver overlay                   
DEBU[0000] Using graph root /var/lib/containers/storage 
DEBU[0000] Using run root /var/run/containers/storage   
DEBU[0000] Using static dir /var/lib/containers/storage/libpod 
DEBU[0000] Using tmp dir /var/run/libpod                
DEBU[0000] Using volume path /var/lib/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] [graphdriver] trying provided driver "overlay" 
DEBU[0000] overlay: imagestore=/var/lib/shared          
DEBU[0000] overlay: mount_program=/usr/bin/fuse-overlayfs 
ERRO[0000] could not get runtime: mount /var/lib/containers/storage/overlay:/var/lib/containers/storage/overlay, flags: 0x1000: operation not permitted 

sh-5.0# ls -l /var/lib/containers/storage/overlay
total 0
drwx------. 2 root root 6 Jun 23 06:50 l
````


In this issue:
 https://github.com/containers/buildah/issues/867

 Dan suggests mounting storage on top of /var/lib/containers is required

 (why is this different from running as user?)

````
sh-5.0$ df
Filesystem                           1K-blocks     Used Available Use% Mounted on
overlay                              125277164 60691652  64585512  49% /
tmpfs                                    65536        0     65536   0% /dev
tmpfs                                 16468192        0  16468192   0% /sys/fs/cgroup
shm                                      65536        0     65536   0% /dev/shm
tmpfs                                 16468192     9660  16458532   1% /etc/hostname
devtmpfs                              16430336        0  16430336   0% /dev/fuse
/dev/mapper/coreos-luks-root-nocrypt 125277164 60691652  64585512  49% /etc/hosts
tmpfs                                 16468192       24  16468168   1% /run/secrets/kubernetes.io/serviceaccount
tmpfs                                 16468192        0  16468192   0% /proc/acpi
tmpfs                                 16468192        0  16468192   0% /proc/scsi
tmpfs                                 16468192        0  16468192   0% /sys/firmware
````

Tried a simple hack of using a tmpfs folder at the `/var/lib/containers/storage`:

````
sh-5.0# ls -l /var/lib/containers/storage 
lrwxrwxrwx. 1 root root 15 Jun 23 08:26 /var/lib/containers/storage -> /dev/xx/storage
````

Similar for linking at `/var/lib/containers`.


### Wrong config file when running as root

When running as root, the configuration file `/usr/share/containers/libpod.conf` is picked up:

````
DEBU[0000] Found deprecated file /usr/share/containers/libpod.conf, please remove. Use /etc/containers/containers.conf to override defaults. 
DEBU[0000] Reading configuration file "/usr/share/containers/libpod.conf" 
...
````

This does not happen when running rootless. But deleting the file does not appear to change anything:

````
rm /usr/share/containers/libpod.conf
````

### Try with VFS

````
$ podman --storage-driver=vfs info
host:
  arch: amd64
  buildahVersion: 1.14.8
  cgroupVersion: v1
  conmon:
    package: conmon-2.0.15-1.fc32.x86_64
    path: /usr/bin/conmon
    version: 'conmon version 2.0.15, commit: 33da5ef83bf2abc7965fc37980a49d02fdb71826'
  cpus: 4
  distribution:
    distribution: fedora
    version: "32"
  eventLogger: file
  hostname: podman-5-8sm92
  idMappings:
    gidmap:
    - container_id: 0
      host_id: 0
      size: 1
    - container_id: 1
      host_id: 10000
      size: 65536
    uidmap:
    - container_id: 0
      host_id: 1000590000
      size: 1
    - container_id: 1
      host_id: 10000
      size: 65536
  kernel: 4.18.0-147.8.1.el8_1.x86_64
  memFree: 3907596288
  memTotal: 33726861312
  ociRuntime:
    name: crun
    package: crun-0.13-2.fc32.x86_64
    path: /usr/bin/crun
    version: |-
      crun version 0.13
      commit: e79e4de4ac16da0ce48777afb72c6241de870525
      spec: 1.0.0
      +SYSTEMD +SELINUX +APPARMOR +CAP +SECCOMP +EBPF +YAJL
  os: linux
  rootless: true
  slirp4netns:
    executable: /usr/bin/slirp4netns
    package: slirp4netns-1.0.0-1.fc32.x86_64
    version: |-
      slirp4netns version 1.0.0
      commit: a3be729152a33e692cd28b52f664defbf2e7810a
      libslirp: 4.2.0
  swapFree: 0
  swapTotal: 0
  uptime: 677h 51m 3.16s (Approximately 28.21 days)
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
  graphDriverName: vfs
  graphOptions: {}
  graphRoot: /home/.local/share/containers/storage
  graphStatus: {}
  imageStore:
    number: 0
  runRoot: /tmp/run-1000590000/containers
  volumePath: /home/.local/share/containers/storage/volumes




$ podman --storage-driver=vfs pull docker.io/library/alpine
Trying to pull docker.io/library/alpine...
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e
````

But running the command still fails:

````
$ id
uid=1000590000(builder) gid=0(root) groups=0(root),1000590000

$ podman --storage-driver=vfs version                                                                     
Version:            1.9.1
RemoteAPI Version:  1
Go Version:         go1.14.2
OS/Arch:            linux/amd64

$ podman --storage-driver=vfs --log-level debug run -it docker.io/library/alpine /bin/sh -c "echo 'hello'"
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/containers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 
/usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr
/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGI
D CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp
.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr
/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podma
n/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-ru
ntime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/
current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libex
ec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] Not configuring container store              
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP
_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/co
ntainers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /us
r/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 
/usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr
/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-ru
nc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/vol
umes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGI
D CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp
.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr
/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] [graphdriver] trying provided driver "vfs"   
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
WARN[0000] Failed to detect the owner for the current cgroup: stat /sys/fs/cgroup/systemd/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-podd79fea22_428a_4a08_adfa_30f24bd2a4f1.slice/crio-1c3679a2c8de50402cd2da66aa43492648f405156046f8867e83b7f1692779e7.scope: no such file or directory 
DEBU[0000] Failed to add podman to systemd sandbox cgroup: exec: "dbus-launch": executable file not found in $PATH 
INFO[0000] running as rootless                          
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/containers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000590000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/.local/share/containers/storage/libpod 10 /tmp/run-1000590000/libpod/tmp /home/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000590000/containers 
DEBU[0000] Using static dir /home/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000590000/libpod/tmp 
DEBU[0000] Using volume path /home/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] parsed reference into "[vfs@/home/.local/share/containers/storage+/tmp/run-1000590000/containers]docker.io/library/alpine:latest" 
DEBU[0000] parsed reference into "[vfs@/home/.local/share/containers/storage+/tmp/run-1000590000/containers]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] [graphdriver] trying provided driver "vfs"   
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] Using host netmode                           
DEBU[0000] Loading seccomp profile from "/usr/share/containers/seccomp.json" 
DEBU[0000] created OCI spec and options for new container 
DEBU[0000] Allocated lock 1 for container fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 
DEBU[0000] parsed reference into "[vfs@/home/.local/share/containers/storage+/tmp/run-1000590000/containers]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] created container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" 
DEBU[0000] container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" has work directory "/home/.local/share/containers/storage/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata" 
DEBU[0000] container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" has run directory "/tmp/run-1000590000/containers/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata" 
DEBU[0000] New container created "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" 
DEBU[0000] container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" has CgroupParent "/libpod_parent/libpod-fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" 
DEBU[0000] Handling terminal attach                     
DEBU[0000] mounted container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" at "/home/.local/share/containers/storage/vfs/dir/3d651c0bc695dbdbac73b64a34431110b4a0eb2f465bd42330744a5a534c35b8" 
DEBU[0000] Created root filesystem for container fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 at /home/.local/share/containers/storage/vfs/dir/3d651c0bc695dbdbac73b64a34431110b4a0eb2f465bd42330744a5a534c35b8 
DEBU[0000] /etc/system-fips does not exist on host, not mounting FIPS mode secret 
DEBU[0000] reading hooks from /usr/share/containers/oci/hooks.d 
DEBU[0000] Created OCI spec for container fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 at /home/.local/share/containers/storage/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata/config.json 
DEBU[0000] /usr/bin/conmon messages will be logged to syslog 
DEBU[0000] running conmon: /usr/bin/conmon               args="[--api-version 1 -c fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 -u fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 -r /usr/bin/crun -b /home/.local/share/containers/storage/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata -p /tmp/run-1000590000/containers/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata/pidfile -l k8s-file:/home/.local/share/containers/storage/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata/ctr.log --exit-dir /tmp/run-1000590000/libpod/tmp/exits --socket-dir-path /tmp/run-1000590000/libpod/tmp/socket --log-level debug --syslog -t --conmon-pidfile /tmp/run-1000590000/containers/vfs-containers/fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911/userdata/conmon.pid --exit-command /usr/bin/podman --exit-command-arg --root --exit-command-arg /home/.local/share/containers/storage --exit-command-arg --runroot --exit-command-arg /tmp/run-1000590000/containers --exit-command-arg --log-level --exit-command-arg debug --exit-command-arg --cgroup-manager --exit-command-arg cgroupfs --exit-command-arg --tmpdir --exit-command-arg /tmp/run-1000590000/libpod/tmp --exit-command-arg --runtime --exit-command-arg crun --exit-command-arg --storage-driver --exit-command-arg vfs --exit-command-arg --events-backend --exit-command-arg file --exit-command-arg container --exit-command-arg cleanup --exit-command-arg fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911]"
WARN[0000] Failed to add conmon to cgroupfs sandbox cgroup: error creating cgroup for cpu: mkdir /sys/fs/cgroup/cpu/libpod_parent: read-only file system 
DEBU[0000] Received: -1                                 
DEBU[0000] Cleaning up container fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911 
DEBU[0000] Network is already cleaned up, skipping...   
DEBU[0000] unmounted container "fea970dd476588d3b2fa34673674edcc00916da44662caa4f750307a201c1911" 
DEBU[0000] ExitCode msg: "mount `proc` to '/home/.local/share/containers/storage/vfs/dir/3d651c0bc695dbdbac73b64a34431110b4a0eb2f465bd42330744a5a534c35b8/proc': permission denied: oci runtime permission denied error" 
ERRO[0000] mount `proc` to '/home/.local/share/containers/storage/vfs/dir/3d651c0bc695dbdbac73b64a34431110b4a0eb2f465bd42330744a5a534c35b8/proc': Permission denied: OCI runtime permission denied error 
````

NOTE: Same problem when dnf-updating the fedora image (which includes podman 1.9.3)


### chroot

Pre image by appending (to `Containerfile.podman-stable`):

````
RUN dnf install buildah -y --exclude container-selinux
````

Run resulting image under podman-anyuid as root:


````
sh-5.0# echo podman:10000:65536 > /etc/subuid
sh-5.0# echo podman:10000:65536 > /etc/subgid
sh-5.0# su - podman

[podman@podman-8-c5qp7 ~]$ buildah version
Version:         1.14.9
Go Version:      go1.14.2
Image Spec:      1.0.1-dev
Runtime Spec:    1.0.1-dev
CNI Spec:        0.4.0
libcni Version:  
image Version:   5.4.3
Git Commit:      
Built:           Thu Jan  1 00:00:00 1970
OS/Arch:         linux/amd64

[podman@podman-8-c5qp7 ~]$ buildah from docker.io/library/alpine
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
alpine-working-container

[podman@podman-8-c5qp7 ~]$ buildah --log-level debug run --isolation chroot alpine-working-container ls /
DEBU running [buildah-in-a-user-namespace --log-level debug run --isolation chroot alpine-working-container ls /] with environment [SHELL=/bin/bash HISTCONTROL=ignoredups HISTSIZE=1000 HOSTNAME= PWD=/home/podman LOGNAME=podman HOME=/home/pod
man LANG=C.UTF-8 LS_COLORS=rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=01;37;41:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31
:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz
=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=0
1;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.
pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.webp=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:
*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=01;36:*.au=01;36:*.flac=01;36:*.m4a=01;36:*.mid=01;36:*.midi=01;36:*.mka=01;36:*.mp3=01;36:*.
mpc=01;36:*.ogg=01;36:*.ra=01;36:*.wav=01;36:*.oga=01;36:*.opus=01;36:*.spx=01;36:*.xspf=01;36: BUILDAH_ISOLATION=chroot TERM=xterm USER=podman SHLVL=1 PATH=/home/podman/.local/bin:/home/podman/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/us
r/sbin MAIL=/var/spool/mail/podman _=/usr/bin/buildah TMPDIR=/var/tmp _CONTAINERS_USERNS_CONFIGURED=1], UID map [{ContainerID:0 HostID:1000 Size:1} {ContainerID:1 HostID:10000 Size:65536}], and GID map [{ContainerID:0 HostID:1000 Size:1} {Co
ntainerID:1 HostID:10000 Size:65536}] 
DEBU [graphdriver] trying provided driver "overlay" 
DEBU overlay: mount_program=/usr/bin/fuse-overlayfs 
DEBU backingFs=overlayfs, projectQuotaSupported=false, useNativeDiff=false, usingMetacopy=false 
DEBU using "/var/tmp/buildah994730804" to hold bundle data 
DEBU Resources: &buildah.CommonBuildOptions{AddHost:[]string{}, CgroupParent:"", CPUPeriod:0x0, CPUQuota:0, CPUShares:0x0, CPUSetCPUs:"", CPUSetMems:"", HTTPProxy:true, Memory:0, DNSSearch:[]string{}, DNSServers:[]string{}, DNSOptions:[]stri
ng{}, MemorySwap:0, LabelOpts:[]string(nil), SeccompProfilePath:"/usr/share/containers/seccomp.json", ApparmorProfile:"", ShmSize:"65536k", Ulimit:[]string{"nproc=1048576:1048576"}, Volumes:[]string{}} 
DEBU overlay: mount_data=lowerdir=/home/podman/.local/share/containers/storage/overlay/l/VUBMQEZB7D4VJWLROCODAIR24F,upperdir=/home/podman/.local/share/containers/storage/overlay/1ca1feda8f3a76261656185490fb0faeb6a192fa8a04ac9a4e12ef0082e0ec2
8/diff,workdir=/home/podman/.local/share/containers/storage/overlay/1ca1feda8f3a76261656185490fb0faeb6a192fa8a04ac9a4e12ef0082e0ec28/work 
ERRO error unmounting /home/podman/.local/share/containers/storage/overlay/1ca1feda8f3a76261656185490fb0faeb6a192fa8a04ac9a4e12ef0082e0ec28/merged: invalid argument 
DEBU error running [ls /] in container "alpine-working-container": error mounting container "8563a43b0e4254fa3003b5fafc79c0f6371ca7bc89f3ffb8d61bcb314d80d05b": error mounting build container "8563a43b0e4254fa3003b5fafc79c0f6371ca7bc89f3ffb8d
61bcb314d80d05b": error creating overlay mount to /home/podman/.local/share/containers/storage/overlay/1ca1feda8f3a76261656185490fb0faeb6a192fa8a04ac9a4e12ef0082e0ec28/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open
 /dev/fuse: Operation not permitted
fuse-overlayfs: cannot mount: Operation not permitted
: exit status 1 
error mounting container "8563a43b0e4254fa3003b5fafc79c0f6371ca7bc89f3ffb8d61bcb314d80d05b": error mounting build container "8563a43b0e4254fa3003b5fafc79c0f6371ca7bc89f3ffb8d61bcb314d80d05b": error creating overlay mount to /home/podman/.loc
al/share/containers/storage/overlay/1ca1feda8f3a76261656185490fb0faeb6a192fa8a04ac9a4e12ef0082e0ec28/merged: using mount program /usr/bin/fuse-overlayfs: fuse: failed to open /dev/fuse: Operation not permitted
fuse-overlayfs: cannot mount: Operation not permitted
: exit status 1
ERRO exit status 1                                

[podman@podman-8-c5qp7 ~]$ ls -lZ /dev/fuse
crw-rw-rw-. 1 root root system_u:object_r:fuse_device_t:s0 10, 229 Jun 22 11:03 /dev/fuse
````

Podman also fails as before:

````
podman~$ export BUILDAH_ISOLATION=chroot
podman~$ podman pull docker.io/library/alpine
podman~$ podman --log-level debug run -it docker.io/library/alpine /bin/sh -c "echo 'hello'"
*** BOOM ***
````


### buildah chroot and VFS

Stay with VFS

````
sh-5.0# echo podman:10000:65536 > /etc/subuid
sh-5.0# echo podman:10000:65536 > /etc/subgid
sh-5.0# su - podman

[podman@podman-8-c5qp7 ~]$ buildah version
Version:         1.14.9
Go Version:      go1.14.2
Image Spec:      1.0.1-dev
Runtime Spec:    1.0.1-dev
CNI Spec:        0.4.0
libcni Version:  
image Version:   5.4.3
Git Commit:      
Built:           Thu Jan  1 00:00:00 1970
OS/Arch:         linux/amd64

[podman@podman-8-c5qp7 ~]$ buildah --storage-driver=vfs from docker.io/library/alpine
Getting image source signatures
Copying blob df20fa9351a1 done  
Copying config a24bb40132 done  
Writing manifest to image destination
Storing signatures
alpine-working-container

[podman@podman-8-c5qp7 ~]$ buildah --storage-driver=vfs run --isolation chroot alpine-working-container ls /
buildah --storage-driver=vfs run --isolation chroot alpine-working-container ls /
bin    dev    etc    home   lib    media  mnt    opt    proc   root   run    sbin   srv    sys    tmp    usr    var
````

So it actually works!

Which leads to the end goal - building a new image from inside OpenShift:

````
$ buildah --storage-driver=vfs bud /home/Containerfile.openshift
STEP 1: FROM fedora:33
Getting image source signatures
Copying blob 36df5217b961 done  
Copying config 1cac645b74 done  
Writing manifest to image destination
Storing signatures
STEP 2: MAINTAINER jskov@jyskebank.dk
STEP 3: LABEL os.updated="2020.06.18"
STEP 4: RUN dnf update -y
Fedora 33 openh264 (From Cisco) - x86_64        
....
Installed:
  acl-2.2.53-6.fc33.x86_64                            attr-2.4.48-9.fc33.x86_64                                     buildah-1.15.0-0.67.dev.git2c46b4b.fc33.x86_64                    catatonit-0.1.5-2.fc33.x86_64                               
  conmon-2:2.0.19-0.2.dev.gitab8f5e5.fc33.x86_64      container-selinux-2:2.137.0-2.dev.git6b721da.fc33.noarch      containernetworking-plugins-0.8.6-5.1.git28773dc.fc33.x86_64      containers-common-1:1.0.1-16.dev.git091f924.fc33.x86_64     
  criu-3.14-5.fc33.x86_64                             crun-0.14-1.fc33.x86_64                                       cryptsetup-libs-2.3.3-1.fc33.x86_64                               dbus-1:1.12.20-1.fc33.x86_64                                
  dbus-broker-23-2.fc33.x86_64                        dbus-common-1:1.12.20-1.fc33.noarch                           device-mapper-1.02.171-2.fc33.x86_64                              device-mapper-libs-1.02.171-2.fc33.x86_64                   
  diffutils-3.7-4.fc32.x86_64                         fuse-common-3.9.2-1.fc33.x86_64                               fuse-overlayfs-1.1.0-6.dev.git50ab2c2.fc33.x86_64                 fuse3-3.9.2-1.fc33.x86_64                                   
  fuse3-libs-3.9.2-1.fc33.x86_64                      hwdata-0.337-1.fc33.noarch                                    iptables-1.8.5-1.fc33.x86_64                                      iptables-libs-1.8.5-1.fc33.x86_64                           
  jansson-2.12-5.fc32.x86_64                          kmod-27-2.fc33.x86_64                                         kmod-libs-27-2.fc33.x86_64                                        libargon2-20171227-4.fc32.x86_64                            
  libbsd-0.10.0-2.fc32.x86_64                         libibverbs-30.0-4.fc33.x86_64                                 libmnl-1.0.4-11.fc32.x86_64                                       libnet-1.1.6-19.fc32.x86_64                                 
  libnetfilter_conntrack-1.0.7-4.fc32.x86_64          libnfnetlink-1.0.1-17.fc32.x86_64                             libnftnl-1.1.7-1.fc33.x86_64                                      libnl3-3.5.0-3.fc33.x86_64                                  
  libpcap-14:1.9.1-4.fc33.x86_64                      libseccomp-2.4.2-3.fc32.x86_64                                libselinux-utils-3.0-5.fc33.x86_64                                libslirp-4.3.0-1.fc33.x86_64                                
  libxkbcommon-0.10.0-2.fc32.x86_64                   nftables-1:0.9.3-4.fc33.x86_64                                pciutils-3.6.4-1.fc33.x86_64                                      pciutils-libs-3.6.4-1.fc33.x86_64                           
  podman-2:2.1.0-0.48.dev.gitb9d48a9.fc33.x86_64      podman-plugins-2:2.1.0-0.48.dev.gitb9d48a9.fc33.x86_64        policycoreutils-3.0-4.fc33.x86_64                                 protobuf-c-1.3.3-2.fc33.x86_64                              
  qrencode-libs-4.0.2-5.fc32.x86_64                   rdma-core-30.0-4.fc33.x86_64                                  rpm-plugin-selinux-4.16.0-0.beta3.2.fc33.x86_64                   runc-2:1.0.0-254.dev.git3cb1909.fc33.x86_64                 
  selinux-policy-3.14.6-17.fc33.noarch                selinux-policy-targeted-3.14.6-17.fc33.noarch                 slirp4netns-1.1.1-6.dev.gitdd4af4f.fc33.x86_64                    systemd-245.6-2.fc33.x86_64                                 
  systemd-pam-245.6-2.fc33.x86_64                     systemd-rpm-macros-245.6-2.fc33.noarch                        xkeyboard-config-2.30-2.fc33.noarch                               yajl-2.1.0-14.fc32.x86_64                                   

Complete!
STEP 6: RUN mkdir -p /home  && chmod a+rwx /home  && touch /etc/subgid /etc/subuid  && chmod g=u /etc/subgid /etc/subuid /etc/passwd
STEP 7: ENV HOME=/home
STEP 8: ENV USER=builder
STEP 9: WORKDIR $HOME
STEP 10: ADD init.sh $HOME/
STEP 11: CMD ["python3", "-m", "http.server"]
STEP 12: COMMIT
Getting image source signatures
Copying blob d734fbc798d2 skipped: already exists  
Copying blob f670de48f929 done  
Copying config 595c98c1ff done  
Writing manifest to image destination
Storing signatures
--> 595c98c1ff1
595c98c1ff1b532e6e0cd1dc638288b6136d59af79686d24f5ff0ee588033004
````

Yes!


### podman chroot and VFS

It still fails with Podman though.

````
sh-5.0# echo podman:10000:65536 > /etc/subuid
sh-5.0# echo podman:10000:65536 > /etc/subgid
sh-5.0# su - podman

podman~$ export BUILDAH_ISOLATION=chroot

podman~$ podman --storage-driver=vfs pull docker.io/library/alpine
podman~$ podman --storage-driver=vfs --log-level debug run -it docker.io/library/alpine /bin/sh -c "echo 'hello'"
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_
SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/cont
ainers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/s
bin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libex
ec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/
kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc
 /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes}
 {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID
 CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.j
son 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/lo
cal/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatoni
t shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/
local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-syst
em/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes} {[/usr/libexec/cn
i /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/podman/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/podman/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000/containers      
DEBU[0000] Using static dir /home/podman/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000/libpod/tmp       
DEBU[0000] Using volume path /home/podman/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] Not configuring container store              
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_
SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/cont
ainers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/s
bin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libex
ec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/
kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc
 /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes}
 {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/podman/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/podman/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000/containers      
DEBU[0000] Using static dir /home/podman/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000/libpod/tmp       
DEBU[0000] Using volume path /home/podman/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] [graphdriver] trying provided driver "vfs"   
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
WARN[0000] Failed to detect the owner for the current cgroup: stat /sys/fs/cgroup/systemd/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod83dfd939_5abc_4d57_b52c_808fa438046a.slice/crio-84f3e4777221de6bab485123d7be8142261928558dd3f0b5d788a8215b4046b0.scope: no such file or directory 
DEBU[0000] Failed to add podman to systemd sandbox cgroup: exec: "dbus-launch": executable file not found in $PATH 
INFO[0000] running as rootless                          
DEBU[0000] Ignoring lipod.conf EventsLogger setting "journald". Use containers.conf if you want to change this setting and remove libpod.conf files. 
DEBU[0000] Reading configuration file "/usr/share/containers/containers.conf" 
DEBU[0000] Merged system config "/usr/share/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  private k8s-file -1 slirp4netns false 2048 private /usr/share/containers/seccomp.json 65536k private host 65536} {false systemd [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 runc map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Reading configuration file "/etc/containers/containers.conf" 
DEBU[0000] Merged system config "/etc/containers/containers.conf": &{{[] [] container-default [] host [CAP_AUDIT_WRITE CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_FSETID CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETFCAP CAP_SETGID CAP_SETPCAP CAP_SETUID CAP_SYS_CHROOT] [] [nproc=1048576:1048576]  [] [] [] false [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] false false false  host k8s-file -1 host false 2048 private /usr/share/containers/seccomp.json 65536k host host 65536} {false cgroupfs [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin] [/usr/libexec/podman/conmon /usr/local/libexec/podman/conmon /usr/local/lib/podman/conmon /usr/bin/conmon /usr/sbin/conmon /usr/local/bin/conmon /usr/local/sbin/conmon /run/current-system/sw/bin/conmon] ctrl-p,ctrl-q true /tmp/run-1000/libpod/tmp/events/events.log file [/usr/share/containers/oci/hooks.d] docker:// /pause k8s.gcr.io/pause:3.2 /usr/libexec/podman/catatonit shm   false 2048 crun map[crun:[/usr/bin/crun /usr/sbin/crun /usr/local/bin/crun /usr/local/sbin/crun /sbin/crun /bin/crun /run/current-system/sw/bin/crun] kata:[/usr/bin/kata-runtime /usr/sbin/kata-runtime /usr/local/bin/kata-runtime /usr/local/sbin/kata-runtime /sbin/kata-runtime /bin/kata-runtime /usr/bin/kata-qemu /usr/bin/kata-fc] runc:[/usr/bin/runc /usr/sbin/runc /usr/local/bin/runc /usr/local/sbin/runc /sbin/runc /bin/runc /usr/lib/cri-o-runc/sbin/runc /run/current-system/sw/bin/runc]] missing [] [crun runc] [crun] {false false false true true true}  false 3 /home/podman/.local/share/containers/storage/libpod 10 /tmp/run-1000/libpod/tmp /home/podman/.local/share/containers/storage/volumes} {[/usr/libexec/cni /usr/lib/cni /usr/local/lib/cni /opt/cni/bin] podman /etc/cni/net.d/}} 
DEBU[0000] Using conmon: "/usr/bin/conmon"              
DEBU[0000] Initializing boltdb state at /home/podman/.local/share/containers/storage/libpod/bolt_state.db 
DEBU[0000] Using graph driver vfs                       
DEBU[0000] Using graph root /home/podman/.local/share/containers/storage 
DEBU[0000] Using run root /tmp/run-1000/containers      
DEBU[0000] Using static dir /home/podman/.local/share/containers/storage/libpod 
DEBU[0000] Using tmp dir /tmp/run-1000/libpod/tmp       
DEBU[0000] Using volume path /home/podman/.local/share/containers/storage/volumes 
DEBU[0000] Set libpod namespace to ""                   
DEBU[0000] Initializing event backend file              
DEBU[0000] using runtime "/usr/bin/runc"                
DEBU[0000] using runtime "/usr/bin/crun"                
WARN[0000] Error initializing configured OCI runtime kata: no valid executable found for OCI runtime kata: invalid argument 
DEBU[0000] parsed reference into "[vfs@/home/podman/.local/share/containers/storage+/tmp/run-1000/containers]docker.io/library/alpine:latest" 
DEBU[0000] parsed reference into "[vfs@/home/podman/.local/share/containers/storage+/tmp/run-1000/containers]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] [graphdriver] trying provided driver "vfs"   
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] Using host netmode                           
DEBU[0000] Loading seccomp profile from "/usr/share/containers/seccomp.json" 
DEBU[0000] created OCI spec and options for new container 
DEBU[0000] Allocated lock 1 for container 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 
DEBU[0000] parsed reference into "[vfs@/home/podman/.local/share/containers/storage+/tmp/run-1000/containers]@a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] exporting opaque data as blob "sha256:a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e" 
DEBU[0000] created container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" 
DEBU[0000] container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" has work directory "/home/podman/.local/share/containers/storage/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata" 
DEBU[0000] container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" has run directory "/tmp/run-1000/containers/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata" 
DEBU[0000] New container created "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" 
DEBU[0000] container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" has CgroupParent "/libpod_parent/libpod-17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" 
DEBU[0000] Handling terminal attach                     
DEBU[0000] mounted container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" at "/home/podman/.local/share/containers/storage/vfs/dir/79f42c390782d4390e493f90f1a636acfacf538975868c000ef8446efab4130a" 
DEBU[0000] Created root filesystem for container 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 at /home/podman/.local/share/containers/storage/vfs/dir/79f42c390782d4390e493f90f1a636acfacf538975868c000ef8446efab4130a 
DEBU[0000] /etc/system-fips does not exist on host, not mounting FIPS mode secret 
DEBU[0000] reading hooks from /usr/share/containers/oci/hooks.d 
DEBU[0000] Created OCI spec for container 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 at /home/podman/.local/share/containers/storage/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata/config.json 
DEBU[0000] /usr/bin/conmon messages will be logged to syslog 
DEBU[0000] running conmon: /usr/bin/conmon               args="[--api-version 1 -c 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 -u 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 -r /usr/bin/crun -b /home/podman/.local/share/containers/storage/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata -p /tmp/run-1000/containers/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata/pidfile -l k8s-file:/home/podman/.local/share/containers/storage/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata/ctr.log --exit-dir /tmp/run-1000/libpod/tmp/exits --socket-dir-path /tmp/run-1000/libpod/tmp/socket --log-level debug --syslog -t --conmon-pidfile /tmp/run-1000/containers/vfs-containers/17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4/userdata/conmon.pid --exit-command /usr/bin/podman --exit-command-arg --root --exit-command-arg /home/podman/.local/share/containers/storage --exit-command-arg --runroot --exit-command-arg /tmp/run-1000/containers --exit-command-arg --log-level --exit-command-arg debug --exit-command-arg --cgroup-manager --exit-command-arg cgroupfs --exit-command-arg --tmpdir --exit-command-arg /tmp/run-1000/libpod/tmp --exit-command-arg --runtime --exit-command-arg crun --exit-command-arg --storage-driver --exit-command-arg vfs --exit-command-arg --events-backend --exit-command-arg file --exit-command-arg container --exit-command-arg cleanup --exit-command-arg 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4]"
WARN[0000] Failed to add conmon to cgroupfs sandbox cgroup: error creating cgroup for cpuset: mkdir /sys/fs/cgroup/cpuset/libpod_parent: read-only file system 
DEBU[0000] Received: -1                                 
DEBU[0000] Cleaning up container 17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4 
DEBU[0000] Network is already cleaned up, skipping...   
DEBU[0000] unmounted container "17a17cfe9bccd21360e1dae3a6ed709a2ffecb84df1ac55bde8e22cef0229ca4" 
DEBU[0000] ExitCode msg: "mount `proc` to '/home/podman/.local/share/containers/storage/vfs/dir/79f42c390782d4390e493f90f1a636acfacf538975868c000ef8446efab4130a/proc': permission denied: oci runtime permission denied error" 
ERRO[0000] mount `proc` to '/home/podman/.local/share/containers/storage/vfs/dir/79f42c390782d4390e493f90f1a636acfacf538975868c000ef8446efab4130a/proc': Permission denied: OCI runtime permission denied error 
````
