# Kubernetes 重建练熟曲线

> 对标：A3 考场任务 = 限时从零搭建 3 master + 1 worker 高可用集群
> 计时起点：4 台 `kubeadm reset` 清空完毕；终点：`kubectl get nodes` 4 行 Ready
> 目标：稳定进入 40 分钟以内，且**不依赖任何排错**

| 轮次 | 日期 | 耗时 | 备注 |
|---|---|---|---|
| 1 | 2026-09-27 | **~19 分钟**（含 4 次排错绕路，秒表丢失后按截图时间戳折算） | 首轮重建。绕路原因见下 |
| 2 | 2026-09-28 | **9.8 分钟**（预检全过，零排错，LastWriteTime 计时） | 🎉 首个干净成绩。目标 40 分钟，已用 1/4 |
| 3 | 2026-09-29 | **28 分钟**（手机计时，含 init 手敲 4 次尝试 + 错字修复 + CNI 工具箱排障） | ⚠️ **难度不同，不与前两轮横比**：全程 VM 控制台手敲、零粘贴 |

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

## 经验

1. **预检先行**：重建前先跑 4 台预检（k8s/README.md 第九节），比 init 被拦后排错快得多
   - 实测数据：第 1 轮没预检 = 19 分钟带 4 次绕路；第 2 轮预检先行 = **9.8 分钟零排错**
2. **`modprobe`（装模块）≠ `sysctl -w`（拨开关）** —— 两步缺一不可：只装模块不拨开关，bridge-nf-call-iptables 默认是 0，预检照样不过
3. **生成的命令必须看尾巴**：join 文件生成后，肉眼确认末尾参数齐全（Mem 豁免 / certificate-key 非空）再投递
4. **计时用文件 LastWriteTime**：不用会话变量（换窗即丢），也不读文件内容（`Out-File` UTF-16 编码坑）——`(Get-Item timer.txt).LastWriteTime` 一行搞定
