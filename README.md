管理节点组件(kubernetes_mgr.yml): 所有节点都需要提前安装这个
    kubeadm
    kubectl

kubernetes master 节点运行如下组件(kubernetes_master.yml):
    kube-apiserver
    kube-scheduler
    kube-controller-manager

kubernetes work 节点运行如下组件(kubernetes_work.yml):
    docker
    kubelet
    kube-proxy

各节点的组件二进制文件最好重新拷贝

各role包含文件
etcd角色
roles/etcd/files/
 etcd
 etcdctl
 etcd-key.pem
 etcd.pem

roles/etcd/templates/
 etcd.service.j2


flanneld角色
roles/flanneld/files/
 flanneld
 flanneld-key.pem
 flanneld.pem
 mk-docker-opts.sh


kubernetes_common角色
roles/kubernetes_common/files/
 ca-config.json
 ca-key.pem
 ca.pem
 cfssl
 cfssl-certinfo
 cfssljson
 kubeadm
 kubectl
 kubernetes.conf

roles/kubernetes_common/templates/
 kubectl.kubeconfig.j2


kubernetes_master角色
roles/kubernetes_master/files/
 kube-apiserver
 kube-controller-manager
 kube-controller-manager-key.pem
 kube-controller-manager.pem
 kubernetes-key.pem
 kubernetes.pem
 kube-scheduler

roles/kubernetes_master/templates/
 encryption-config.yaml.j2
 kube-apiserver.service.j2
 kube-controller-manager.kubeconfig.j2
 kube-controller-manager.service.j2
 kube-scheduler.kubeconfig.j2
 kube-scheduler.service.j2


kubernetes_work角色
roles/kubernetes_work/files/
 docker
 docker-containerd
 docker-containerd-ctr
 docker-containerd-shim
 dockerd
 docker-daemon.json
 docker-init
 docker-proxy
 docker-runc
 kubelet
 kube-proxy

roles/kubernetes_work/templates/
 docker.service.j2
 kubelet_bootstrap_kubeconfig.sh.j2
 kubelet.config.json.j2
 kubelet.service.j2
 kube-proxy.config.yaml.j2
 kube-proxy.kubeconfig.j2
 kube-proxy.service.j2


部署完etcd后，etc节点上执行如下命令：

    ETCDCTL_API=3 /opt/k8s/bin/etcdctl \
    --endpoints=https://192.168.95.11:2379 \
    --cacert=/opt/k8s/work/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem endpoint health

预期输出
https://192.168.95.11:2379 is healthy: successfully committed proposal: took = 1.487615ms

向 etcd 写入集群 Pod 网段信息
注意：本步骤只需在任意etcd节点执行一次。

etcdctl \
  --endpoints=https://192.168.95.11:2379 \
  --ca-file=/opt/k8s/work/ca.pem \
  --cert-file=/opt/k8s/work/flanneld.pem \
  --key-file=/opt/k8s/work/flanneld-key.pem \
  set /kubernetes/network/config '{"Network":"'172.30.0.0/16'", "SubnetLen": 21, "Backend": {"Type": "vxlan"}}'


验证flannel

systemctl status flanneld

检查分配给各 flanneld 的 Pod 网段信息

etcdctl \
  --endpoints=https://192.168.95.11:2379 \
  --ca-file=/etc/kubernetes/cert/ca.pem \
  --cert-file=/etc/flanneld/cert/flanneld.pem \
  --key-file=/etc/flanneld/cert/flanneld-key.pem \
  get kubernetes/network/config

查看已分配的 Pod 子网段列表

etcdctl \
  --endpoints=https://192.168.95.11:2379 \
  --ca-file=/etc/kubernetes/cert/ca.pem \
  --cert-file=/etc/flanneld/cert/flanneld.pem \
  --key-file=/etc/flanneld/cert/flanneld-key.pem \
  ls kubernetes/network/subnets

检查 kube-apiserver 运行状态
    systemctl status kube-apiserver |grep 'Active:'


打印 kube-apiserver 写入 etcd 的数据

source /opt/k8s/bin/environment.sh
ETCDCTL_API=3 etcdctl \
    --endpoints=192.168.95.11:6443 \
    --cacert=/opt/k8s/work/ca.pem \
    --cert=/opt/k8s/work/etcd.pem \
    --key=/opt/k8s/work/etcd-key.pem \
    get /registry/ --prefix --keys-only

检查集群信息

$ kubectl cluster-info
$ kubectl get all --all-namespaces
$ kubectl get componentstatuses

授予 kubernetes 证书访问 kubelet API 的权限
在执行 kubectl exec、run、logs 等命令时，apiserver 会转发到 kubelet。这里定义 RBAC 规则，授权 apiserver 调用 kubelet API。
$ kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes

kube-controller-manager检查服务运行状态
systemctl status kube-controller-manager|grep Active

测试 kube-controller-manager 集群的高可用
停掉一个或两个节点的 kube-controller-manager 服务，观察其它节点的日志，看是否获取了 leader 权限。

查看当前的 leader
$ kubectl get endpoints kube-controller-manager --namespace=kube-system  -o yaml

kube-scheduler检查服务运行状态
systemctl status kube-scheduler|grep Active

