# Kubernetes 集群（备赛训练环境）

> 用途：为 **A3 集群搭建（6 分）**、**A4 编排（6 分）**、**B6 集群故障排除（20 分）** 提供可反复练习的真机环境。
> 详细过程见 [实验记录：从零搭建 Kubernetes 集群](../docs/2026-09-25-k8s-cluster-from-scratch.md)

## 拓扑

| 角色 | IP | 配置 |
|---|---|---|
| master1 | 192.168.184.11 | 2C / 2G / 25G |
| master2 | 192.168.184.12 | 2C / 2G / 25G |
| master3 | 192.168.184.13 | 2C / 2G / 25G |
| worker1 | 192.168.184.21 | 2C / 2G / 25G |

系统：openEuler 24.03 LTS ｜ 网络：VMware NAT（VMnet8，网关 192.168.184.2）
版本：kubeadm / kubelet / kubectl v1.30.14 ｜ CNI：flannel（Pod 网段 10.244.0.0/16）

## 一、母本通用配置（每台都要）

```bash
swapoff -a && sed -i '/swap/d' /etc/fstab
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
systemctl disable --now firewalld
```

## 二、内核模块（必须持久化，否则重启后 flannel 崩溃）

```bash
modprobe overlay && modprobe br_netfilter
echo overlay      > /etc/modules-load.d/k8s.conf
echo br_netfilter >> /etc/modules-load.d/k8s.conf
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf
sysctl --system
```

> ⚠️ 只 `modprobe` 不写 `/etc/modules-load.d/`，重启后模块丢失，
> flannel 会报 `Failed to check br_netfilter` 并进入 CrashLoopBackOff。

## 三、containerd

```bash
dnf install -y containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = .*#sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.9"#' /etc/containerd/config.toml
systemctl enable --now containerd
```

## 四、kubeadm 三件套（阿里云镜像源）

```bash
echo [kubernetes] > /etc/yum.repos.d/kubernetes.repo
echo name=Kubernetes >> /etc/yum.repos.d/kubernetes.repo
echo baseurl=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.30/rpm/ >> /etc/yum.repos.d/kubernetes.repo
echo enabled=1 >> /etc/yum.repos.d/kubernetes.repo
echo gpgcheck=1 >> /etc/yum.repos.d/kubernetes.repo
echo gpgkey=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.30/rpm/repodata/repomd.xml.key >> /etc/yum.repos.d/kubernetes.repo
dnf makecache
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet
```

## 五、初始化控制平面

```bash
kubeadm init --pod-network-cidr=10.244.0.0/16 \
  --image-repository registry.aliyuncs.com/google_containers \
  --ignore-preflight-errors=Mem

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

## 六、节点加入（管道投递，避免手抄 hash 出错）

```powershell
$join = ssh root@192.168.184.11 "kubeadm token create --print-join-command"
ssh root@192.168.184.21 $join
```

## 六-B、控制平面加入（三 master HA）

> ⚠️ **init 的那一刻就要带 `--control-plane-endpoint`**（指向将来的 VIP，如 192.168.184.100:6443）。
> 事后补救可以，但若题目要求 VIP 则需重签证书——开头定对才是拿分姿势。

**坑 1：没配 controlPlaneEndpoint 时，`join --control-plane` 直接被拒：**

```
unable to add a new control plane instance to a cluster
that doesn't have a stable controlPlaneEndpoint
```

补救（在 master1 上把 endpoint 补进 kubeadm-config）：

```bash
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > /root/cc.yaml
sed -i '1i controlPlaneEndpoint: 192.168.184.11:6443' /root/cc.yaml
kubeadm init phase upload-config kubeadm --config /root/cc.yaml
kubectl -n kube-system get cm kubeadm-config -o yaml | grep controlPlaneEndpoint
```

**坑 2：跨层取证书密钥，别用 awk**（PowerShell→bash→awk 三层引号会绞碎它，`$KEY` 变空）。
用无引号的 grep 模式 + 空值校验：

```bash
KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | grep -Eo "[0-9a-f]{64}" | head -1)
[ -z "$KEY" ] && echo KEY_EMPTY && exit 1
kubeadm token create --print-join-command | \
  sed "s#$# --control-plane --certificate-key $KEY#" > /root/join-cp.sh
```

然后逐台（**不要同时**，etcd 加成员要串行）：

```powershell
$cp = ssh root@192.168.184.11 "cat /root/join-cp.sh"
ssh root@192.168.184.12 $cp
ssh root@192.168.184.13 $cp
```

验收：`kubectl get nodes` 4 行 Ready（3 control-plane + 1 worker）；
`kubectl get pod -n kube-system | grep etcd` **3 个** etcd 全 Running。
新 control-plane 刚加入时 NotReady 1~2 分钟属正常（flannel 自动铺过去）。

## 七、克隆机出厂五连（每台克隆后必做）

```bash
nmcli con mod ens33 ipv4.addresses 192.168.184.12/24
nmcli con up ens33
hostnamectl set-hostname master2
rm -f /etc/machine-id && systemd-machine-id-setup
reboot
```

> 不重置 machine-id 会导致 DHCP 撞 IP、证书互顶、join 失败。

## 八、重置重来（练熟曲线的计时起点）

```bash
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd ~/.kube
systemctl restart containerd kubelet
```
