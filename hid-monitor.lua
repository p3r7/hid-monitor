--
--   HID MONITOR
--   @eigen
--
--
--   E1 - select HID device
--   E3 - scrollback through HID messages
--
--   K2 - toggle unmute/mute internal synth
--   K3 - clear screen / buffer
--

local hid_events = require "hid_events"

local ANALOG_O_MARGIN = 5

local devicepos = 1
local hdevs = {}
local hid_device
local msg = {}

local hid_buffer = {}
local hid_buffer_len = 256
local buff_start = 1

-- display grid setup
local line_height = 8
local line_offset = 16
local col1 = 0
local col2 = 10
local col3 = 30
local col4 = col3 + 27
local col5 = col4 + 20


-- ------------------------------------------------------------------------
-- MAIN API

function init()
  norns.enc.sens(1,6)
  clear_hid_buffer()
  --_norns.rev_off()

  connect()
  get_hid_names()
  print_hid_names()

  -- setup params

  params:add{type = "option", id = "hid_device", name = "HID-device", options = hdevs , default = 1,
             action = function(value)
               hid_device.event = nil
               --grid.cleanup()
               hid_device = hid.connect(value)
               hid_device.event = hid_event
               hid.update_devices()

               hdevs = {}
               get_hid_names()
               params.params[1].options = hdevs
               --tab.print(params.params[1].options)
               devicepos = value
               if clocking then
                 clock.cancel(blink_id)
                 clocking = false
               end
               print ("hid ".. devicepos .." selected: " .. hdevs[devicepos])

  end}

  -- Render Style
  screen.level(15)
  screen.aa(0)
  screen.line_width(1)

end

function redraw()
  screen.clear()
  draw_labels()
  if msg then
    draw_event()
  end

  screen.level(3)
  screen.move(90,7)
  screen.text(hid_type_name()) -- FIXME: not working as expected
  screen.stroke()

  screen.level(1)
  screen.line_width(1.5)
  screen.move(0, 18)
  screen.line(128, 18)
  screen.stroke()

  screen.level(15)
  screen.move(0, 7)
  screen.text(devicepos .. ": ".. truncate_txt(hdevs[devicepos], 19))

  screen.update()
end


function key(n, z)
  if n==2 and z == 1 then
    mute = not mute
  end
  if n == 3 and z == 1 then
    clear_hid_buffer()
  end
  redraw()
end


function enc(id,delta)
  if id == 1 then
    --print(params:get("hid_device"))
    params:set("hid_device", util.clamp(devicepos+delta, 1,4))
  end
  if id == 2 then
  end
  if id == 3 then
    buff_start = util.clamp(buff_start + delta, 1, hid_buffer_len-5)
  end

  redraw()
end



-- ------------------------------------------------------------------------
-- HID EVENT CB

function hid_event(typ, code, value)

  local event_code_type
  for k, v in pairs(hid_events.types) do
    if tonumber(v) == typ then
      event_code_type = k
      break
    end
  end

  local do_log_event = is_loggable_event(event_code_type, value)

  if do_log_event then

    local keycode = code_2_keycode(event_code_type, code)
    if keycode == nil then
      keycode = ""
    end
    -- dbg_msg = "hid.event" .."\t".. " type: "..typ .."\t".. " code: ".. code .."\t".. " value: "..value
    -- if keycode then
    --   dbg_msg = dbg_msg .."\t".. " keycode: "..keycode
    -- end
    msg = {typ, string.sub(event_code_type, -3), int_to_hex(code), value, shorten_keycode(keycode)}
    table.insert(hid_buffer, 1, msg)
  end

  redraw()
end


-- ------------------------------------------------------------------------
-- HELPER FNS - HID DEVICES

function get_hid_names()
  -- Get a list of grid devices
  for id,device in pairs(hid.vports) do
    hdevs[id] = device.name
  end
end

