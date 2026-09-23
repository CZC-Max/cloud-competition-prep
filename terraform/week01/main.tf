# ============================================================
# W1 地基：VPC + 交换机 + 安全组 + ECS(nginx 双站点) + 数据盘
# 世界技能大赛云计算项目备赛 · 平台：阿里云
#
# 设计要点：
#   1. provider 显式声明 region —— 防止环境变量丢失后 destroy 跑错地域、
#      在云端留下孤儿资源持续计费（2026-09-22 亲身踩坑）
#   2. AK/SK 一律走环境变量，绝不硬编码进代码
#   3. 实例密码走 terraform.tfvars（已被 .gitignore 排除，不入库）
# ============================================================

terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = ">= 1.220.0"
    }
  }
}

# 显式声明 region，不依赖环境变量
provider "alicloud" {
  region = var.region
}

# ---------- 网络 ----------
resource "alicloud_vpc" "vpc" {
  vpc_name   = "wk1-vpc"
  cidr_block = "10.0.0.0/16"
}

resource "alicloud_vswitch" "vswhangzhou" {
  vswitch_name = "wk1-vsw"
  vpc_id       = alicloud_vpc.vpc.id
  cidr_block   = "10.0.1.0/24"
  zone_id      = var.zone_id
}

resource "alicloud_security_group" "sg" {
  security_group_name = "wk1-sg"
  vpc_id              = alicloud_vpc.vpc.id
}

# 安全组规则：SSH / HTTP / HTTPS / 8080 / ICMP
# 训练环境全放开；Jam 演练时会练习收紧成最小权限（只放行必要端口与来源网段）
resource "alicloud_security_group_rule" "ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "22/22"
  security_group_id = alicloud_security_group.sg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "80/80"
  security_group_id = alicloud_security_group.sg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  security_group_id = alicloud_security_group.sg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "icmp" {
  type              = "ingress"
  ip_protocol       = "icmp"
  port_range        = "-1/-1"
  security_group_id = alicloud_security_group.sg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "app8080" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "8080/8080"
  security_group_id = alicloud_security_group.sg.id
  cidr_ip           = "0.0.0.0/0"
}

# ---------- 云主机 ----------
resource "alicloud_instance" "ecs" {
  instance_name   = "wk1-ecs"
  instance_type   = "ecs.t6-c1m2.large" # 2 vCPU / 4 GiB，入门够用且便宜
  image_id        = var.image_id
  security_groups = [alicloud_security_group.sg.id]
  vswitch_id      = alicloud_vswitch.vswhangzhou.id # 可用区由交换机决定，实例无需再写 zone_id
  password        = var.ecs_password

  internet_max_bandwidth_out = 10 # >0 自动分配公网 IP（allocate_public_ip 已废弃，勿用）

  system_disk_category = "cloud_efficiency"
  system_disk_size     = 40

  # 数据盘：在线挂载，加盘不会导致实例重建
  data_disks {
    name     = "wk1-data"
    size     = 40
    category = "cloud_efficiency"
  }

  # 开机自动装 nginx 并起两个站点（80 主站 / 8080 第二站点）
  # 注意：修改 user_data 或 image_id 会触发实例重建，公网 IP 会变
  user_data = base64encode(<<-EOT
    #!/bin/bash
    yum install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "cloud-week-ok by 2026" > /usr/share/nginx/html/index.html
    mkdir -p /usr/share/nginx/html2
    echo "cloud-week5-ok by 2026 (port 8080)" > /usr/share/nginx/html2/index.html
    printf 'server {\n    listen 8080;\n    server_name _;\n    root /usr/share/nginx/html2;\n    index index.html;\n    location / { try_files $uri $uri/ =404; }\n}\n' > /etc/nginx/conf.d/8080.conf
    systemctl restart nginx
  EOT
  )
}

# ---------- 输出 ----------
output "ecs_public_ip" {
  value = alicloud_instance.ecs.public_ip
}

output "ecs_login" {
  value = "ssh root@${alicloud_instance.ecs.public_ip}"
}
