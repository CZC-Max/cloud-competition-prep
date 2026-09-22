# Week 01 · 架构说明

> 世赛评分含「沟通技能 10%」，要求能说清架构设计与取舍。
> 本文件既是训练记录，也是过程分练习 —— 每周搭完都写一份。

## 一、架构拓扑

```
公网用户
   |
   |-- :22   (SSH)
   |-- :80   (HTTP)
   |-- :443  (HTTPS)  ---> 安全组 wk1-sg ---> ECS wk1-ecs
   |-- :8080 (第二站点)                        |-- 系统盘 40G (cloud_efficiency)
   |-- ICMP  (探测)                            |-- 数据盘 40G
                                               |-- 公网 IP，带宽 10M
                                               |
                                          nginx 双站点
                                          :80   -> /usr/share/nginx/html
                                          :8080 -> /usr/share/nginx/html2
                          |
                     VPC 10.0.0.0/16
                          |
                     交换机 10.0.1.0/24 (可用区 cn-hangzhou-k)
```

## 二、资源清单（共 9 个）

| # | 资源类型 | 名称 | 关键规格 |
|---|---|---|---|
| 1 | VPC | wk1-vpc | 网段 10.0.0.0/16 |
| 2 | 交换机 | wk1-vsw | 10.0.1.0/24，可用区 cn-hangzhou-k |
| 3 | 安全组 | wk1-sg | 入方向 5 条规则 |
| 4 | 安全组规则 | ssh | TCP 22/22，来源 0.0.0.0/0 |
| 5 | 安全组规则 | http | TCP 80/80 |
| 6 | 安全组规则 | https | TCP 443/443 |
| 7 | 安全组规则 | icmp | ICMP -1/-1 |
| 8 | 安全组规则 | app8080 | TCP 8080/8080 |
| 9 | ECS 实例 | wk1-ecs | ecs.t6-c1m2.large，系统盘 40G + 数据盘 40G，带宽 10M |

## 三、验收步骤

1. `terraform apply` 完成后，取输出的 `ecs_public_ip`
2. 浏览器访问 `http://<IP>` → 应显示 `cloud-week-ok by 2026`
3. 浏览器访问 `http://<IP>:8080` → 应显示 `cloud-week5-ok by 2026 (port 8080)`
4. `terraform destroy` → 按「三看」复核（见根 README）

## 四、踩过的坑

| 现象 | 原因 | 解法 |
|---|---|---|
| `NotEnoughBalance` 下单失败 | 阿里云后付费要求可用余额 ≥ 100 | 账户常备 ≥ 200 弹药 |
| `destroy` 报 0 destroyed 但资源还在 | provider 没写 region，跑错地域 | 显式声明 `provider { region = var.region }` |
| 改 user_data / image_id 后公网 IP 变了 | 这两项变更会触发实例重建 | 属正常现象；SSH 报指纹变化用 `ssh-keygen -R <IP>` |
| 本地 PowerShell 敲 `curl localhost` 没反应 | PS 的 curl 是 Invoke-WebRequest 别名，localhost 指自己电脑 | 先 SSH 进云主机再 curl |
| Rocky Linux 没有 `lsblk` | 最小化镜像未装 util-linux | 用 `fdisk -l` 或 `cat /proc/partitions` |

## 五、成本提示

按量付费，单次演练约几元。**用完立刻 destroy**，这是训练纪律。
