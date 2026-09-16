local guard = dofile("scripts/omarchy/rounded-cursor.lua")
local w, h, r = 1524, 1016, 48
local function near(a, b) assert(math.abs(a - b) < 0.00001) end
-- Straight edges, including the extreme top/left, must remain reachable.
for _, p in ipairs({{0,h/2},{w-0.001,h/2},{w/2,0},{w/2,h-0.001},
                    {0,r},{w-r,0},{w/2,h/2},{-2,0},{w+2,0}}) do
  local x,y=guard.clamp(p[1],p[2],w,h,r)
  near(x,p[1]); near(y,p[2])
end
for _, p in ipairs({{0,0},{w-0.001,0},{0,h-0.001},{w-0.001,h-0.001}}) do
  local x,y=guard.clamp(p[1],p[2],w,h,r)
  local cx,cy=p[1]<r and r or w-r,p[2]<r and r or h-r
  near((x-cx)^2+(y-cy)^2,r^2)
  assert(x~=p[1] and y~=p[2])
  local xx,yy=guard.clamp(x,y,w,h,r)
  near(xx,x);near(yy,y)
end
-- A valid point inside the curved corner must not be pushed into a square.
local x,y=guard.clamp(2,40,w,h,r)
near(x,2);near(y,40)
-- Rotated/scaled/offset output mapping and external monitor isolation.
local monitor={name="DSI-1",width=3048,height=2032,scale=2,transform=1,x=2000,y=10,dpms_status=true}
local pointer={x=2000,y=10}; local cb; local warps=0;local interval
hl={
  get_monitor=function() return monitor end,
  get_cursor_pos=function() return pointer end,
  get_monitor_at_cursor=function() return monitor end,
  get_config=function() return false end,
  timer=function(fn,opts) cb=fn;interval=opts.timeout;return {set_timeout=function(_,v) interval=v end} end,
  dsp={cursor={move=function(p) return p end}},
  dispatch=function(p) pointer=p;warps=warps+1 end,
}
guard.start({radius_px=96});cb()
near(pointer.x,2000+r-r/math.sqrt(2));near(pointer.y,10+r-r/math.sqrt(2))
pointer={x=2000,y=500};cb();near(pointer.x,2000)
local previous=warps
hl.get_monitor_at_cursor=function() return {name="DP-1"} end
pointer={x=2000,y=10};cb();assert(warps==previous)
monitor.dpms_status=false;cb();assert(interval==500)
print("PASS: straight edges stay reachable; only circular corners constrained; rotation and external outputs handled")
