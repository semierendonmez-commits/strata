-- lib/voices.lua
-- strata: softcut voice allocation and control
-- 6 voices: capture, surface A/B, fossil, ghost, drone

local World = nil  -- set via init
local Voices = {}

-- voice assignments
local V = {
  CAPTURE   = 1,
  SURFACE_A = 2,
  SURFACE_B = 3,
  FOSSIL    = 4,
  GHOST     = 5,
  DRONE     = 6,
}
Voices.V = V

-- mix levels
Voices.levels = {
  surface = 0.7,
  deep = 0.3,
  ghost = 0.4,
  crystal = 0.3,
  dry = 0.5,
}

-- state
local ghost_active = false
local drone_active = false
local capture_head = 0

-- ============ INIT ============

function Voices.init(world_ref)
  World = world_ref

  -- reset all softcut
  for i = 1, 6 do
    softcut.enable(i, 1)
    softcut.level(i, 0)
    softcut.pan(i, 0)
    softcut.rate(i, 1)
    softcut.loop(i, 1)
    softcut.fade_time(i, 0.05)
    softcut.rec(i, 0)
    softcut.play(i, 0)
    softcut.level_slew_time(i, 0.5)
    softcut.rate_slew_time(i, 0.5)
    softcut.rec_level(i, 1)
    softcut.pre_level(i, 0)
    softcut.level_input_cut(1, i, 1)  -- left input
    softcut.level_input_cut(2, i, 1)  -- right input
    softcut.level_cut_cut(i, i, 0)    -- no self-feedback
  end

  -- VOICE 1: CAPTURE (continuous recording from input)
  softcut.buffer(V.CAPTURE, World.SURFACE_BUF)
  softcut.loop_start(V.CAPTURE, World.CAPTURE_ZONE[1])
  softcut.loop_end(V.CAPTURE, World.CAPTURE_ZONE[2])
  softcut.position(V.CAPTURE, World.CAPTURE_ZONE[1])
  softcut.rate(V.CAPTURE, 1)
  softcut.rec_level(V.CAPTURE, 1)
  softcut.pre_level(V.CAPTURE, 0)
  softcut.rec(V.CAPTURE, 1)
  softcut.play(V.CAPTURE, 0)  -- don't play capture voice
  softcut.level(V.CAPTURE, 0)
  softcut.fade_time(V.CAPTURE, 0.01)

  -- track capture position
  softcut.phase_quant(V.CAPTURE, 0.25)
  softcut.event_phase(function(voice, pos)
    if voice == V.CAPTURE then
      capture_head = pos
      World.capture_pos = pos
    end
  end)
  softcut.poll_start_phase()

  -- VOICE 2: SURFACE A
  softcut.buffer(V.SURFACE_A, World.SURFACE_BUF)
  softcut.level(V.SURFACE_A, Voices.levels.surface)
  softcut.pan(V.SURFACE_A, -0.3)
  softcut.fade_time(V.SURFACE_A, 0.5)
  softcut.rate_slew_time(V.SURFACE_A, 2)

  -- VOICE 3: SURFACE B (slight detune)
  softcut.buffer(V.SURFACE_B, World.SURFACE_BUF)
  softcut.level(V.SURFACE_B, Voices.levels.surface * 0.6)
  softcut.pan(V.SURFACE_B, 0.3)
  softcut.fade_time(V.SURFACE_B, 0.5)
  softcut.rate_slew_time(V.SURFACE_B, 2)

  -- VOICE 4: FOSSIL
  softcut.buffer(V.FOSSIL, World.DEEP_BUF)
  softcut.level(V.FOSSIL, Voices.levels.deep)
  softcut.pan(V.FOSSIL, 0)
  softcut.fade_time(V.FOSSIL, 1)
  softcut.rate_slew_time(V.FOSSIL, 3)

  -- VOICE 5: GHOST
  softcut.buffer(V.GHOST, World.DEEP_BUF)
  softcut.level(V.GHOST, 0)
  softcut.pan(V.GHOST, 0)
  softcut.fade_time(V.GHOST, 2)
  softcut.rate_slew_time(V.GHOST, 1)

  -- VOICE 6: DRONE (crystal)
  softcut.buffer(V.DRONE, World.SURFACE_BUF)
  softcut.level(V.DRONE, 0)
  softcut.pan(V.DRONE, 0)
  softcut.fade_time(V.DRONE, 1)

  -- start capture
  softcut.play(V.CAPTURE, 1)
  softcut.rec(V.CAPTURE, 1)
end

-- ============ LAYER PLAYBACK ============

function Voices.play_surface(layer)
  if not layer then return end
  -- surface A: normal rate with drift
  local drift_ratio = math.pow(2, layer.pitch_drift / 12)
  softcut.loop_start(V.SURFACE_A, layer.start_pos)
  softcut.loop_end(V.SURFACE_A, layer.start_pos + layer.length)
  softcut.position(V.SURFACE_A, layer.start_pos)
  softcut.rate(V.SURFACE_A, 1.0 * drift_ratio)
  softcut.level(V.SURFACE_A, Voices.levels.surface * layer.energy)
  softcut.post_filter_lp(V.SURFACE_A, layer.freq_ceiling)
  softcut.post_filter_enabled(V.SURFACE_A, 1)
  softcut.play(V.SURFACE_A, 1)

  -- surface B: slight detune
  softcut.loop_start(V.SURFACE_B, layer.start_pos)
  softcut.loop_end(V.SURFACE_B, layer.start_pos + layer.length)
  softcut.position(V.SURFACE_B, layer.start_pos + layer.length * 0.2)
  softcut.rate(V.SURFACE_B, 0.98 * drift_ratio)
  softcut.level(V.SURFACE_B, Voices.levels.surface * 0.5 * layer.energy)
  softcut.post_filter_lp(V.SURFACE_B, layer.freq_ceiling * 0.8)
  softcut.post_filter_enabled(V.SURFACE_B, 1)
  softcut.play(V.SURFACE_B, 1)
