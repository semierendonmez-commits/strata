-- lib/world.lua
-- strata: digital geology simulation
-- layers, entropy, tectonic events

local World = {}

-- constants
World.MAX_LAYERS = 8
World.SURFACE_BUF = 1
World.DEEP_BUF = 2
World.CAPTURE_ZONE = {0, 120}      -- buffer 1: 0-120s
World.SURFACE_ZONE = {120, 340}    -- buffer 1: 120-340s
World.DEEP_ZONE = {0, 250}         -- buffer 2: 0-250s
World.GHOST_ZONE = {250, 340}      -- buffer 2: 250-340s

-- world state
World.layers = {}
World.time = 0
World.time_scale = 1.0
World.running = true
World.pressure = 0
World.seismic_history = {}  -- last 60 values for sismograph

-- params (set from params menu)
World.decay_rate = 0.01
World.dissolution_rate = 0.005
World.pressure_rate = 0.1
World.quake_threshold = 0.8
World.capture_length = 4.0
World.capture_threshold = 0.05

-- capture state
World.capture_pos = 0
World.capture_active = false
World.next_surface_pos = World.SURFACE_ZONE[1]
World.next_deep_pos = World.DEEP_ZONE[1]

-- layer ID counter
local next_id = 1

-- callbacks (set by main script)
World.on_quake = nil      -- function(intensity)
World.on_ghost = nil      -- function(layer)
World.on_crystal = nil    -- function(layer)
World.on_bury = nil       -- function(layer)

-- ============ LAYER ============

local function new_layer(buf_pos, length, brightness, density)
  local l = {
    id = next_id,
    birth_time = World.time,
    age = 0,
    depth = 0,

    buf = World.SURFACE_BUF,
    start_pos = buf_pos,
    length = length,

    brightness = brightness or 0.5,
    density = density or 0.5,
    avg_pitch = 440,

    entropy = 0,
    bit_decay = 16,
    freq_ceiling = 20000,
    stereo_width = 1.0,
    noise_floor = 0,
    pitch_drift = 0,

    state = "surface",
    energy = 1.0,
    visible = true,
    crystal = false,
  }
  next_id = next_id + 1
  return l
end

-- ============ ENTROPY PHYSICS ============

local function update_entropy(layer, dt)
  layer.age = layer.age + dt * World.time_scale

  -- exponential decay curve
  local rate = World.decay_rate * (1 + layer.depth * 0.5)
  layer.entropy = 1 - math.exp(-layer.age * rate)
  local e = layer.entropy

  -- derived parameters
  layer.bit_decay = math.max(2, math.floor(16 - e * 14))
  layer.freq_ceiling = math.max(200, 20000 * (1 - math.pow(e, 0.7)))
  layer.stereo_width = math.max(0, 1 - math.pow(e, 1.5))
  layer.noise_floor = e * 0.25
  -- pitch drift: pseudo-random walk
  local noise = math.sin(layer.age * 0.7 + layer.id * 3.14) * 0.5
        + math.sin(layer.age * 1.3 + layer.id * 1.7) * 0.3
  layer.pitch_drift = noise * e * 2  -- max +/-2 semitones

  -- energy dissolution
  layer.energy = layer.energy - dt * World.dissolution_rate * e * World.time_scale
  if layer.energy < 0 then layer.energy = 0 end
end

-- ============ TECTONIC ============

local function update_pressure(dt)
  World.pressure = World.pressure + dt * World.pressure_rate * World.time_scale
  -- add to seismic history (sampled at ~2Hz)
  if #World.seismic_history > 120 then
    table.remove(World.seismic_history, 1)
  end
end

