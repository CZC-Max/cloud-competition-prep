# Kubernetes 重建练熟曲线

> 对标：A3 考场任务 = 限时从零搭建 3 master + 1 worker 高可用集群
> 计时起点：4 台 `kubeadm reset` 清空完毕；终点：`kubectl get nodes` 4 行 Ready
> 目标：稳定进入 40 分钟以内，且**不依赖任何排错**

## A3 集群重建

| 轮次 | 日期 | 耗时 | 备注 |
|---|---|---|---|
| 1 | 2026-09-27 | **~19 分钟**（含 4 次排错绕路，秒表丢失后按截图时间戳折算） | 首轮重建。绕路原因见下 |
| 2 | 2026-09-28 | **9.8 分钟**（预检全过，零排错，LastWriteTime 计时） | 🎉 首个干净成绩。目标 40 分钟，已用 1/4 |
| 4 | 2026-09-30 | **39 分 19 秒**（手机计时，含 init 1 次失败 + join 文件重写 + CNI 排障 + 整机重启） | 🧯 史上最难一轮。手敲能力达标：**init 只失败 1 次**（R3 是 4 次），所有 join 一次过 |

## A4 编排四件套（Deployment+Service+Ingress+PVC，2026-10-05 起）

> 计时起点：应用层清空（控制器保留）；终点：四条验收全过
> （Pod Running / svc NodePort / PV+PVC Bound / **控制器端口 + Host 头** curl 通）

| 轮次 | 日期 | 耗时 | 备注 |
|---|---|---|---|
| 1 | 2026-10-05 | **9 分 25 秒**（手机计时） | 🎉 一次通过。两处待改进：①占位符 `<>` 敲进终端（bash 重定向误解析）②curl 误打 web svc 端口而非 ingress 控制器端口——**绕过 Ingress 的成功不算成功** |

> **R3/R4 说明**：这两轮是手敲（考场同条件），且都撞上了"集群级残留状态"问题，
> 耗时不可与 R1/R2（PowerShell 粘贴）横比。**手敲能力本身在快速收敛**：
> init 失败次数 4 → 1，join 全部一次过。
> 下一阶段目标：**手敲 + 无残留状态**条件下稳定 ≤20 分钟。

> 第 3 轮的"实际干净耗时"参考值 ≈ 15 分钟（28 分钟减去 4 次 init 重写、1 次 sed 修错字、约 10 分钟 CNI 排障）。
> 真正的对标目标是：**手敲条件下稳定 ≤20 分钟**，第 4 轮开始计时。

## 第 1 轮踩的绕路（全部已固化为预检清单）

1. **init 前没验 ip_forward** → master1 体检被拦（关机后全员回退）
2. **只修了 master1 没修另外三台** → worker join 同样被拦
3. **join 文件生成时漏带 `--ignore-preflight-errors=Mem`** → master2/3 被 RAM 检查拦
4. **中途换 PowerShell 窗口排错** → `$sw` 秒表变量丢失

## 第 3 轮（手敲版）踩的坑

1. **`=` 两边加空格** → `--pod-network-cidr = 10.244.0.0/16` 被当成两条参数，报 `unknown command`
   - 规则：`--flag=value` 必须**紧贴**，无空格
2. **`--upload-certs` 手敲不顺** → 果断从 init 里删掉（**非必需**，第 5 步单独 `upload-certs` 等价）
3. **`errors` 打成 `erroes`** → `unknown flag`；用 `sed -i 's/erroes/errors/g'` 修
   - 又一次印证"生成的命令必须看尾巴"
4. **flannel 用了 gitee master 分支 yml** → 新版 install-cni 只拷贝 flannel 二进制，
   `/opt/cni/bin` 缺 `bridge`/`portmap`/`host-local` → kubelet 报 `cni plugin not initialized`
   - 修法：`dnf install -y kubernetes-cni`（4 台全装）+ 重启 kubelet
   - **教训：物料要锁版本，master 分支 ≠ 稳定版**
5. **VM 控制台吞符号**（`--` 变 `-`、`|` 变 `!`）→ 长命令和管道用宿主机 ssh 兜底；
   手敲时**敲完先肉眼扫一遍回显再回车**

## 第 4 轮踩的坑（2026-09-30）

1. **init 漏敲 `=`** → `--image-repository.aliyuncs.com/...` 被当一个 flag，报 `unknown flag`
   - 第 3 轮是"`=` 两边有空格"，第 4 轮是"**忘了 `=`**"——同一个零件，两种错法
2. **VM 控制台吞 `>`** → 第 5 步生成 join 文件的重定向没生效，文件里还是**昨天的旧内容**
   （token 没变就是证据）→ worker join 报 `unknown flag: --certificate-key`
   - **规则：文件生成类操作（重定向写文件）一律走宿主机 ssh，控制台只敲短命令和 init**
3. **清空漏了 worker1** → join 时 preflight 报 `kubelet.conf exists` / `Port 10250 in use`
   - 补救：单独 `kubeadm reset -f` + 清目录 + 重启服务，再 join
4. 🔥 **4 节点集体 NotReady，底层全对**（工具箱✓ conflist✓ 网卡✓ flannel Pod✓）→ **整机重启解决**
   - 诊断过程：对照组实验（坏节点 vs 好节点逐项比对配置）→ 配置完全一致 → 排除配置层
   - 真相：**kubeadm 反复 reset/init 会留下跨集群的残留状态**（containerd 旧容器、CNI 缓存），
     日志永远只显示含糊的 `cni plugin not initialized`，**只有整机重启能清干净**
   - ⚠️ 重启后内核参数必回退，**开机先补预检再验收**

### 考场级结论：重启洗牌法

> **当"底层全对但节点就是不 Ready"时，把整机重启作为最后的手术刀。**
> 考场建议给这条留 10 分钟预算——它可能是最后一道保险。

## 经验

1. **预检先行**：重建前先跑 4 台预检（k8s/README.md 第九节），比 init 被拦后排错快得多
   - 实测数据：第 1 轮没预检 = 19 分钟带 4 次绕路；第 2 轮预检先行 = **9.8 分钟零排错**
2. **`modprobe`（装模块）≠ `sysctl -w`（拨开关）** —— 两步缺一不可：只装模块不拨开关，bridge-nf-call-iptables 默认是 0，预检照样不过
3. **生成的命令必须看尾巴**：join 文件生成后，肉眼确认末尾参数齐全（Mem 豁免 / certificate-key 非空）再投递
4. **计时用文件 LastWriteTime**：不用会话变量（换窗即丢），也不读文件内容（`Out-File` UTF-16 编码坑）——`(Get-Item timer.txt).LastWriteTime` 一行搞定
