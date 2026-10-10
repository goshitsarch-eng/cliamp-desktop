import ctypes as c
import sys
import os
x = c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XFlush.argtypes = [c.c_void_p]
x.XCloseDisplay.argtypes = [c.c_void_p]
x.XSetInputFocus.argtypes = [c.c_void_p,c.c_ulong,c.c_int,c.c_ulong]
x.XInternAtom.argtypes = [c.c_void_p,c.c_char_p,c.c_int]
x.XInternAtom.restype = c.c_ulong
x.XStringToKeysym.argtypes = [c.c_char_p]
x.XStringToKeysym.restype = c.c_ulong
x.XKeysymToKeycode.argtypes = [c.c_void_p,c.c_ulong]
x.XKeysymToKeycode.restype = c.c_uint
x.XSendEvent.argtypes = [c.c_void_p,c.c_ulong,c.c_int,c.c_long,c.c_void_p]
d = x.XOpenDisplay(os.environ.get('DISPLAY', ':100').encode())
assert d, 'No virtual display'
action = sys.argv[1]
window = int(sys.argv[2], 0)
x.XSetInputFocus(d, window, 2, 0)
if action == 'resize':
 x.XResizeWindow.argtypes=[c.c_void_p,c.c_ulong,c.c_uint,c.c_uint]
 x.XResizeWindow(d,window,int(sys.argv[3]),int(sys.argv[4]))
elif action == 'move':
 x.XMoveWindow.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_int]
 x.XMoveWindow(d,window,int(sys.argv[3]),int(sys.argv[4]))
elif action in ('close', 'maximize', 'restore'):
 class Data(c.Union):
  _fields_ = [('b',c.c_char*20),('s',c.c_short*10),('l',c.c_long*5)]
 class Client(c.Structure):
  _fields_ = [('type',c.c_int),('serial',c.c_ulong),('send_event',c.c_int),('display',c.c_void_p),('window',c.c_ulong),('message_type',c.c_ulong),('format',c.c_int),('data',Data)]
 class Event(c.Union):
  _fields_ = [('client',Client),('pad',c.c_long*24)]
 e=Event()
 e.client.type=33
 e.client.send_event=1
 e.client.display=d
 e.client.window=window
 e.client.format=32
 if action == 'close':
  e.client.message_type=x.XInternAtom(d,b'WM_PROTOCOLS',0)
  e.client.data.l[0]=x.XInternAtom(d,b'WM_DELETE_WINDOW',0)
  target=window
  mask=0
 else:
  e.client.message_type=x.XInternAtom(d,b'_NET_WM_STATE',0)
  e.client.data.l[0]=1 if action == 'maximize' else 0
  e.client.data.l[1]=x.XInternAtom(d,b'_NET_WM_STATE_MAXIMIZED_VERT',0)
  e.client.data.l[2]=x.XInternAtom(d,b'_NET_WM_STATE_MAXIMIZED_HORZ',0)
  e.client.data.l[3]=1
  x.XDefaultRootWindow.argtypes=[c.c_void_p]
  x.XDefaultRootWindow.restype=c.c_ulong
  target=x.XDefaultRootWindow(d)
  mask=(1<<20)|(1<<19)
 assert x.XSendEvent(d,target,0,mask,c.byref(e))
else:
 xt=c.CDLL('libXtst.so.6')
 xt.XTestFakeMotionEvent.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_ulong]
 xt.XTestFakeButtonEvent.argtypes=[c.c_void_p,c.c_uint,c.c_int,c.c_ulong]
 xt.XTestFakeKeyEvent.argtypes=[c.c_void_p,c.c_uint,c.c_int,c.c_ulong]
 if action=='click':
  xt.XTestFakeMotionEvent(d,-1,int(sys.argv[3]),int(sys.argv[4]),0)
  xt.XTestFakeButtonEvent(d,1,1,0)
  xt.XTestFakeButtonEvent(d,1,0,0)
 elif action=='type':
  names={' ':'space','/':'slash','.':'period',':':'colon','-':'minus','_':'underscore'}
  shift=x.XKeysymToKeycode(d,x.XStringToKeysym(b'Shift_L'))
  for char in sys.argv[3]:
   symbol=names.get(char,char.lower())
   code=x.XKeysymToKeycode(d,x.XStringToKeysym(symbol.encode()))
   assert code, 'Unsupported character; use clipboard for Unicode'
   shifted=char.isupper() or char in ':_'
   if shifted: xt.XTestFakeKeyEvent(d,shift,1,0)
   xt.XTestFakeKeyEvent(d,code,1,0)
   xt.XTestFakeKeyEvent(d,code,0,0)
   if shifted: xt.XTestFakeKeyEvent(d,shift,0,0)
 elif action=='key':
  keys=[x.XKeysymToKeycode(d,x.XStringToKeysym(k.encode())) for k in sys.argv[3:]]
  assert all(keys), 'Unknown key'
  for key in keys: xt.XTestFakeKeyEvent(d,key,1,0)
  for key in reversed(keys): xt.XTestFakeKeyEvent(d,key,0,0)
 else: raise ValueError(action)
x.XFlush(d)
x.XCloseDisplay(d)
