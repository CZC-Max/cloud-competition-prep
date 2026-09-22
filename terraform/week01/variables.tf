variable "region" {
  description = "阿里云地域，默认杭州"
  type        = string
  default     = "cn-hangzhou"
}

variable "zone_id" {
  description = "可用区。杭州可用 b/e/f/g/h/i/j/k；建议固定一个，避免跨可用区导致重建"
  type        = string
  default     = "cn-hangzhou-k"
}

variable "image_id" {
  description = "公共镜像 ID，每个地域不同。用 aliyun ecs DescribeImages 查最新"
  type        = string
  default     = "rockylinux_9_8_x64_20G_alibase_20260916.vhd"
}

variable "ecs_password" {
  description = "ECS root 密码，8-30 位且含大小写字母+数字。请在 terraform.tfvars 中填写"
  type        = string
  sensitive   = true
  # 故意不设默认值：强制走 tfvars，避免密码被提交进公开仓库
}
