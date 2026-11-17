import {createRequire} from 'node:module';
const require=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fs=require('node:fs');
const cfg=require('dotenv').parse(fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway/.env'));
for(const k of ['MANAGER_BOT_TOKEN','ADMIN_USER_ID','DEFAULT_PROJECT'])if(cfg[k])process.env[k]=cfg[k];
Object.assign(process.env,{
 TG_AGENT_GATEWAY_REVIEW_MODE:'1',TG_AGENT_GATEWAY_REVIEW_TASK_ID:'task-20261111-005',TG_AGENT_GATEWAY_REVIEW_COMMIT:'e757c3476a8ab75c82ce322128a7476df025cb82',
 TG_AUTO_REVIEW_ENABLED:'false',RUNNER_MODE:'mock',TASK_QUEUE_AUTORUN:'false',WEBAPP_PORT:'43009',
 DATABASE_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cc4-details/gateway.sqlite',TASK_MESSAGES_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cc4-details/task-messages.json',LOG_DIR:'/home/zhanxp/.local/share/tg-gateway-reviews/cc4-details/logs'
});
process.chdir('/home/zhanxp/worktrees/tg-agent-gateway/cx5');
await import('/home/zhanxp/worktrees/tg-agent-gateway/cx5/dist/index.js');
