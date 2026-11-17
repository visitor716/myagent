import {createRequire} from 'node:module';
const require=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fs=require('node:fs');
const cfg=require('dotenv').parse(fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway/.env'));
for(const k of ['MANAGER_BOT_TOKEN','ADMIN_USER_ID','DEFAULT_PROJECT'])if(cfg[k])process.env[k]=cfg[k];
Object.assign(process.env,{
 TG_AGENT_GATEWAY_REVIEW_MODE:'1',TG_AGENT_GATEWAY_REVIEW_TASK_ID:'task-20261111-005',TG_AGENT_GATEWAY_REVIEW_COMMIT:'a5dfa8eeabac889f6ab3752ca19b4c52d5c4f30b',
 RUNNER_MODE:'mock',TASK_QUEUE_AUTORUN:'false',WEBAPP_PORT:'43007',
 DATABASE_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cx3-mobile/gateway.sqlite',TASK_MESSAGES_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/cx3-mobile/task-messages.json',LOG_DIR:'/home/zhanxp/.local/share/tg-gateway-reviews/cx3-mobile/logs'
});
process.chdir('/home/zhanxp/worktrees/tg-agent-gateway/cx3');
await import('/home/zhanxp/worktrees/tg-agent-gateway/cx3/dist/index.js');
