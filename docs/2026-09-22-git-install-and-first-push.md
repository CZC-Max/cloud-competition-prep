# Windows 国内环境从零装 Git 并完成 GitHub 首次推送

> 沿用「现象 → 思路 → 步骤 → 经验」模板。
> 2026-09-22 亲测全流程，从一台没有 git 的 Windows 到代码上 GitHub，约 30 分钟（其中一半时间在跟网络搏斗）。

**环境**：Windows 11 / Clash Verge（本地混合端口 7897）/ 全程免费方案，未买任何服务

---

## 一、目标

在一台全新 Windows 上装好 Git，并把本地 Terraform 备赛仓库首次推送到 GitHub。

## 二、现象（遇到的三个坑）

**坑 1：winget 装 GitHub CLI 报错**

```
执行此命令时发生意外错误
InternetOpenUrl() failed.
0x80072efd : unknown error
```

winget 能找到包信息（`已找到 GitHub CLI [GitHub.cli] 版本 2.101.0`），但下载安装包时连接失败。

**坑 2：照着镜像目录名拼下载链接，404**

访问 `.../git-for-windows/v2.55.0.windows.5/Git-2.55.0-64-bit.exe` → `404 Not Found`。

**坑 3：git push 报连接错误（授权都成功了还报）**

```
fatal: 发送请求时出错。
fatal: 基础连接已经关闭: 接收时发生错误。
fatal: unable to access 'https://github.com/...': Failed to connect to github.com:443
```

浏览器里授权明明显示 `Authentication Succeeded`，推送却连不上。

## 三、思路

1. **坑 1 根因**：winget 的包*元数据*在微软 CDN（能拿到），但安装包*本体*托管在 GitHub Releases，下载时 302 重定向到 `objects.githubusercontent.com`——这个域名国内直连经常被掐。**结论：winget 装 GitHub 系工具在国内基本必挂，直接找国内镜像。**
2. **坑 2 根因**：镜像的**版本目录名**（`v2.55.0.windows.5`）≠ **安装包文件名**。目录名含 `.windows.5` 补丁号，文件名却是 `Git-2.55.0.5-64-bit.exe`（多一个 `.5`）。**结论：先拉目录列表看真实文件名，别猜。**
3. **坑 3 根因**：GFW 对 github.com 的 HTTPS 连接是**概率性干扰**——浏览器授权那一下通了，git 推送的长连接又被掐。浏览器能走系统代理，git 默认不走。**结论：让 git 显式走 Clash 的本地代理，并且只对 github.com 走（不影响访问阿里云等国内服务）。**

## 四、步骤（可复现）

**1. 从国内镜像下载 Git**（华为云镜像，秒下）：

```
https://mirrors.huaweicloud.com/git-for-windows/
```

进最新稳定版目录（如 `v2.55.0.windows.5/`），下载 **`Git-2.55.0.5-64-bit.exe`**（注意文件名从目录列表里抄，别手拼）。备用镜像：`https://registry.npmmirror.com/-/binary/git-for-windows/`

**2. 安装**：一路 Next 默认，PATH 页保持默认的 "Git from the command line and also from 3rd-party software"。装完**重开终端**，`git --version` 验证。

**3. 首次推送的授权**：第一次 `git push` 会弹出 "Connect to GitHub" 窗口 → 点蓝色 **Sign in with your browser** → 浏览器里点绿色授权按钮 → 看到 `Authentication Succeeded`。凭证自动存进 Windows 凭据管理器，以后不再弹。**gh CLI 不是必需品，这一步就是它的全部作用。**

**4. 关键一步：让 git 对 GitHub 走 Clash 代理**（端口看 Clash Verge 设置里的混合端口，默认 7897）：

```powershell
git config --global http.https://github.com/.proxy http://127.0.0.1:7897
git push -u origin main
```

> 注意配置项的写法：`http.https://github.com/.proxy` 表示**只对 github.com 走代理**，
> 推阿里云、拉国内源都不受影响。不要直接 `git config --global http.proxy ...`（全局代理，误伤）。

**5. 验证**：`Writing objects: 100%` → 刷新 GitHub 仓库页，文件全在。

## 五、结果

仓库成功上线，1 commit / 9 files：**https://github.com/CZC-Max/cloud-competition-prep**

GitHub 还会发来一封 "A first-party GitHub OAuth application (Git Credential Manager) ... has been added to your account" 邮件——这是授权成功的官方确认，属正常现象。

## 六、经验

1. **国内装开发工具的第一反应是找镜像**，不是 winget：Git → 华为云/npmmirror；gh 这类只在 GitHub 发的，能不装就不装（GCM 授权等效）
2. **镜像目录名 ≠ 文件名**，先拉列表再下，省一个 404
3. `git config --global http.https://github.com/.proxy` 这个写法值得背——**按站点配代理**，是 Clash 用户管理 git 的正解
4. GFW 干扰是概率性的：**授权成功 ≠ 推送成功**，失败重试 2-3 次本身就是方案的一部分
5. 排错顺序：先分层定位（TCP 通不通 → 是不是只有下载不通 → 是不是只有 git 不通），再换路（winget→镜像，直连→代理），不要在一条死路上反复横跳

---

**清理自查**：本篇不涉及云资源，无需销毁。本仓库不含任何真实凭证。
