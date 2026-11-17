import {createRequire} from 'node:module';
const require=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fs=require('node:fs');
const cfg=require('dotenv').parse(fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway/.env'));
for(const k of ['MANAGER_BOT_TOKEN','ADMIN_USER_ID','DEFAULT_PROJECT'])if(cfg[k])process.env[k]=cfg[k];
Object.assign(process.env,{
 TG_AGENT_GATEWAY_REVIEW_MODE:'1',TG_AGENT_GATEWAY_REVIEW_TASK_ID:'task-20261111-005',TG_AGENT_GATEWAY_REVIEW_COMMIT:'1afd011a32496d1e0bded670daf6f65580178385',
 RUNNER_MODE:'mock',TASK_QUEUE_AUTORUN:'false',WEBAPP_PORT:'43005',
 DATABASE_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cc3-1afd011/gateway.sqlite',TASK_MESSAGES_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cc3-1afd011/task-messages.json',LOG_DIR:'/home/zhanxp/.local/share/tg-gateway-reviews/cc3-1afd011/logs'
});
process.chdir('/home/zhanxp/worktrees/tg-agent-gateway/cc3');
await import('/home/zhanxp/worktrees/tg-agent-gateway/cc3/dist/index.js');
