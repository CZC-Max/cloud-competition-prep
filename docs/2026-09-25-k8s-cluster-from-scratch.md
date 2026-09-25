# 从零搭建 Kubernetes 集群（openEuler 24.03 + kubeadm v1.30）

> 世界技能大赛云计算项目备赛 · 实验记录第 3 篇
> 环境：Windows 宿主机 + VMware Workstation，4 台 openEuler 24.03 LTS 虚拟机
> 结果：master1（control-plane）+ worker1 双节点 Ready，flannel 网络插件正常运行

---

## 一、目标

在单机 VMware 环境里搭出一套可复用的 K8S 集群，用于后续练习：
- **A3** K8S 高可用集群搭建（6 分）
- **A4** K8S 编排：Deployment / Service / Ingress / PVC（6 分）
- **B6** K8S 集群故障排除（20 分）—— 分值最高的单项之一，必须有真机可练

---

## 二、环境规划

| 角色 | IP | 配置 | 说明 |
|---|---|---|---|
| master1 | 192.168.184.11 | 2C / 2G / 25G | 控制平面，兼克隆母本 |
| master2 | 192.168.184.12 | 2C / 2G / 25G | 备用 master（HA 待补） |
| master3 | 192.168.184.13 | 2C / 2G / 25G | 备用 master（HA 待补） |
| worker1 | 192.168.184.21 | 2C / 2G / 25G | 工作节点 |

- 网络：VMware NAT（VMnet8），网关 `192.168.184.2`
- 系统镜像：openEuler 24.03 LTS（华为云镜像，3.93 GB）
- **策略：只装 1 台，其余 3 台克隆** —— 省下 3 次装系统时间

---

## 三、过程

### 3.1 母本通用配置（每台节点都需要）

```bash
# 关 swap（kubelet 硬要求）
swapoff -a && sed -i '/swap/d' /etc/fstab

# SELinux 转 permissive
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 关防火墙
systemctl disable --now firewalld

# 内核参数
modprobe overlay && modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf
sysctl --system

# 静态 IP（openEuler 用 nmcli 比 nmtui 更稳）
nmcli con mod ens33 ipv4.method manual ipv4.addresses 192.168.184.11/24 \
  ipv4.gateway 192.168.184.2 ipv4.dns 223.5.5.5
nmcli con up ens33
```

### 3.2 containerd（两处必改，否则 init 必挂）

```bash
dnf install -y containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = .*#sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.9"#' /etc/containerd/config.toml
systemctl enable --now containerd
```

- `SystemdCgroup = true`：cgroup 驱动与 kubelet 对齐，不改则 kubelet 起不来
- `sandbox_image` 换国内源：默认的 `registry.k8s.io` 国内拉不动，init 会卡死在拉镜像

### 3.3 kubeadm 三件套

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

实测版本：**v1.30.14**。

### 3.4 克隆三台（VMware）

右键 master1 → 管理 → 克隆 → 当前状态 → **完整克隆** → 名称/位置各自独立目录。

> 克隆机开机时会弹「我已移动 / 我已复制」——**选「我已复制」**，VMware 会重新生成 UUID 和 MAC，等价于图形界面版的身份重置。

每台克隆后执行「出厂五连」（只差 IP 和主机名）：

```bash
nmcli con mod ens33 ipv4.addresses 192.168.184.12/24
nmcli con up ens33
hostnamectl set-hostname master2
rm -f /etc/machine-id && systemd-machine-id-setup
reboot
```

### 3.5 初始化控制平面

```bash
kubeadm init --pod-network-cidr=10.244.0.0/16 \
  --image-repository registry.aliyuncs.com/google_containers \
  --ignore-preflight-errors=Mem
```

`--ignore-preflight-errors=Mem` 是因为 VM 只有 2G（系统内可用约 1.4G），练习环境放行内存检查。

