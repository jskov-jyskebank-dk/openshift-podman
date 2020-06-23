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

Create new `podman-anyuid.yaml` cloned from `anyuid` SCC, adding the hostPath element, and setting priority 20.

Load it:

````
$ oc create -f podman-anyid.yaml
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


