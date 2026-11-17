import {createRequire} from 'node:module';
const require=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fs=require('node:fs');
const cfg=require('dotenv').parse(fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway/.env'));
for(const k of ['MANAGER_BOT_TOKEN','ADMIN_USER_ID','DEFAULT_PROJECT'])if(cfg[k])process.env[k]=cfg[k];
Object.assign(process.env,{
 DOTENV_CONFIG_PATH:'/dev/null',TG_AGENT_GATEWAY_REVIEW_MODE:'1',TG_AGENT_GATEWAY_REVIEW_TASK_ID:'agy-exec-stream-20261114',TG_AGENT_GATEWAY_REVIEW_COMMIT:require('node:child_process').execFileSync('git',['-C','/home/zhanxp/worktrees/tg-agent-gateway/agy-exec-stream-20261114','rev-parse','HEAD'],{encoding:'utf8'}).trim(),
 DATA_DIR:'/home/zhanxp/.local/share/tg-gateway-reviews/agy-exec-stream-20261114',TG_AUTO_REVIEW_ENABLED:'false',RUNNER_MODE:'mock',TASK_QUEUE_AUTORUN:'false',WEBAPP_PORT:'43131',
 DATABASE_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/agy-exec-stream-20261114/gateway.sqlite',TASK_MESSAGES_PATH:'/home/zhanxp/.local/share/tg-gateway-reviews/agy-exec-stream-20261114/task-messages.json',LOG_DIR:'/home/zhanxp/.local/share/tg-gateway-reviews/agy-exec-stream-20261114/logs'
});
process.chdir('/home/zhanxp/worktrees/tg-agent-gateway/agy-exec-stream-20261114');
await import('/home/zhanxp/worktrees/tg-agent-gateway/agy-exec-stream-20261114/dist/index.js');
