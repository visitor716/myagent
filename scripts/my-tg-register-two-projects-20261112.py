from pathlib import Path
import json,os,sqlite3,subprocess,time,signal,shlex
root=Path('/home/zhanxp/projects/tg-agent-gateway')
production=Path('/home/zhanxp/projects/tg-agent-gateway-production')
backup=Path('/home/zhanxp/backups/tg-agent-gateway/project-registry-20261112-145437')
pid=2924925
assert Path(os.readlink(f'/proc/{pid}/cwd')).resolve()==production.resolve(), 'runtime cwd changed'
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2]==[b'node',b'dist/index.js'], 'runtime command changed'
c=sqlite3.connect('file:'+str(root/'data/gateway.sqlite')+'?mode=ro',uri=True)
assert not c.execute("select id from tasks where status in ('running','processing')").fetchall(), 'active tasks; do not restart'
c.close()
config=root/'data/repositories.json'
assert config.read_bytes()==(backup/'repositories.json').read_bytes(), 'registry changed concurrently'
candidate=Path('/home/zhanxp/worktrees/tg-agent-gateway/register-github-projects-20261112/data/repositories.json')
data=json.loads(candidate.read_text())
assert set(data['repositories'])-set(json.loads(config.read_text())['repositories'])=={'neocd-android','calibration-precision-tool'}
menu=json.loads((backup/'current-menu.json').read_text())
launcher=Path('/home/zhanxp/projects/myagent/scripts/my-tg-gateway-project-registry-launch-20261112.sh')
lines=Path('/home/zhanxp/projects/myagent/scripts/my-tg-gateway-master-release-launch.sh').read_text().splitlines()
lines=[('export TG_WEBAPP_URL='+shlex.quote(menu['web_app']['url'])) if line.startswith('export TG_WEBAPP_URL=') else line for line in lines]
launcher.write_text('\n'.join(lines)+'\n')
launcher.chmod(0o700)
tmp=config.with_name('repositories.json.pending')
tmp.write_bytes(candidate.read_bytes()); os.replace(tmp,config)
print('Runtime registry updated: exactly two projects',flush=True)
os.kill(pid,signal.SIGTERM)
for _ in range(150):
 if not Path(f'/proc/{pid}').exists():break
 time.sleep(.1)
else:raise RuntimeError('Original process did not exit; no second instance launched')
for _ in range(50):
 if subprocess.run(['tmux','has-session','-t','tg-agent-gateway'],capture_output=True).returncode!=0:break
 time.sleep(.1)
else:raise RuntimeError('Original session still active; not replacing it')
subprocess.run(['tmux','new-session','-d','-s','tg-agent-gateway','-c',str(production),'bash '+shlex.quote(str(launcher))],check=True)
print('Started same production build with preserved current Mini App URL',flush=True)
