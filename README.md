# cloud-competition-prep

> 世界技能大赛「云计算」项目备赛仓库 · 福建省第二届职业技能大赛（个人赛 · 10 小时 / 100 分）
> 从零到省赛的完整训练存档：Terraform IaC 模板、Kubernetes / CEPH / OpenStack 实操、故障复现与排查、架构说明。

> **2026-09-24 方向校正**：拿到赛项官方技术工作文件后确认，考核平台为
> **私有云栈（openEuler + OpenStack + Kubernetes + CEPH）**，而非此前假设的阿里云公有云。
> 阿里云相关内容（terraform/week01）保留为存档，训练重心已转向私有云。
> 分值权重：**K8S 32 > CEPH 18 > OpenStack 16 > 中间件 / Linux 34**。

## 这是什么

我（泉州华光职业学院 · 云计算方向）正在备战 **福建省第二届职业技能大赛「云计算」赛项**
（世界技能大赛选拔项目，个人赛，实操平台为阿里云，比赛窗口 2026-10-30 ~ 11-22）。

这个仓库把整个备赛过程**当作作品来沉淀**——每周的 IaC 模板、排错记录、加固脚本都提交进来。
它同时承担三个目的：

1. **备赛弹药库** —— 比赛时可复用的 Terraform 模板与运维脚本
2. **过程分练习** —— 世赛评分含「工作组织管理 10% + 沟通技能 10%」，写架构说明与代码注释本身就是得分项
3. **个人作品集** —— 云安全方向的真实能力证明（抵消学历短板的最强杠杆）

## 目录结构

```
.
├── terraform/          # IaC 模板（阿里云阶段，已归档为历史）
│   └── week01/         # VPC + 交换机 + 安全组 + ECS + 数据盘 + 双站点服务
├── k8s/                # 私有云阶段：Kubernetes 集群搭建与编排（持续补充）
├── scripts/            # 加固脚本、故障复现脚本、巡检脚本
├── docs/               # 实验记录（现象 → 思路 → 步骤 → 经验）
└── README.md
```

## 快速开始

**前置条件**

- Terraform >= 1.0（[官方下载](https://developer.hashicorp.com/terraform/downloads)）
- 阿里云账号 + **RAM 子账号** AK/SK（最小权限，绝不用主账号 AK）
- 账号可用余额 >= 100 元（后付费门槛；变配、加盘等二次下单会瞬间踩线）

**跑一遍 W1**

```bash
git clone <this-repo>
cd cloud-competition-prep/terraform/week01

# 1. 凭证走环境变量，绝不写进代码
export ALICLOUD_ACCESS_KEY="<your-ak>"
export ALICLOUD_SECRET_KEY="<your-sk>"
export ALICLOUD_REGION="cn-hangzhou"

# 2. 填实例密码（tfvars 已被 gitignore，不会入库）
cp terraform.tfvars.example terraform.tfvars

# 3. 建资源
terraform init
terraform plan        # 确认显示 "9 to add"
terraform apply

# 4. 用完立刻销毁，钱只在练的时候花
terraform destroy
```

浏览器打开输出里的公网 IP，应看到 `:80` 与 `:8080` 两个不同页面。

## ⚠️ 销毁后三看（血泪教训）

`terraform destroy` 报 `Resources: 0 destroyed` **不等于真删干净了**。
曾经因为 provider 没写 region、`destroy` 跑错地域，云端留下 9 个孤儿资源持续计费。
每次销毁后必须核对三点：

1. **销毁前** `terraform plan -destroy` —— 显示的资源数必须等于你建的数（如 9），不是 0
2. **销毁后** `terraform state list` —— 必须返回空，无残留账本
3. **控制台复核** —— ECS / VPC 页面确认实例、安全组真的消失

> 所有模板已强制显式声明 `provider "alicloud" { region = var.region }`，
> region 写死进代码，不再依赖环境变量。

## 顺手发布三步

练完一个模块，顺手提交，不额外花时间：

```bash
git add .
git commit -m "week01: <这周做了什么>"
git push
```

## 进度看板

### 阿里云阶段（已归档）

| 周 | 主题 | 状态 |
|---|---|---|
| W1 | Terraform 上手 + 七件套地基，练熟曲线 40min → 2.1min | ✅ 已归档 |
| W2 ~ W6 | 公私子网 / NAT / RDS / SLB / Jam 专项 | ⏸ 暂停（赛项平台为私有云，非阿里云） |

### 私有云阶段（当前主线，距比赛约 5 周）

| 周 | 主题 | 状态 |
|---|---|---|
| W1 | **Kubernetes 集群**：4 节点环境 + kubeadm init + flannel + worker join | 🟡 进行中（双节点 Ready，HA 待补） |
| W2 | K8S 编排：Deployment / Service / Ingress / StatefulSet / PVC | ⬜ 待开始 |
| W3 | CEPH：cephadm 部署 + RBD / CephFS + OSD / MON 故障恢复 | ⬜ 待开始 |
| W4 | OpenStack 深化：运维 + 故障排查 | ⬜ 待开始 |
| W5 | libvirt / NFS / Keepalived / Go / 中间件补齐 + 全真模拟 | ⬜ 待开始 |
| W6 | 赛前：默写命令卡 + 限时演练 | ⬜ 待开始 |

### 实验记录

| 日期 | 标题 |
|---|---|
| 2026-09-22 | [Windows 国内环境从零装 Git 并完成 GitHub 首次推送](./docs/2026-09-22-git-install-and-first-push.md) |
| 2026-09-23 | [W1 第 1 轮：Terraform 全生命周期闭环](./docs/2026-09-23-w1-round1-full-cycle.md) |
| 2026-09-24 | [W1 练熟曲线表](./docs/w1-rounds.md) |
| 2026-09-25 | [从零搭建 Kubernetes 集群（openEuler + kubeadm）](./docs/2026-09-25-k8s-cluster-from-scratch.md) |

## 安全声明

- 本仓库**不含任何真实 AK/SK、密码、私钥**；`.tfvars` 与 `.tfstate` 已被 `.gitignore` 排除
- 所有演练均在**个人训练账号**内进行，用完即销毁
- 涉及安全的脚本仅用于**自有或明确授权**的环境（靶场 / 实验账号 / CVE 复现）

## 许可

[MIT](./LICENSE)
