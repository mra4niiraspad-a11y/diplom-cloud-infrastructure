# Дипломный проект: инфраструктура в Yandex Cloud

## Архитектура

- **2 веб-сервера** (Nginx + статический сайт) — web-1, web-2
- **Elasticsearch** — сбор и хранение логов
- **Kibana** — визуализация логов
- **Zabbix Server + Agents** — мониторинг всех хостов
- **Bastion** — jump host для доступа по SSH
- **Application Load Balancer** — балансировка трафика на web-1 и web-2
- **Snapshot schedules** — резервное копирование дисков ВМ

## Сеть

- VPC с подсетями в зонах ru-central1-a и ru-central1-b
- ВМ в приватных подсетях, доступ через bastion (ProxyJump)
- ALB направляет HTTP-трафик (порт 80) на целевую группу из web-1 и web-2

## Мониторинг (USE)

- **Utilization** — CPU, RAM, диск, сеть (шаблон "Linux by Zabbix agent")
- **Saturation** — CPU load, disk I/O (там же)
- **Errors** — сетевые ошибки, проблемы диска (там же)
- **HTTP** — Nginx-метрики (шаблон "Nginx by Zabbix agent" на web-1, web-2)
- Триггеры настроены на всех 6 хостах

## Логи

- Elasticsearch + Kibana (ELK)
- Web-серверы отправляют Nginx-логи в Elasticsearch
- Kibana доступна на порту 5601

## Резервное копирование

- Snapshot schedules на диски всех ВМ
- Ежедневные снимки, retention 7 дней

## IaC

- **Terraform** — `main.tf` (инфраструктура: ВМ, сеть, ALB, snapshots)
- **Ansible** — `ansible/` (playbooks для настройки Nginx, ELK, Zabbix)

## Структура репозитория


├── main.tf # Terraform- манифест ├── ansible/ │ ├── ansible.cfg # Ansible config │ ├── inventory.ini # Inventory с FQDN и ProxyJump │ ├── web.yml # Nginx + статический сайт │ ├── elasticsearch.yml # Установка Elasticsearch │ ├── kibana.yml # Установка Kibana │ ├── zabbix_server.yml # Установка Zabbix Server │ └── zabbix_agent.yml # Установка Zabbix Agent на все хосты ├── lb-base.json # Конфигурация ALB ├── listener-config.json # Конфигурация listener └── id_ed25519.pub # Публичный SSH-ключ




## Компромиссы

- Secrets в `terraform.tfvars` (в .gitignore) — не в CI/CD, а локально
- Bastion без failover — single point of failure для SSH-доступа
- ALB в одной зоне с двумя подсетями — частичная отказоустойчивость
- Snapshot schedules вместо полноценного backup-решения
