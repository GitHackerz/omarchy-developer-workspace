#!/usr/bin/env python3
"""Local developer dashboard. Explicit user actions manage local services."""
import json, os, re, subprocess, sys, time, shutil, signal
from pathlib import Path
BASE=Path(__file__).parent
CONFIG=BASE/'config.json'
MARKERS=('.git','package.json','pyproject.toml','Cargo.toml','go.mod','composer.json','pom.xml','build.gradle')
SKIP={'.git','node_modules','.venv','venv','.next','dist','build','target','.cache','vendor','graphify-out'}

def run(args, timeout=4):
    try:
        p=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
        return p.stdout if p.returncode==0 else ''
    except (OSError,subprocess.SubprocessError): return ''

def settings():
    try: return json.loads(CONFIG.read_text())
    except (OSError,ValueError): return {'projectRoots':['~/Projects'],'maxDepth':4}

def projects():
    found=[]; seen=set(); cfg=settings()
    for raw in cfg.get('projectRoots',['~/Projects']):
        root=Path(raw).expanduser()
        if not root.is_dir(): continue
        for folder,dirs,files in os.walk(root,followlinks=False):
            p=Path(folder); depth=len(p.relative_to(root).parts)
            dirs[:]=sorted(d for d in dirs if d not in SKIP and not d.startswith('.'))
            if depth>=cfg.get('maxDepth',4): dirs[:]=[]
            if any((p/m).exists() for m in MARKERS):
                dirs[:]=[]
                if str(p.resolve()) in seen: continue
                seen.add(str(p.resolve()))
                found.append({'name':p.name,'detail':str(p.relative_to(Path.home())) if p.is_relative_to(Path.home()) else str(p),'path':str(p),'kind':'project'})
    return sorted(found,key=lambda x:x['name'].lower())

def services():
    rows=[]
    docker_available=bool(run(['docker','info','--format','{{.ServerVersion}}']))
    if docker_available:
        for line in run(['docker','ps','-a','--format','{{json .}}']).splitlines():
            try: c=json.loads(line)
            except ValueError: continue
            rows.append({'kind':'container','name':c['Names'],'detail':c['Status']+' · '+(c['Ports'] or 'No published ports'),'id':c['ID'],'image':c['Image'],'state':c.get('State','unknown'),'status':c['Status'],'ports':c['Ports']})
    for line in run(['ss','-ltnpH']).splitlines():
        fields=line.split()
        if len(fields)<5: continue
        address=fields[3]
        try: port=int(address.rsplit(':',1)[1])
        except ValueError: continue
        if port<1024: continue
        match=re.search(r'users:\(\("([^"\n]+)",pid=(\d+)',line)
        process=match.group(1) if match else 'Listener'; pid=match.group(2) if match else ''
        cwd=''
        if pid:
            try: cwd=os.readlink('/proc/'+pid+'/cwd')
            except OSError: pass
        # Keep browser/editor internals out of the development view.
        if process in ('code','chrome','chromium','language_server','quickshell'): continue
        http=process.lower() in ('node','bun','deno','python','python3','uvicorn','gunicorn','next-server','vite') or port in (3000,3001,4000,4173,4200,5000,5050,5173,8000,8080,8081)
        identity = process_identity(pid) if pid else ''
        try: owned = bool(identity) and Path('/proc/'+pid).stat().st_uid == os.getuid()
        except OSError: owned = False
        rows.append({'kind':'port','name':f'{process} · :{port}','detail':address+(' · '+cwd if cwd else ''),'port':port,'pid':pid,'identity':identity,'canStop':owned and bool(cwd) and any(Path(cwd).is_relative_to(Path(r).expanduser().resolve()) for r in settings().get('projectRoots',['~/Projects'])),'state':'listening','url':f'http://localhost:{port}' if http else ''})
    return {'rows':rows,'dockerAvailable':docker_available}

def launch(args):
    subprocess.Popen(args,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)

