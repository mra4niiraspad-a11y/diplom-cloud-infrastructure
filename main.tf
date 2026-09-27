terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.88"
    }
  }
}

# ==========================================
# ПЕРЕМЕННЫЕ
# ==========================================

variable "folder_id" {
  type        = string
  description = "ID папки Yandex Cloud"
}

variable "yc_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "cloud_id" {
  type    = string
  default = ""
}

variable "ssh_pub_key" {
  type    = string
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCsrc0ahd0+bc94u3Rjagkwbp0zrb4PjgxSyRzveTvDbln32VDtAR7Dn7FxqFS9cti8HdiNvzUPiz9KHKTa08gi84q7/2cwAev4nvph/ioFOTBcF5w5a+QgBrUEJDTURqpFqrG9QwuWzY1ZQq4VNQHVzJ2wsY0uOXTmWfGS2twQiZwescVZ3rKsduFkmADq10vBurD0jMgnWHxZEL8hkb+pXns6NFN1HFdOKOXpk1VscIfx6pP9QgIUAQsy6H2129n4otWWjpoxm/5wJwRQE1mkal/3WhcNXstoLF474T50AlPmDCgp+HiZd+9xwuHb7nqXFZF5HI09vtu28Kd18vsZz6zrRTxGs0/o4bENIfCgwbxvlhajvA7rwC2lMVxv8SUSa9uZ3IifAwh0aTdlISb2sLiZ7gg7CSJu8+FaAwRzbgpmmRSMS406P6N86tRqXHnxFxItTa0bcz5zUtfGaUveo1cpx7lrQA3goCubiLpOQhpdC/TUpCl/WUsHw01TlMyZepJhaRqm9kqtDk8AVXhwXO03HuTf90XUUclJ08wpBwZQPs1uMErItEBRAxd/woJZctVjZ486tlpvD2ChCc9H9/xS++MHMb+f7o5enpITgO5QpzhKr2Wb4ZSkIw1Dx3T08OdYSmSQRapDZd8in3zWcR/qlUUx4lLV9RdvOVMO7Q== last@ubu"
}

provider "yandex" {
  folder_id = var.folder_id
  cloud_id  = var.cloud_id != "" ? var.cloud_id : null
}

# ==========================================
# СЕТЬ — VPC
# ==========================================

resource "yandex_vpc_network" "diploma_net" {
  name = "diploma-network"
}

# Публичная подсеть — зона A (bastion, zabbix, kibana, ALB)
resource "yandex_vpc_subnet" "public_a" {
  name           = "public-a"
  network_id     = yandex_vpc_network.diploma_net.id
  zone           = "ru-central1-a"
  v4_cidr_blocks = ["10.10.1.0/24"]
}

# Публичная подсеть — зона B (ALB для двух зон)
resource "yandex_vpc_subnet" "public_b" {
  name           = "public-b"
  network_id     = yandex_vpc_network.diploma_net.id
  zone           = "ru-central1-b"
  v4_cidr_blocks = ["10.10.2.0/24"]
}

# Приватная подсеть — зона A (web-1, elasticsearch)
resource "yandex_vpc_subnet" "private_a" {
  name           = "private-a"
  network_id     = yandex_vpc_network.diploma_net.id
  zone           = "ru-central1-a"
  v4_cidr_blocks = ["10.10.3.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# Приватная подсеть — зона B (web-2)
resource "yandex_vpc_subnet" "private_b" {
  name           = "private-b"
  network_id     = yandex_vpc_network.diploma_net.id
  zone           = "ru-central1-b"
  v4_cidr_blocks = ["10.10.4.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# NAT-шлюз для исходящего трафика из приватных подсетей
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "diploma-nat-gateway"
  shared_egress_gateway {}
}

# Таблица маршрутизации для приватных подсетей
resource "yandex_vpc_route_table" "private_rt" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.diploma_net.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

# ==========================================
# SECURITY GROUPS
# ==========================================

# SG для бастиона — только SSH
resource "yandex_vpc_security_group" "sg_bastion" {
  name       = "sg-bastion"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для ALB — HTTP из интернета
resource "yandex_vpc_security_group" "sg_alb" {
  name       = "sg-alb"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "HTTP from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для веб-серверов
resource "yandex_vpc_security_group" "sg_web" {
  name       = "sg-web"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "HTTP from internal network"
    v4_cidr_blocks = ["10.10.0.0/16"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH from bastion"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix agent"
    v4_cidr_blocks = ["10.10.0.0/16"]
    port           = 10050
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для Zabbix
resource "yandex_vpc_security_group" "sg_zabbix" {
  name       = "sg-zabbix"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "Zabbix web HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix web HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix trapper from internal"
    v4_cidr_blocks = ["10.10.0.0/16"]
    port           = 10051
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH from bastion"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для Elasticsearch
resource "yandex_vpc_security_group" "sg_elasticsearch" {
  name       = "sg-elasticsearch"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "Elasticsearch from internal"
    v4_cidr_blocks = ["10.10.0.0/16"]
    port           = 9200
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH from bastion"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix agent"
    v4_cidr_blocks = ["10.10.0.0/16"]
    port           = 10050
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для Kibana
resource "yandex_vpc_security_group" "sg_kibana" {
  name       = "sg-kibana"
  network_id = yandex_vpc_network.diploma_net.id

  ingress {
    protocol       = "TCP"
    description    = "Kibana web"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH from bastion"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# ВИРТУАЛЬНЫЕ МАШИНЫ
# ==========================================

# Bastion host
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  hostname    = "bastion"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 10
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_bastion.id]
  }
}

# Web-сервер 1 — зона A
resource "yandex_compute_instance" "web_1" {
  name        = "web-1"
  hostname    = "web-1"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 10
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_web.id]
  }
}

# Web-сервер 2 — зона B
resource "yandex_compute_instance" "web_2" {
  name        = "web-2"
  hostname    = "web-2"
  platform_id = "standard-v3"
  zone        = "ru-central1-b"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 10
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_b.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_web.id]
  }
}

# Zabbix server
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  hostname    = "zabbix"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 20
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_zabbix.id]
  }
}

# Elasticsearch
resource "yandex_compute_instance" "elasticsearch" {
  name        = "elasticsearch"
  hostname    = "elasticsearch"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 20
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_elasticsearch.id]
  }
}

