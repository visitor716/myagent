#!/usr/bin/env bash
set -euo pipefail
cd /home/zhanxp/projects/tg-agent-gateway-production
export TG_AUTO_REVIEW_ENABLED=false
export TG_AUTO_REVIEW_MAIN_REPO=/home/zhanxp/projects/tg-agent-gateway
export TG_WEBAPP_URL='https://invision-cold-luggage-mine.trycloudflare.com/?commit=1989dfc'
export DATABASE_PATH=/home/zhanxp/projects/tg-agent-gateway/data/gateway.sqlite
export TASK_MESSAGES_PATH=/home/zhanxp/projects/tg-agent-gateway/data/task-messages.json
export TASK_AGENT_EVENT_DIR=/home/zhanxp/projects/tg-agent-gateway/data/task-agent-events
export TASK_DISPLAY_EVENT_DIR=/home/zhanxp/projects/tg-agent-gateway/data/task-events
export TASK_TERMINAL_EVENT_DIR=/home/zhanxp/projects/tg-agent-gateway/data/task-terminal-events
export LOG_DIR=/home/zhanxp/projects/tg-agent-gateway/logs
export WEBAPP_PORT=3000
export HTTPS_PROXY=http://172.31.112.1:4065
export HTTP_PROXY=http://172.31.112.1:4065
export NO_PROXY='localhost,127.0.0.1,::1,.local,*.local,host.docker.internal,gateway.docker.internal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16,172.31.112.1,10.255.255.254,172.18.128.1,2.0.0.1,26.26.26.1,192.168.6.2,192.168.1.4'
export https_proxy=http://172.31.112.1:4065
export http_proxy=http://172.31.112.1:4065
export no_proxy='localhost,127.0.0.1,::1,.local,*.local,host.docker.internal,gateway.docker.internal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16,172.31.112.1,10.255.255.254,172.18.128.1,2.0.0.1,26.26.26.1,192.168.6.2,192.168.1.4'
exec bash scripts/run-with-bounded-log.sh /home/zhanxp/projects/tg-agent-gateway/logs/runtime/gateway.log 5242880 'node dist/index.js'
