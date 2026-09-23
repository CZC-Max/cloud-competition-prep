# W1 第 1 轮：Terraform 全生命周期闭环（建 → 验 → 毁 → 三看）

> 沿用「现象 → 思路 → 步骤 → 经验」模板。
> 2026-09-23 ｜ W1 重复练熟周 · 第 1 轮（慢练，对照命令卡）｜ 耗时约 40 分钟

**环境**：阿里云 cn-hangzhou-k / Terraform + alicloud provider v1.293.0 / Windows PowerShell

---

## 一、目标

从零拉起 W1 七件套（9 个资源），浏览器验证 80/8080 双站点，最后干净销毁归零。
本轮目的：把「plan 数字校验 → apply → 验证 → destroy 三看」整条链路练成肌肉记忆。

## 二、现象（本轮遇到的两个新东西）

**1. PowerShell 找不到 terraform（工具明明在 system32 里）**

```
terraform : 无法将"terraform"项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
```

但 `C:\Windows\system32\terraform.exe` 确实存在，机器 PATH 也正常。

**2. 连跑两次 `terraform apply`，第二次显示**

```
No changes. Your infrastructure matches the configuration.
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

## 三、思路

1. **坑 1 根因**：该 PowerShell 是 **32 位进程**。Windows 的文件系统重定向会把 32 位进程对
   `C:\Windows\system32` 的访问重定向到 `C:\Windows\SysWOW64`——而 terraform.exe 只在真正的
   system32 里。**结论：工具别塞 system32，放一个自建目录（如 `C:\Tools`，已在用户 PATH），
   32/64 位窗口通吃。**
2. **现象 2 不是 bug，是特性**：Terraform 是**幂等**的——资源已存在且与配置一致时，
   重复 apply 不会重建，只报告 "No changes"。考场里不确定资源建没建过时，
   **放心重跑 apply，不会产生重复资源**。

## 四、步骤（可复现）

```powershell
# 1. 校验凭证已随环境变量带入本窗口（LTAI 开头的是 AK ID）
$env:ALICLOUD_ACCESS_KEY

# 2. 预演：最后一行必须是 Plan: 9 to add（1 VPC + 1 交换机 + 1 安全组 + 5 规则 + 1 ECS）
terraform plan

# 3. 真建（输 yes）
terraform apply

# 4. 浏览器验证双端口
#    http://<IP>      -> cloud-week-ok by 2026
#    http://<IP>:8080 -> cloud-week5-ok by 2026 (port 8080)

# 5. 销毁三看
terraform plan -destroy    # ① 必须显示 9 to destroy（数量=建成数，绝不能是 0）
terraform destroy          # 输 yes
terraform state list       # ② 必须返回空
# ③ 控制台复核 ECS/VPC 页面 0 资源
```

## 五、结果

| 环节 | 结果 |
|---|---|
| `plan` | ✅ 9 to add（网段 10.0.0.0/16→10.0.1.0/24，可用区 cn-hangzhou-k） |
| `apply` | ✅ 9 added，公网 IP 47.111.4.124 |
| 二次 apply | ✅ No changes（幂等性验证） |
| `destroy` | ✅ 9 destroyed |
| `state list` | ✅ 空，无残留账本 |
| 控制台 | ✅ 0 资源 |

## 六、经验

1. **工具永远放自建目录**（如 `C:\Tools`），不放 system32——32/64 位 PowerShell 对 system32
   的解析不同，塞 system32 迟早出"明明在却找不到"的灵异问题
2. **Terraform 幂等性**：重复 apply → `No changes`，考场不确定就重跑，不会重复建
3. **plan 的数字是开工前合同**：`9 to add` 对应 `9 to destroy`，数字对不上就停手排查，
   这是最便宜的纠错点（还没花钱）
4. **provider 显式声明 region** 是三看能对上数的前提——本轮全程无孤儿资源，
   上次的事故链（丢环境变量 → 跑错地域 → 假销毁）已通过模板修复闭环

---

**清理自查**：destroy 三看全部通过，无残留资源。本篇不含任何凭证。
