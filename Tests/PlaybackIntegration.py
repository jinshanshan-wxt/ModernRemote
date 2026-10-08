import socket,json,uuid,subprocess,time
import argparse
parser=argparse.ArgumentParser(description="Opt-in real Music.app playback regression. Stop Music before running; creates dated remote playlists.")
parser.add_argument('--host',default='127.0.0.1')
parser.add_argument('--port',type=int,required=True)
parser.add_argument('--exercise-playback',action='store_true',required=True)
args=parser.parse_args()
s=socket.create_connection((args.host,args.port));s.settimeout(120);f=s.makefile('rb')
def call(action,**kw):
 s.sendall((json.dumps(dict(version=1,id=str(uuid.uuid4()),action=action,**kw))+'\n').encode());r=json.loads(f.readline());assert not r.get('error'),r.get('error');return r
original=call('status')['playback']
if original.get('trackID') or original['playing']:
 raise SystemExit('Stop Music first; this test does not replace an existing playback queue.')
tracks=[]
while True:
 r=call('library',offset=len(tracks));tracks+=r.get('tracks',[])
 if not r.get('hasMore'):break
local=[t for t in tracks if t.get('downloaded') and t['duration']>40];assert len(local)>=4
ids=[t['id'] for t in local[:4]]
def check(expected,label):
 for _ in range(20):
  p=call('status')['playback']
  if p.get('trackID')==expected and p['playing']:
   print('PASS:',label,flush=True);return
  time.sleep(.25)
 raise AssertionError(label+' failed: unexpected current song or stopped playback')
try:
 call('queue',offset=0,value=0,trackIDs=ids[:2]);check(ids[0],'old album first track')
 call('queue',offset=1,value=0,trackIDs=[ids[3],ids[2],ids[0]]);check(ids[2],'different context clicked middle track')
 call('next');check(ids[0],'Next follows new context, not old album')
 call('next');time.sleep(.3)
 call('queue',offset=0,value=0,trackIDs=[ids[1],ids[3]]);check(ids[1],'new context starts after exhausted queue')
 call('next');check(ids[3],'Next plays after previous queue exhausted')
 call('queue',offset=0,value=0,trackIDs=[ids[1],ids[3]]);check(ids[1],'same context restarts from selection')
 call('next');check(ids[3],'reused context Next plays')
 call('queue',offset=1,value=0,trackIDs=[ids[3],ids[2],ids[0]]);check(ids[2],'middle selection before Previous')
 call('previous');check(ids[3],'Previous reaches item before initial selection')
 call('next');check(ids[2],'Next returns to initially selected item')
 p=call('status')['playback'];call('seek',value=p['duration']-.4)
 check(ids[0],'native automatic advance without phone Next')
 p=call('status')['playback'];call('seek',value=p['duration']-.4)
 for _ in range(30):
  if not call('status')['playback']['playing']:break
  time.sleep(.25)
 else:raise AssertionError('queue did not naturally finish')
 print('PASS: queue naturally exhausted',flush=True)
 call('queue',offset=0,value=0,trackIDs=[ids[1],ids[3]]);check(ids[1],'new selection after natural exhaustion')
 call('next');check(ids[3],'Next after natural exhaustion plays correctly')
 print('PASS: live Music.app regression through installed companion',flush=True)
finally:
 call('stop')
 call('shuffle',value=1 if original.get('shuffle') else 0);call('repeat',value=original.get('repeatMode',0))
 print('Restored stopped playback and original shuffle/repeat modes',flush=True)
 s.close()
