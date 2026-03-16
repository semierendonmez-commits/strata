-- strata
-- v1.0.0 @semi
-- llllllll.co/t/xxxxx
--
-- digital geology instrument
-- sound becomes sediment
-- sediment decays over time
-- ghosts rise from the deep
--
-- K1: norns menu
-- K2+E1: page change
-- K2 short: play/stop
-- K3: context action
-- grid: world map + controls

engine.name = "Strata"

local World = include("lib/world")
local Voices = include("lib/voices")
local UI = include("lib/ui")

-- state
local screen_dirty = true
local grid_dirty = true
local g = nil
local k2_held = false
local k2_time = 0
local k1_held = false
local page_acc = 0

-- clocks
local clocks = {}

-- amplitude tracking
local current_amp = 0
local current_pitch = 440
local capture_cooldown = 0
local ghost_cooldown = 0
local sc_update_counter = 0

-- ============ POLLS ============

local function setup_polls()
  -- input amplitude for capture triggering
  local p_amp = poll.set("amp_in_l")
  if p_amp then
    p_amp.time = 0.1
    p_amp.callback = function(val)
      current_amp = val
    end
    p_amp:start()
  end

  -- pitch tracking
  local p_pitch = poll.set("pitch_in_l")
  if p_pitch then
    p_pitch.time = 0.2
    p_pitch.callback = function(val)
      if val > 20 and val < 10000 then
        current_pitch = val
      end
    end
    p_pitch:start()
  end
end

-- ============ WORLD CALLBACKS ============

local function on_quake(intensity)
  -- trigger SC quake effect
  engine.quake(intensity, 2 + intensity * 3)
  UI.quake_flash = 3
  screen_dirty = true
  grid_dirty = true
end

local function on_ghost(layer)
  if ghost_cooldown > 0 then return end
  ghost_cooldown = 5  -- 5 second cooldown

  -- play ghost via softcut
  local reverse = math.random() > 0.5
  local rate = 0.25 + math.random() * 0.5
  Voices.play_ghost(layer, {rate = rate, reverse = reverse})

  -- SC ghost processing
  local shift = -12 + math.random() * (-12)  -- -12 to -24
  engine.ghost_start(shift, 0.8, 800, 0.3)

  -- auto-stop ghost after a while
  clock.run(function()
    clock.sleep(layer.length / rate + 3)
    Voices.stop_ghost()
    engine.ghost_stop()
  end)
end

local function on_crystal(layer)
  local freq = layer.avg_pitch or 220
  engine.crystal_start(freq, 0.9, 0.25)
  Voices.start_drone(layer)
  screen_dirty = true
end

local function on_bury(layer)
  -- copy layer from surface buffer to deep buffer
  Voices.bury_to_deep(layer)

  -- start fossil playback if first fossil
  local fossils = World.get_fossils()
  if #fossils == 1 then
    Voices.play_fossil(layer)
  end
end

-- ============ CLOCKS ============

local function world_loop()
  while true do
    clock.sleep(1 / 15)  -- 15 Hz world tick

    local ok, err = pcall(function()
      World.tick(1 / 15)

      -- capture new material when input is loud enough
      capture_cooldown = math.max(0, capture_cooldown - 1/15)
      if current_amp > World.capture_threshold and capture_cooldown <= 0 then
        local pos, len = Voices.capture_segment()
        local layer = World.add_layer(pos, len,
          current_amp, current_amp, current_pitch)
        Voices.play_surface(layer)
        capture_cooldown = World.capture_length + 1
      end

      -- ghost cooldown
      ghost_cooldown = math.max(0, ghost_cooldown - 1/15)

      -- random ghost chance
      if math.random() < (params:get("ghost_prob") or 0) * (1/15) * 0.1 then
        local match = World.find_ghost_match(current_amp, current_pitch)
        if match then on_ghost(match) end
      end

      -- update SC decay chain from surface layer (rate-limited)
      sc_update_counter = sc_update_counter + 1
      if sc_update_counter >= 8 then  -- ~2Hz
        sc_update_counter = 0
        local surf = World.get_surface()
        if surf then
          engine.decay(
            surf.bit_decay,
            48000 * (1 - surf.entropy * 0.9),  -- sample rate
            surf.freq_ceiling,
            surf.stereo_width,
            surf.noise_floor,
            surf.pitch_drift
          )
          engine.decay_mix(World.avg_entropy())
        end
        Voices.update_from_world()
      end
    end)
    if not ok then print("strata world error: " .. tostring(err)) end

    screen_dirty = true
    grid_dirty = true
  end