# Kibana
resource "yandex_compute_instance" "kibana" {
  name        = "kibana"
  hostname    = "kibana"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8c21mmbvs6akc3mnos"
      type     = "network-hdd"
      size     = 10
    }
    auto_delete = true
  }

  scheduling_policy { preemptible = true }
  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_pub_key}"
    serial-port-enable = "1"
    user-data = <<-EOF
#cloud-config
runcmd:
  - ufw disable
  - iptables -F
  - systemctl restart ssh
EOF
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_kibana.id]
  }
}

# ==========================================
# APPLICATION LOAD BALANCER
# ==========================================

# Target Group
resource "yandex_alb_target_group" "web_tg" {
  name = "web-target-group"

  target {
    subnet_id  = yandex_vpc_subnet.private_a.id
    ip_address = yandex_compute_instance.web_1.network_interface[0].ip_address
  }

  target {
    subnet_id  = yandex_vpc_subnet.private_b.id
    ip_address = yandex_compute_instance.web_2.network_interface[0].ip_address
  }
}

# Backend Group
resource "yandex_alb_backend_group" "web_bg" {
  name = "web-backend-group"

  http_backend {
    name             = "web-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web_tg.id]

    healthcheck {
      timeout  = "10s"
      interval = "2s"

      http_healthcheck {
        path = "/"
      }
    }
  }
}

# HTTP Router
resource "yandex_alb_http_router" "web_router" {
  name = "web-http-router"
}

resource "yandex_alb_virtual_host" "web_vhost" {
  name           = "web-virtual-host"
  http_router_id = yandex_alb_http_router.web_router.id

  route {
    name = "web-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web_bg.id
      }
    }
  }
}

# Application Load Balancer
resource "yandex_alb_load_balancer" "web_alb" {
  name        = "web-load-balancer"
  network_id  = yandex_vpc_network.diploma_net.id

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public_a.id
    }
    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.public_b.id
    }
  }

  listener {
    name = "http-listener"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }

    http {
      handler {
        http_router_id = yandex_alb_http_router.web_router.id
      }
    }
  }

  security_group_ids = [yandex_vpc_security_group.sg_alb.id]
}

# ==========================================
# СНАПШОТЫ — ежедневно, retention 7 дней
# ==========================================

resource "yandex_compute_snapshot_schedule" "daily_backup" {
  name = "daily-snapshot-schedule"

  schedule_policy {
    expression = "0 2 * * *"
  }

  snapshot_spec {
    description = "Daily automated snapshot"
  }

  retention_period = "168h"

  disk_ids = [
    yandex_compute_instance.bastion.boot_disk[0].disk_id,
    yandex_compute_instance.web_1.boot_disk[0].disk_id,
    yandex_compute_instance.web_2.boot_disk[0].disk_id,
    yandex_compute_instance.zabbix.boot_disk[0].disk_id,
    yandex_compute_instance.elasticsearch.boot_disk[0].disk_id,
    yandex_compute_instance.kibana.boot_disk[0].disk_id,
  ]
}

# ==========================================
# OUTPUTS
# ==========================================

output "bastion_public_ip" {
  value = yandex_compute_instance.bastion.network_interface[0].nat_ip_address
}

output "alb_public_ip" {
  value = yandex_alb_load_balancer.web_alb.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}

output "zabbix_public_ip" {
  value = yandex_compute_instance.zabbix.network_interface[0].nat_ip_address
}

output "kibana_public_ip" {
  value = yandex_compute_instance.kibana.network_interface[0].nat_ip_address
}

output "web1_fqdn" {
  value = "web-1.ru-central1.internal"
}

output "web2_fqdn" {
  value = "web-2.ru-central1.internal"
}