查看输出的 metric
注意：以下命令在 kube-scheduler 节点上执行。
kube-scheduler 监听 10251 端口，接收 http 请求：
$ sudo netstat -lnpt|grep kube-sche
tcp        0      0 127.0.0.1:10251         0.0.0.0:*               LISTEN      23783/kube-schedule

$ curl -s http://127.0.0.1:10251/metrics |head

测试 kube-scheduler 集群的高可用
随便找一个或两个 master 节点，停掉 kube-scheduler 服务，看其它节点是否获取了 leader 权限（systemd 日志）。
查看当前的 leader
$ kubectl get endpoints kube-scheduler --namespace=kube-system  -o yaml 


Bootstrap Token Auth 和授予权限

kublet 启动时查找配置的 --kubeletconfig 文件是否存在，如果不存在则使用 --bootstrap-kubeconfig 向 kube-apiserver 发送证书签名请求 (CSR)。

kube-apiserver 收到 CSR 请求后，对其中的 Token 进行认证（事先使用 kubeadm 创建的 token），认证通过后将请求的 user 设置为 system:bootstrap:，group 
设置为 system:bootstrappers，这一过程称为 Bootstrap Token Auth。

默认情况下，这个 user 和 group 没有创建 CSR 的权限，kubelet 启动失败，错误日志如下：
$ sudo journalctl -u kubelet -a |grep -A 2 'certificatesigningrequests'
May 06 06:42:36 m7-autocv-gpu01 kubelet[26986]: F0506 06:42:36.314378   26986 server.go:233] failed to run Kubelet: cannot create certificate signing request: certificatesigningrequests.certificates.k8s.io is forbidden: User "system:bootstrap:lemy40" cannot create certificatesigningrequests.certificates.k8s.io at the cluster scope
May 06 06:42:36 m7-autocv-gpu01 systemd[1]: kubelet.service: Main process exited, code=exited, status=255/n/a
May 06 06:42:36 m7-autocv-gpu01 systemd[1]: kubelet.service: Failed with result 'exit-code'.

解决办法是：创建一个 clusterrolebinding，将 group system:bootstrappers 和 clusterrole system:node-bootstrapper 绑定：
$ kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers



验证kubelet 服务
$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
node-csr-Tk72PEOvNe9rDVFSbldnaDGuzNPfxFcAZXtY2XSXCgA   1m        system:bootstrap:ploqjl   Pending
node-csr-mdqibsv7fdiZ5z5tklMvjh8vpobNFqM3obvXGiaIikI   1m        system:bootstrap:bkalee   Pending

$ kubectl get nodes
No resources found.


手动 approve CSR 请求
$ kubectl certificate approve node-csr-Tk72PEOvNe9rDVFSbldnaDGuzNPfxFcAZXtY2XSXCgA


自动 approve CSR 请求

创建三个 ClusterRoleBinding，分别用于自动 approve client、renew client、renew server 证书：

cat > csr-crb.yaml <<EOF
 # Approve all CSRs for the group "system:bootstrappers"
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: auto-approve-csrs-for-group
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
 # To let a node of the group "system:nodes" renew its own credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-client-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
 # To let a node of the group "system:nodes" renew its own server credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-server-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io
EOF

    auto-approve-csrs-for-group：自动 approve node 的第一次 CSR； 注意第一次 CSR 时，请求的 Group 为 system:bootstrappers；
    node-client-cert-renewal：自动 approve node 后续过期的 client 证书，自动生成的证书 Group 为 system:nodes;
    node-server-cert-renewal：自动 approve node 后续过期的 server 证书，自动生成的证书 Group 为 system:nodes;

生效配置：
$ kubectl apply -f csr-crb.yaml

查看 kublet 的情况

等待一段时间(1-10 分钟)，三个节点的 CSR 都被自动 approved：

$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
node-csr--BjlTzxB5Y4op_6wYlDKbbQj1NtX-IOBMLmWhkupEWA   4m        system:bootstrap:8galm1   Approved,Issued
node-csr-a68FhmUgprTJkaLwnJOLQLOkDQuAviDdBy91ByVtWt0   4m        system:bootstrap:4ef7hj   Approved,Issued
node-csr-a7DI6d0QjBiPh58IBGYFPUKAZvKs6sfbqlnoc22erRs   4m        system:bootstrap:ai162m   Approved,Issued

所有节点均 ready：

$ kubectl get nodes
NAME         STATUS    ROLES     AGE       VERSION
m7-autocv-gpu01   Ready     <none>    1m        v1.11.2
m7-autocv-gpu02   Ready     <none>    1m        v1.11.2
m7-autocv-gpu03   Ready     <none>    1m        v1.11.2

kube-controller-manager 为各 node 生成了 kubeconfig 文件和公私钥：

$ ls -l /etc/kubernetes/kubelet.kubeconfig
-rw------- 1 root root 2311 8月  15 12:20 /etc/kubernetes/kubelet.kubeconfig

$ ls -l /etc/kubernetes/cert/|grep kubelet
-rw------- 1 root root 1281 8月  15 12:20 kubelet-client-2018-08-15-12-20-15.pem
lrwxrwxrwx 1 root root   59 8月  15 12:20 kubelet-client-current.pem -> /etc/kubernetes/cert/kubelet-client-2018-08-15-12-20-15.pem
-rw-r--r-- 1 root root 2213 8月  15 12:16 kubelet.crt
-rw------- 1 root root 1675 8月  15 12:16 kubelet.key
END