local function trigger_quake(intensity)
  World.pressure = 0
  -- record seismic spike
  World.seismic_history[#World.seismic_history + 1] = intensity

  if World.on_quake then World.on_quake(intensity) end

  -- find deepest fossil to surface as ghost
  local deepest = nil
  for _, l in ipairs(World.layers) do
    if l.state == "fossil" or l.state == "buried" then
      if not deepest or l.depth > deepest.depth then
        deepest = l
      end
    end
  end
  if deepest and World.on_ghost then
    World.on_ghost(deepest)
  end
end

-- ============ SPECTRAL MATCHING ============

function World.find_ghost_match(current_amp, current_pitch)
  local candidates = {}
  for _, l in ipairs(World.layers) do
    if l.state == "fossil" or l.state == "buried" then
      local amp_diff = math.abs((l.brightness or 0.5) - current_amp)
      local pitch_diff = math.abs(math.log(current_pitch / (l.avg_pitch or 440)) / math.log(2)) * 12
      local distance = amp_diff * 0.3 + pitch_diff * 0.7
      candidates[#candidates + 1] = {layer = l, dist = distance}
    end
  end

  if #candidates == 0 then return nil end

  -- sort by distance
  table.sort(candidates, function(a, b) return a.dist < b.dist end)

  -- weighted random among top 3
  local top = math.min(3, #candidates)
  local weights = {}
  local total = 0
  for i = 1, top do
    weights[i] = 1 / (candidates[i].dist + 0.01)
    total = total + weights[i]
  end
  local r = math.random() * total
  local acc = 0
  for i = 1, top do
    acc = acc + weights[i]
    if r <= acc then return candidates[i].layer end
  end
  return candidates[1].layer
end

-- ============ LAYER MANAGEMENT ============

function World.add_layer(buf_pos, length, brightness, density, pitch)
  -- push existing layers down
  for _, l in ipairs(World.layers) do
    if l.state == "surface" then
      l.depth = l.depth + 1
      if l.depth >= 2 then
        l.state = "buried"
      end
      if l.depth >= 4 then
        l.state = "fossil"
        -- trigger bury callback for buffer copy
        if World.on_bury then World.on_bury(l) end
      end
    end
  end

  -- create new surface layer
  local layer = new_layer(buf_pos, length, brightness, density)
  layer.avg_pitch = pitch or 440
  table.insert(World.layers, 1, layer)

  -- prune if over max
  while #World.layers > World.MAX_LAYERS do
    table.remove(World.layers)
  end

  return layer
end

function World.get_surface()
  for _, l in ipairs(World.layers) do
    if l.state == "surface" then return l end
  end
  return nil
end

function World.get_fossils()
  local result = {}
  for _, l in ipairs(World.layers) do
    if l.state == "fossil" or l.state == "buried" then
      result[#result + 1] = l
    end
  end
  return result
end

function World.get_layer_by_depth(d)
  for _, l in ipairs(World.layers) do
    if l.depth == d then return l end
  end
  return nil
end

-- ============ RESTORE ============

function World.restore(layer)
  -- restoration is never perfect
  layer.entropy = math.max(layer.entropy * 0.3, 0.05)
  layer.bit_decay = math.min(layer.bit_decay + 4, 12)  -- max 12, not 16
  layer.freq_ceiling = math.min(layer.freq_ceiling * 2, 14000)  -- max 14k
  layer.noise_floor = layer.noise_floor * 0.5
  layer.energy = math.min(layer.energy + 0.3, 0.8)  -- never fully restored
  -- permanent damage marker
  layer.restored = (layer.restored or 0) + 1
end

-- ============ TICK ============

function World.tick(dt)
  if not World.running then return end

  World.time = World.time + dt

  -- update all layers
  local to_remove = {}
  for i, l in ipairs(World.layers) do
    update_entropy(l, dt)
    if l.energy <= 0 and l.state ~= "surface" then
      to_remove[#to_remove + 1] = i
    end
    -- crystallization check: low entropy + high energy
    if l.entropy < 0.3 and l.energy > 0.7 and not l.crystal then
      -- rare chance
      if math.random() < 0.0005 * dt then
        l.crystal = true
        if World.on_crystal then World.on_crystal(l) end
      end
    end
  end
  -- remove dissolved layers (reverse order)
  for i = #to_remove, 1, -1 do
    table.remove(World.layers, to_remove[i])
  end

  -- tectonic pressure
  update_pressure(dt)
  -- seismic sampling (~2Hz)
  if #World.seismic_history == 0 or
     World.time % 0.5 < dt then
    World.seismic_history[#World.seismic_history + 1] = World.pressure * 0.1
  end

  -- auto quake
  if World.pressure >= World.quake_threshold then
    trigger_quake(World.pressure)
  end
end

-- ============ ACTIONS ============

function World.manual_quake(intensity)
  trigger_quake(intensity or World.pressure)
end

function World.toggle_crystal(freq)
  -- find surface layer
  local s = World.get_surface()
  if s then
    s.crystal = not s.crystal
    if s.crystal and World.on_crystal then
      World.on_crystal(s)
    end
    return s.crystal
  end
  return false
end

function World.reset()
  World.layers = {}
  World.time = 0
  World.pressure = 0
  World.seismic_history = {}
  World.capture_pos = 0
  World.next_surface_pos = World.SURFACE_ZONE[1]
  World.next_deep_pos = World.DEEP_ZONE[1]
  next_id = 1
end

-- ============ HELPERS ============

function World.layer_count() return #World.layers end

function World.avg_entropy()
  if #World.layers == 0 then return 0 end
  local sum = 0
  for _, l in ipairs(World.layers) do sum = sum + l.entropy end
  return sum / #World.layers
end

function World.deepest_depth()
  local d = 0
  for _, l in ipairs(World.layers) do
    if l.depth > d then d = l.depth end
  end
  return d
end

return World