def terminal(path=None, command=None):
    directory=str(Path(path or Path.home()).resolve())
    command=command or []
    if shutil.which('ghostty'):
        args=['uwsm-app','--','ghostty','--gtk-single-instance=false','--working-directory='+directory]
        if command: args+=['-e']+command
    else:
        # Enter the folder inside the terminal too, for launchers that ignore --dir.
        args=['uwsm-app','--','xdg-terminal-exec','--dir='+directory,
              'sh','-c','cd "$1" || exit; shift; exec "$@"','developer-terminal',directory]
        args+=command or [os.environ.get('SHELL','/bin/bash')]
    launch(args)


def process_identity(pid):
    try:
        return Path('/proc/'+str(pid)+'/stat').read_text().rsplit(')',1)[1].split()[19]
    except (OSError,IndexError): return ''

def checked(args, timeout=25):
    result=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
    if result.returncode:
        raise ValueError((result.stderr.strip() or 'Action failed')[:240])

def action(kind,value):
    if kind in ('project','editor','terminal','files','ai-codex','ai-claude','ai-agy'):
        path=Path(value).resolve()
        if str(path) not in {p['path'] for p in projects()}: raise ValueError('Unknown project')
        if kind in ('project','editor'): launch(['omarchy','launch','editor',str(path)])
        if kind in ('project','terminal'): terminal(path)
        if kind=='files': launch(['xdg-open',str(path)])
        if kind.startswith('ai-'):
            tool=kind[3:]
            executable=shutil.which(tool)
            if not executable: raise ValueError(tool+' is not installed')
            terminal(path,[executable])
    elif kind in ('start','stop','restart','remove','inspect','logs'):
        if not re.fullmatch(r'[0-9a-f]{12,64}',value): raise ValueError('Invalid container ID')
        state=run(['docker','inspect','--format','{{.State.Status}}',value]).strip()
        if not state: raise ValueError('Container no longer exists; refresh the panel')
        if kind=='remove':
            if state not in ('exited','created','dead'): raise ValueError('Stop the container before removing it')
            checked(['docker','rm',value])
        elif kind in ('start','stop','restart'):
            checked(['docker',kind,value])
        elif kind=='inspect':
            terminal(command=['sh','-c','docker inspect "$1" | less','inspect',value])
        else:
            terminal(command=['docker','logs','--tail','150','--follow',value])
    elif kind in ('terminate','kill'):
        data=json.loads(value);pid=int(data['pid'])
        matching=[r for r in services()['rows'] if r.get('pid')==str(pid) and r.get('canStop') and r.get('identity')==data['identity']]
        if not matching: raise ValueError('Process changed or is outside your projects; refresh the panel')
        fd=os.pidfd_open(pid)
        try:
            if process_identity(pid)!=data['identity']: raise ValueError('Process changed; refresh the panel')
            signal.pidfd_send_signal(fd,signal.SIGTERM if kind=='terminate' else signal.SIGKILL)
        finally: os.close(fd)
    elif kind=='copy':
        subprocess.run(['wl-copy'],input=value,text=True,check=True,timeout=3)
    elif kind=='browser':
        if not re.fullmatch(r'http://localhost:\d{1,5}',value): raise ValueError('Invalid local URL')
        launch(['xdg-open',value])
    else: raise ValueError('Unknown action')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='action':
        try:
            action(sys.argv[2],sys.argv[3]);print(json.dumps({'ok':True,'message':'Action completed'}))
        except (ValueError,OSError,subprocess.SubprocessError) as error:
            print(json.dumps({'ok':False,'message':str(error)[:240]}));sys.exit(1)
    else:
        s=services()
        print(json.dumps({'projects':projects(),'services':s['rows'],'dockerAvailable':s['dockerAvailable'],'agents':[{'name':name,'id':tool,'available':bool(shutil.which(tool))} for name,tool in [('Codex CLI','codex'),('Antigravity CLI','agy'),('Claude Code','claude')]],'updated':time.strftime('%H:%M:%S')}))