成功后：

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
kubectl get nodes        # 此时 NotReady —— 没装网络插件，正常
```

### 3.6 网络插件 flannel

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### 3.7 worker 加入（管道投递，零手抄）

```powershell
$join = ssh root@192.168.184.11 "kubeadm token create --print-join-command"
ssh root@192.168.184.21 $join
```

---

## 四、踩过的坑（这部分最值钱）

### 坑 1：VMware 多台虚拟机不能同时开机

**现象**：单开任意一台都正常，开第二台必报「未能启动虚拟机」。

**思路**：查 `vmware.log` 与目录文件，发现 4 台 VM 的文件**全挤在同一个目录**（克隆时位置选了同一个父目录），而每台运行时都要写 `vmware.log`——同名文件被先启动的那台锁住。

**解决**：给每台 VM 分家（各自独立子目录）+ 清理 `.lck` 锁文件夹。
清理锁的前提是 **VMware 完全退出**（含 `vmware-tray` 托盘进程），VM 运行时删锁会损坏数据。

> 通用规律：**一台 VM 一个独立目录**，日志/锁/磁盘才不打架。
> 同类问题在服务端同样成立：两个服务抢同一个日志文件锁，后启动的起不来。

### 坑 2：flannel CrashLoopBackOff —— br_netfilter 没持久化

**现象**：`kubectl get nodes` 里 master1 一直 NotReady，flannel Pod 重启 5 次进入 CrashLoopBackOff。

**思路**：抓日志 `kubectl logs -n kube-flannel <pod>`，末尾一行直接点名：

```
Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory
```

**原因**：`modprobe br_netfilter` 只在**本次运行**生效，机器重启后模块就没了。

**解决**：加载模块 + 写进开机自动加载清单 + 重建 Pod：

```bash
modprobe br_netfilter && modprobe overlay
echo overlay      > /etc/modules-load.d/k8s.conf
echo br_netfilter >> /etc/modules-load.d/k8s.conf
sysctl -p /etc/sysctl.d/k8s.conf
kubectl delete pod -n kube-flannel <pod>    # DaemonSet 会自动重建
```

> 这是 K8S 装机题的**高频失分点**：手动 modprobe 的模块重启即丢。
> 同理适用于 `net.ipv4.ip_forward`——只 `sysctl -w` 不落盘，重启就回原样。

### 坑 3：手敲/手抄长命令必翻车

一天内翻车三次：

1. 行首 `--` 被吞 → `kubeadm: Unknown command`
2. `google_containers` 打成 `goole` → 拉不到镜像
3. 手抄 `--discovery-token-ca-cert-hash` 少抄 1 位 → `hash 必须是 64 位`

**根本解法两条**：

- **SSH 免密**：`ssh-keygen` 生成密钥，公钥投递到 4 台的 `~/.ssh/authorized_keys`，之后从宿主机 PowerShell 整块粘贴执行
- **变量管道**：join 命令让 master1 现场生成、直接管道送给 worker1，不经人手

```powershell
$join = ssh root@192.168.184.11 "kubeadm token create --print-join-command"
ssh root@192.168.184.21 $join
```

### 坑 4（小）：`ping` 通 ≠ TCP 通

openEuler 官方源 `repo.openeuler.org` 在国内被干扰，表现为 `Curl error 7 / 35`（ICMP 能通，TCP 80/443 被重置）。

换华为云镜像一条 sed 解决：

```bash
sed -i 's#http://repo.openeuler.org#https://mirrors.huaweicloud.com/openeuler#g' /etc/yum.repos.d/openEuler.repo
dnf makecache
```

> 排错分层：**能 ping 通不代表能下载**，要单独测 TCP/HTTPS。

---

## 五、经验

1. **克隆前把母本配满，克隆后只改 IP/主机名** —— 装 1 次 = 装 4 次
2. **`--ignore-preflight-errors=Mem`** 是练习环境的合法操作，但要清楚自己放行了什么
3. **节点刚 join 时 NotReady 是正常剧本** —— flannel DaemonSet 要在新节点上起 Pod，等 1~2 分钟
4. **命令先在母本验证成功再克隆**，否则 4 台一起错
5. **每完成一个里程碑就给 VM 拍快照** —— 后面练排障（故意搞坏集群）时，回滚是唯一的底气

---

## 六、下一步

- [ ] master2 / master3 以 `--control-plane` 加入 → 完成 **A3 三 master HA（6 分）**
- [ ] `kubeadm reset` 全清后**计时重搭**，压进 40 分钟（从"会做"到"能限时做出来"）
- [ ] 在集群上刷 Deployment / Service / Ingress / PVC（A4）
- [ ] 主动注入故障并排错（B6，20 分）：kubelet 起不来、flannel 被删、NetworkPolicy 拦截
