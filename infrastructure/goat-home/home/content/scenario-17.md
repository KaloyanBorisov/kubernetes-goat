---
scenario: 17
title: KubeAudit - Audit Kubernetes clusters
notes:
    - kubectl run scenario-17-kubeaudit -n kube-system --overrides='{"spec":{"serviceAccountName":"superadmin"}}' --rm --restart=Never -it --image=madhuakula/hacker-container -- bash
label: Scenario
---

# KubeAudit - Audit Kubernetes clusters

This scenario is mainly to perform the audit of Kubernetes Cluster for various different security concerns.

To get started with this scenario you can run the following command to start the hacker-container with cluster administrator privileges (using the `superadmin` service account from the insecure RBAC setup, which is bound to `cluster-admin`)
