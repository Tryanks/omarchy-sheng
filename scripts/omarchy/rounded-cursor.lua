-- Pointer-only physical-panel corner guard. No window, bar or output resizing.
-- A Lua timer is used because this Hyprland API has no pointer-motion event.
local M = {}

function M.clamp(x, y, width, height, radius)
  local r = math.max(0, math.min(radius, width / 2, height / 2))
  if r == 0 or x < 0 or y < 0 or x >= width or y >= height then
    return x, y
  end
  local cx = x < r and r or (x > width - r and width - r or nil)
  local cy = y < r and r or (y > height - r and height - r or nil)
  -- Leave the entire middle of all four straight edges untouched.
  if not cx or not cy then return x, y end
  local dx, dy = x - cx, y - cy
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance <= r then return x, y end
  return cx + dx * r / distance, cy + dy * r / distance
end

function M.start(options)
  options = options or {}
  local output = options.output or "DSI-1"
  -- Initial estimate, in native panel pixels; not a measured panel specification.
  local radius_px = options.radius_px or 96
  local timer
  local previous_x, previous_y
  local function correct()
    local monitor = hl.get_monitor(output)
    if not monitor or not monitor.dpms_status then
      timer:set_timeout(500)
      previous_x, previous_y = nil, nil
      return
    end
    local position = hl.get_cursor_pos()
    if not position or (position.x == previous_x and position.y == previous_y) then return end
    previous_x, previous_y = position.x, position.y
    -- Never move a pointer on an external output or override explicit no-warps.
    local under_pointer = hl.get_monitor_at_cursor()
    if not under_pointer or under_pointer.name ~= output or hl.get_config("cursor.no_warps") then return end
    local width, height = monitor.width, monitor.height
    if monitor.transform % 2 == 1 then width, height = height, width end
    width, height = width / monitor.scale, height / monitor.scale
    local x, y = M.clamp(position.x - monitor.x, position.y - monitor.y,
                         width, height, radius_px / monitor.scale)
    x, y = x + monitor.x, y + monitor.y
    if math.abs(x - position.x) > 0.01 or math.abs(y - position.y) > 0.01 then
      hl.dispatch(hl.dsp.cursor.move({x = x, y = y}))
      previous_x, previous_y = x, y
    end
  end
  timer = hl.timer(correct, {type = "repeat", timeout = 8})
  return {timer = timer, correct_now = correct}
end

return M