function print_hid_names()
  print ("HID Devices:")
  for id,device in pairs(hid.vports) do
    hdevs[id] = device.name
    print(id, hdevs[id])
  end
end

function connect()
  hid.update_devices()
  hid_device = hid.connect(devicepos)
  hid_device.event = hid_event
end

function clear_hid_buffer()
  hid_buffer = {}
  for z=1,hid_buffer_len do
    table.insert(hid_buffer, {})
  end
  buff_start = 1
end

function hid_type_name()
  if hid_device.device.is_ascii_keyboard then
    return "keyboard"
  elseif hid_device.device.is_mouse then
    return "mouse"
  elseif hid_device.device.is_gamepad then
    return "gamepad"
  else
    return "???"
  end
end

-- ------------------------------------------------------------------------
-- HELPER FNS - HID EVENTS

function is_loggable_event(event_code_type,val)
  if event_code_type == "EV_KEY" and val == 0 then
    return false
  end

  if event_code_type == "EV_ABS" and is_dpad_origin(val) then
    return false
  end

  return true
end

function is_dpad_origin(value)
  return ( value >= (128 - ANALOG_O_MARGIN) and value <= (128 + ANALOG_O_MARGIN) )
end

function code_2_keycode(event_code_type, code)
  for k, v in pairs(hid_events.codes) do
    if tonumber(v) == code then
      if event_code_type == 'EV_KEY' and (util.string_starts(k, 'KEY_') or util.string_starts(k, 'BTN_')) then
        return k
      elseif util.string_starts(k, gamepad.event_code_type_2_key_prfx(event_code_type)) then
        return k
      end
    end
  end
end

function event_code_type_2_key_prfx(event_code_type)
  return string.sub(event_code_type, -3)
end

function shorten_keycode(keycode)
  if util.string_starts(keycode, 'KEY_') then
    return string.sub(keycode, string.len('KEY_')+1)
  end
  return keycode
end

-- ------------------------------------------------------------------------
-- HELPER FNS - STR

function truncate_txt(txt, size)
  if string.len(txt) > size then
    s1 = string.sub(txt, 1, 9) .. "..."
    s2 = string.sub(txt, string.len(txt) - 5, string.len(txt))
    s = s1..s2
  else
    s = txt
  end
  return s
end

function int_to_hex(v)
  local hex = string.format("%X", v)
  if string.len(hex) == 1 then
    hex = '0'..hex
  end
  return '0x'..hex
end


-- ------------------------------------------------------------------------
-- HELPER FNS - DRAWING

function draw_labels()
  screen.level(1)
  screen.move(col1,(line_height * 2))
  screen.text('')
  screen.move(col2 - 9,(line_height * 2))
  screen.text('event')
  screen.move(col3 + 2,(line_height * 2))
  screen.text('code')
  screen.move(col4, (line_height * 2))
  screen.text('val')
  screen.move(col5,(line_height * 2))
  screen.text('keycode')
  -- screen.move(col6,(line_height * 2))
  -- screen.text_right('ln')
end

function draw_event()
  for i=1,6 do
    --print("i:",i)
    buf_idx = buff_start + i - 1
    if hid_buffer[buf_idx][1] ~= nil then
      screen.level(12)
      screen.move(col1+1,(line_offset + line_height * i))
      screen.text(hid_buffer[buf_idx][1])
      screen.move(col2+1,(line_offset + line_height * i))
      screen.text(hid_buffer[buf_idx][2])
      screen.move(col3+2,(line_offset + line_height * i))
      screen.text(hid_buffer[buf_idx][3])
      screen.move(col4,(line_offset + line_height * i))
      screen.text(hid_buffer[buf_idx][4])
      screen.move(col5,(line_offset + line_height * i))
      screen.text(hid_buffer[buf_idx][5])
      screen.stroke()
      screen.level(3)
      -- screen.move(col6,(line_offset + line_height * i))
      -- screen.text_right(buf_idx)
      screen.stroke()
    end
  end
end