end

function Voices.play_fossil(layer)
  if not layer then return end
  softcut.loop_start(V.FOSSIL, layer.start_pos)
  softcut.loop_end(V.FOSSIL, layer.start_pos + layer.length)
  softcut.position(V.FOSSIL, layer.start_pos)
  -- fossils play slower
  local rate = 0.5 - layer.entropy * 0.3  -- 0.5 -> 0.2
  softcut.rate(V.FOSSIL, math.max(0.125, rate))
  softcut.level(V.FOSSIL, Voices.levels.deep * layer.energy)
  softcut.post_filter_lp(V.FOSSIL, math.max(200, layer.freq_ceiling))
  softcut.post_filter_enabled(V.FOSSIL, 1)
  softcut.play(V.FOSSIL, 1)
end

function Voices.play_ghost(layer, params)
  if not layer then return end
  params = params or {}
  local rate = params.rate or 0.5
  local reverse = params.reverse or false

  -- ghost from deep buffer
  softcut.loop_start(V.GHOST, layer.start_pos)
  softcut.loop_end(V.GHOST, layer.start_pos + layer.length)
  softcut.position(V.GHOST, layer.start_pos)
  softcut.rate(V.GHOST, reverse and -rate or rate)
  softcut.level(V.GHOST, Voices.levels.ghost)
  softcut.post_filter_lp(V.GHOST, 2000)
  softcut.post_filter_hp(V.GHOST, 300)
  softcut.post_filter_enabled(V.GHOST, 1)
  softcut.play(V.GHOST, 1)
  ghost_active = true
end

function Voices.stop_ghost()
  softcut.level(V.GHOST, 0)
  ghost_active = false
  -- delayed stop
  clock.run(function()
    clock.sleep(3)
    if not ghost_active then
      softcut.play(V.GHOST, 0)
    end
  end)
end

function Voices.start_drone(layer)
  if not layer then return end
  -- very short loop = pitched drone
  local loop_len = math.max(0.01, 1 / (layer.avg_pitch or 220))
  softcut.buffer(V.DRONE, layer.buf)
  softcut.loop_start(V.DRONE, layer.start_pos)
  softcut.loop_end(V.DRONE, layer.start_pos + loop_len)
  softcut.position(V.DRONE, layer.start_pos)
  softcut.rate(V.DRONE, 1)
  softcut.level(V.DRONE, Voices.levels.crystal)
  softcut.play(V.DRONE, 1)
  drone_active = true
end

function Voices.stop_drone()
  softcut.level(V.DRONE, 0)
  drone_active = false
  clock.run(function()
    clock.sleep(2)
    if not drone_active then softcut.play(V.DRONE, 0) end
  end)
end

-- ============ CAPTURE ============

function Voices.get_capture_pos()
  return capture_head
end

function Voices.capture_segment()
  -- copy captured audio to surface zone
  local src_start = capture_head - World.capture_length
  if src_start < World.CAPTURE_ZONE[1] then
    src_start = World.CAPTURE_ZONE[2] - (World.CAPTURE_ZONE[1] - src_start)
  end

  local dst = World.next_surface_pos
  local len = World.capture_length

  -- wrap destination
  if dst + len > World.SURFACE_ZONE[2] then
    dst = World.SURFACE_ZONE[1]
  end

  -- copy within buffer 1
  softcut.buffer_copy_mono(
    World.SURFACE_BUF, World.SURFACE_BUF,
    src_start, dst, len, 0.01, 0
  )

  World.next_surface_pos = dst + len + 0.1
  if World.next_surface_pos > World.SURFACE_ZONE[2] then
    World.next_surface_pos = World.SURFACE_ZONE[1]
  end

  return dst, len
end

function Voices.bury_to_deep(layer)
  -- copy from surface buffer to deep buffer
  local dst = World.next_deep_pos
  local len = layer.length

  if dst + len > World.DEEP_ZONE[2] then
    dst = World.DEEP_ZONE[1]
  end

  softcut.buffer_copy_mono(
    World.SURFACE_BUF, World.DEEP_BUF,
    layer.start_pos, dst, len, 0.01, 0
  )

  -- update layer to reference deep buffer
  layer.buf = World.DEEP_BUF
  layer.start_pos = dst

  World.next_deep_pos = dst + len + 0.1
  if World.next_deep_pos > World.DEEP_ZONE[2] then
    World.next_deep_pos = World.DEEP_ZONE[1]
  end
end

-- ============ UPDATE ============

function Voices.update_from_world()
  -- update surface playback based on current surface layer
  local surf = World.get_surface()
  if surf then
    local drift_ratio = math.pow(2, surf.pitch_drift / 12)
    softcut.rate(V.SURFACE_A, 1.0 * drift_ratio)
    softcut.level(V.SURFACE_A, Voices.levels.surface * surf.energy)
    softcut.post_filter_lp(V.SURFACE_A, surf.freq_ceiling)

    softcut.rate(V.SURFACE_B, 0.98 * drift_ratio)
    softcut.level(V.SURFACE_B, Voices.levels.surface * 0.5 * surf.energy)
    softcut.post_filter_lp(V.SURFACE_B, surf.freq_ceiling * 0.8)
  end

  -- update fossil if playing
  local fossils = World.get_fossils()
  if #fossils > 0 then
    local f = fossils[1]
    softcut.level(V.FOSSIL, Voices.levels.deep * f.energy)
    softcut.post_filter_lp(V.FOSSIL, math.max(200, f.freq_ceiling))
  end
end

return Voices