end

local function screen_loop()
  while true do
    clock.sleep(1 / 15)
    local menu_active = _menu and _menu.mode
    if screen_dirty and not menu_active then
      local ok, err = pcall(UI.draw, screen)
      if not ok then print("strata draw error: " .. tostring(err)) end
      screen_dirty = false
    end
    if grid_dirty and g then
      pcall(UI.grid_draw, g)
      grid_dirty = false
    end
  end
end

-- ============ GRID ============

local function grid_connect()
  g = grid.connect()
  if g then
    g.key = function(x, y, z)
      if UI.grid_key(x, y, z) then
        screen_dirty = true
        grid_dirty = true
      end
    end
  end
end

-- ============ PARAMS ============

local function init_params()
  params:add_separator("STRATA: WORLD")

  params:add_control("time_scale", "time scale",
    controlspec.new(0.01, 16, "exp", 0.01, 1))
  params:set_action("time_scale", function(v) World.time_scale = v end)

  params:add_control("decay_rate", "decay rate",
    controlspec.new(0.001, 0.1, "exp", 0.001, 0.01))
  params:set_action("decay_rate", function(v) World.decay_rate = v end)

  params:add_control("dissolution", "dissolution",
    controlspec.new(0.001, 0.05, "exp", 0.001, 0.005))
  params:set_action("dissolution", function(v) World.dissolution_rate = v end)

  params:add_control("capture_thresh", "capture threshold",
    controlspec.new(0.01, 0.5, "exp", 0.01, 0.05))
  params:set_action("capture_thresh", function(v) World.capture_threshold = v end)

  params:add_control("capture_len", "capture length",
    controlspec.new(0.5, 30, "lin", 0.5, 4, "s"))
  params:set_action("capture_len", function(v) World.capture_length = v end)

  params:add_number("max_layers", "max layers", 2, 16, 8)
  params:set_action("max_layers", function(v) World.MAX_LAYERS = v end)

  params:add_separator("STRATA: TECTONIC")

  params:add_control("pressure_rate", "pressure rate",
    controlspec.new(0.01, 1, "exp", 0.01, 0.1))
  params:set_action("pressure_rate", function(v) World.pressure_rate = v end)

  params:add_control("quake_thresh", "quake threshold",
    controlspec.new(0.3, 1, "lin", 0.05, 0.8))
  params:set_action("quake_thresh", function(v) World.quake_threshold = v end)

  params:add_control("crystal_freq", "crystal freq",
    controlspec.new(50, 2000, "exp", 1, 220, "Hz"))

  params:add_control("crystal_fb", "crystal feedback",
    controlspec.new(0.5, 0.99, "lin", 0.01, 0.9))

  params:add_separator("STRATA: GHOST")

  params:add_control("ghost_rate", "ghost rate",
    controlspec.new(0.125, 2, "exp", 0.01, 0.5))

  params:add_control("ghost_pitch", "ghost pitch",
    controlspec.new(-24, 12, "lin", 1, -12, "st"))

  params:add_control("ghost_verb", "ghost reverb",
    controlspec.new(0, 1, "lin", 0.01, 0.8))

  params:add_control("ghost_prob", "ghost probability",
    controlspec.new(0, 1, "lin", 0.01, 0.3))

  params:add_separator("STRATA: MIX")

  params:add_control("mix_surface", "surface level",
    controlspec.new(0, 1, "lin", 0.01, 0.7))
  params:set_action("mix_surface", function(v)
    Voices.levels.surface = v
  end)

  params:add_control("mix_deep", "deep level",
    controlspec.new(0, 1, "lin", 0.01, 0.3))
  params:set_action("mix_deep", function(v)
    Voices.levels.deep = v
  end)

  params:add_control("mix_ghost", "ghost level",
    controlspec.new(0, 1, "lin", 0.01, 0.4))
  params:set_action("mix_ghost", function(v)
    Voices.levels.ghost = v
  end)

  params:add_control("mix_crystal", "crystal level",
    controlspec.new(0, 1, "lin", 0.01, 0.3))
  params:set_action("mix_crystal", function(v)
    Voices.levels.crystal = v
  end)

  params:add_control("master", "master",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("master", function(v) engine.amp(v) end)
end

-- ============ INIT ============

function init()
  print("STRATA: init...")

  -- world callbacks
  World.on_quake = on_quake
  World.on_ghost = on_ghost
  World.on_crystal = on_crystal
  World.on_bury = on_bury

  init_params()
  params:default()

  Voices.init(World)
  UI.init(World, Voices)
  grid_connect()

  setup_polls()

  -- start clocks
  clocks.world = clock.run(world_loop)
  clocks.screen = clock.run(screen_loop)

  screen_dirty = true
  print("STRATA: ready")
end

-- ============ ENC / KEY ============

function enc(n, d)
  if n == 1 and (k1_held or k2_held) then
    page_acc = page_acc + d
    if math.abs(page_acc) >= 3 then
      if page_acc > 0 then UI.next_page() else UI.prev_page() end
      page_acc = 0
      screen_dirty = true
    end
    return
  end

  if UI.page == 1 then
    -- SECTION: E1=time scale, E2=erosion speed, E3=depth browse
    if n == 1 then
      params:delta("time_scale", d)
    elseif n == 2 then
      params:delta("decay_rate", d)
    elseif n == 3 then
      -- browse layers
      UI.matter_layer = util.clamp(UI.matter_layer + d, 0, World.layer_count() - 1)
    end
  elseif UI.page == 2 then
    -- SEISMIC: E1=time speed, E2=pressure rate, E3=quake threshold
    if n == 1 then
      params:delta("time_scale", d)
    elseif n == 2 then
      params:delta("pressure_rate", d)
    elseif n == 3 then
      params:delta("quake_thresh", d)
    end
  elseif UI.page == 3 then
    -- MATTER: E1=layer select, E2=scroll, E3=adjust
    if n == 1 then
      UI.matter_layer = util.clamp(UI.matter_layer + d, 0, World.layer_count() - 1)
    end
  elseif UI.page == 4 then
    -- ARCHAEOLOGY: E1=select action, E3=dig depth
    if n == 1 then
      UI.archaeo_sel = util.clamp(UI.archaeo_sel + d, 1, #ARCHAEO_ITEMS)
    elseif n == 3 then
      if UI.archaeo_sel == 1 then  -- DIG
        UI.dig_depth = util.clamp(UI.dig_depth + d, 0, World.deepest_depth())
      end
    end
  end
  screen_dirty = true
end

function key(n, z)
  if n == 1 then
    k1_held = (z == 1)
    if z == 0 then page_acc = 0 end
    return
  end

  if n == 2 then
    if z == 1 then
      k2_held = true
      k2_time = util.time()
    else
      k2_held = false
      page_acc = 0
      if util.time() - k2_time < 0.3 then
        World.running = not World.running
      end
    end
    screen_dirty = true
    return
  end

  if n == 3 and z == 1 then
    if UI.page == 1 or UI.page == 2 then
      -- QUAKE
      World.manual_quake(0.5 + World.pressure * 0.5)
      UI.quake_flash = 3
    elseif UI.page == 3 then
      -- CRYSTAL toggle
      local freq = params:get("crystal_freq")
      World.toggle_crystal(freq)
      local surf = World.get_surface()
      if surf and surf.crystal then
        on_crystal(surf)
      else
        engine.crystal_stop()
        Voices.stop_drone()
      end
    elseif UI.page == 4 then
      -- ARCHAEOLOGY actions
      if UI.archaeo_sel == 1 then
        -- DIG: play layer at dig_depth
        local l = World.get_layer_by_depth(UI.dig_depth)
        if l then
          if l.buf == World.DEEP_BUF then
            Voices.play_fossil(l)
          else
            Voices.play_surface(l)
          end
        end
      elseif UI.archaeo_sel == 2 then
        -- RESTORE
        local l = World.get_layer_by_depth(UI.dig_depth)
        if l then World.restore(l) end
      elseif UI.archaeo_sel == 3 then
        -- EXTRACT: trigger ghost from deepest fossil
        local fossils = World.get_fossils()
        if #fossils > 0 then
          on_ghost(fossils[#fossils])
        end
      end
    end
    screen_dirty = true
    grid_dirty = true
  end
end

-- ============ CLEANUP ============

function cleanup()
  for _, id in pairs(clocks) do
    pcall(function() clock.cancel(id) end)
  end
  engine.crystal_stop()
  engine.ghost_stop()
  if g then g:all(0); g:refresh() end
  print("STRATA: shutdown")
end
