-- lib/ui.lua
-- strata: 4-page UI + grid

local UI = {}
local World = nil
local Voices = nil
local G = {time = 0}

-- navigation
UI.page = 1
UI.NUM_PAGES = 4
UI.PAGE_NAMES = {"SECTION", "SEISMIC", "MATTER", "ARCHAEO"}

-- page-specific state
UI.matter_layer = 0    -- selected layer index for MATTER page
UI.archaeo_sel = 1     -- selected action for ARCHAEOLOGY
UI.dig_depth = 0
UI.quake_flash = 0

local ARCHAEO_ITEMS = {"DIG", "RESTORE", "EXTRACT", "ARCHIVE"}

function UI.init(world, voices)
  World = world
  Voices = voices
end

-- ============ DRAW ============

function UI.draw(scr)
  local menu_active = _menu and _menu.mode
  if menu_active then return end

  G.time = G.time + 1 / 15
  scr.clear()
  scr.font_face(1)
  scr.font_size(8)

  -- header
  scr.level(2)
  scr.move(1, 7)
  scr.text(UI.PAGE_NAMES[UI.page])
  -- page dots
  for i = 1, UI.NUM_PAGES do
    scr.level(i == UI.page and 10 or 2)
    scr.rect(54 + (i-1)*6, 2, 3, 3)
    scr.fill()
  end
  -- layer count
  scr.level(4)
  scr.move(128, 7)
  scr.text_right("d:" .. World.deepest_depth() .. " n:" .. World.layer_count())

  -- quake flash
  if UI.quake_flash > 0 then
    scr.level(math.floor(UI.quake_flash * 5))
    scr.rect(0, 0, 128, 64)
    scr.stroke()
    UI.quake_flash = UI.quake_flash - 0.3
  end

  -- page content
  if UI.page == 1 then
    UI.draw_section(scr)
  elseif UI.page == 2 then
    UI.draw_seismic(scr)
  elseif UI.page == 3 then
    UI.draw_matter(scr)
  elseif UI.page == 4 then
    UI.draw_archaeo(scr)
  end

  -- footer
  scr.level(1)
  scr.move(1, 63)
  if UI.page == 1 then
    scr.text("E1:time E2:erosion K3:quake")
  elseif UI.page == 2 then
    scr.text("E1:spd E2:press K3:quake")
  elseif UI.page == 3 then
    scr.text("E1:layer E2:scroll E3:adj")
  elseif UI.page == 4 then
    scr.text("E1:sel E3:adj K3:act")
  end

  scr.update()
end

-- ============ PAGE 1: CROSS-SECTION ============

function UI.draw_section(scr)
  local layers = World.layers
  if #layers == 0 then
    scr.level(3)
    scr.move(64, 35)
    scr.text_center("waiting for input...")
    return
  end

  -- draw each layer as horizontal band
  local y_start = 12
  local band_h = math.floor(40 / math.max(#layers, 1))
  band_h = math.min(band_h, 8)

  for i, l in ipairs(layers) do
    local y = y_start + (i-1) * band_h
    if y > 52 then break end

    local brightness = math.floor(l.energy * 12) + 1
    if l.crystal then brightness = 15 end
    scr.level(math.min(15, brightness))

    -- bar width based on layer length (normalized)
    local w = math.floor((l.length / (World.capture_length * 2)) * 120)
    w = math.min(120, math.max(8, w))
    local x = math.floor((128 - w) / 2)

    scr.rect(x, y, w, math.max(2, band_h - 1))
    scr.fill()

    -- state indicator
    scr.level(2)
    scr.move(2, y + band_h - 1)
    if l.state == "surface" then scr.text("S")
    elseif l.state == "buried" then scr.text("B")
    elseif l.state == "fossil" then scr.text("F")
    elseif l.state == "ghost" then scr.text("G")
    end

    -- entropy bar on right
    local ebar = math.floor(l.entropy * 20)
    scr.level(1)
    for b = 0, ebar do
      scr.pixel(126 - b, y + 1)
    end
    scr.fill()
  end

  -- time display
  scr.level(4)
  scr.move(64, 57)
  local t = World.time
  scr.text_center(string.format("%d:%02d", math.floor(t/60), math.floor(t%60)))
end

-- ============ PAGE 2: SEISMIC ============

function UI.draw_seismic(scr)
  -- pressure gauge
  scr.level(6)
  scr.move(128, 7)
  scr.text_right(string.format("P:%.0f%%", World.pressure * 100))

  -- seismograph
  local hist = World.seismic_history
  local y_mid = 35
  scr.level(2)
  scr.move(4, y_mid)
  scr.line(124, y_mid)
  scr.stroke()

  if #hist > 1 then
    local x_step = 120 / math.max(#hist - 1, 1)
    for i = 1, #hist do
      local x = 4 + (i-1) * x_step
      local y = y_mid - hist[i] * 20
      local lev = math.floor(math.abs(hist[i]) * 15 + 2)
      scr.level(math.min(15, lev))
      if i > 1 then
        local px = 4 + (i-2) * x_step
        local py = y_mid - hist[i-1] * 20
        scr.move(px, py)
        scr.line(x, y)
        scr.stroke()
      end
    end
  end

  -- pressure bar
  scr.level(4)
  scr.rect(4, 50, 120, 4)
  scr.stroke()
  local pw = math.floor(World.pressure / World.quake_threshold * 118)
  local plev = World.pressure > World.quake_threshold * 0.8 and 15 or 8
  scr.level(plev)
  scr.rect(5, 51, math.min(118, pw), 2)
  scr.fill()

  -- threshold marker
  scr.level(2)
  local tx = 5 + math.floor(118 * 0.8)
  scr.move(tx, 49)
  scr.line(tx, 55)
  scr.stroke()
end

-- ============ PAGE 3: MATTER ============

function UI.draw_matter(scr)
  local layers = World.layers
  if #layers == 0 then
    scr.level(3)
    scr.move(64, 35)
    scr.text_center("no layers")
    return
  end

  UI.matter_layer = util.clamp(UI.matter_layer, 0, #layers - 1)
  local l = layers[UI.matter_layer + 1]
  if not l then return end

  -- layer selector
  scr.level(10)
  scr.move(128, 7)
  scr.text_right(l.state .. " #" .. l.id)

  -- parameter bars
  local items = {
    {"entropy", l.entropy, string.format("%.0f%%", l.entropy * 100)},
    {"bits", (16 - l.bit_decay) / 14, tostring(l.bit_decay)},
    {"ceiling", 1 - l.freq_ceiling / 20000, string.format("%.1fk", l.freq_ceiling/1000)},
    {"width", l.stereo_width, string.format("%.0f%%", l.stereo_width * 100)},
    {"energy", l.energy, string.format("%.0f%%", l.energy * 100)},
    {"noise", l.noise_floor / 0.25, string.format("%.2f", l.noise_floor)},
  }

  for i, item in ipairs(items) do
    local y = 10 + i * 8
    scr.level(4)
    scr.move(4, y)
    scr.text(item[1])
    -- bar
    scr.level(2)
    scr.rect(50, y - 5, 50, 4)
    scr.stroke()
    local bw = math.floor(item[2] * 48)
    scr.level(i == 1 and 8 or 6)
    scr.rect(51, y - 4, math.max(1, bw), 2)
    scr.fill()
    -- value
    scr.level(4)
    scr.move(105, y)
    scr.text(item[3])
  end

  if l.crystal then
    scr.level(12)
    scr.move(64, 57)
    scr.text_center("CRYSTALLIZED")
  end
end

-- ============ PAGE 4: ARCHAEOLOGY ============

function UI.draw_archaeo(scr)
  for i, name in ipairs(ARCHAEO_ITEMS) do
    local y = 10 + i * 10
    local is_sel = (i == UI.archaeo_sel)
    scr.level(is_sel and 15 or 4)
    scr.move(6, y)
    scr.text((is_sel and "> " or "  ") .. name)

    scr.move(75, y)
    scr.level(is_sel and 8 or 3)
    if i == 1 then      -- DIG
      scr.text("depth: " .. UI.dig_depth)
    elseif i == 2 then  -- RESTORE
      local l = World.get_layer_by_depth(UI.dig_depth)
      if l then
        scr.text(string.format("e:%.0f%%", l.entropy * 100))
      else
        scr.text("--")
      end
    elseif i == 3 then  -- EXTRACT
      local fossils = World.get_fossils()
      scr.text(#fossils .. " fossils")
    elseif i == 4 then  -- ARCHIVE
      scr.text(World.layer_count() .. " layers")
    end
  end
end

-- ============ GRID ============

function UI.grid_draw(g)
  if not g then return end
  g:all(0)

  local layers = World.layers

  -- rows 1-4: world map
  for row = 1, 4 do
    local layer = layers[row]
    if layer then
      local cols = math.floor(layer.length / World.capture_length * 8)
      cols = math.min(8, math.max(1, cols))
      local start_col = math.floor((8 - cols) / 2) + 1
      for c = start_col, start_col + cols - 1 do
        local lev = math.floor(layer.energy * 12) + 1
        if layer.crystal then lev = 15 end
        g:led(c, row, math.min(15, lev))
      end
    end
  end

  -- row 5: tectonic
  -- quake (cols 1-2)
  local qlev = math.floor(World.pressure / World.quake_threshold * 10) + 2
  g:led(1, 5, math.min(15, qlev))
  g:led(2, 5, math.min(15, qlev))
  -- crystal (cols 3-4)
  local surf = World.get_surface()
  local clev = (surf and surf.crystal) and 15 or 4
  g:led(3, 5, clev)
  g:led(4, 5, clev)

  -- row 6: time scale
  local scales = {0.1, 0.5, 1, 2, 4, 8}
  for i, sc in ipairs(scales) do
    local lev = math.abs(World.time_scale - sc) < 0.01 and 15 or 3
    g:led(i, 6, lev)
  end
  g:led(7, 6, World.running and 3 or 15)  -- STOP
  g:led(8, 6, World.time_scale < 0 and 15 or 3)  -- REV

  -- row 7: ghost slots
  local fossils = World.get_fossils()
  for i = 1, 8 do
    local f = fossils[i]
    if f then
      g:led(i, 7, math.floor(f.energy * 10) + 2)
    else
      g:led(i, 7, 1)
    end
  end

  -- row 8: mix levels
  g:led(1, 8, math.floor(Voices.levels.surface * 15))
  g:led(2, 8, math.floor(Voices.levels.surface * 15))
  g:led(3, 8, math.floor(Voices.levels.deep * 15))
  g:led(4, 8, math.floor(Voices.levels.deep * 15))
  g:led(5, 8, math.floor(Voices.levels.ghost * 15))
  g:led(6, 8, math.floor(Voices.levels.ghost * 15))
  g:led(7, 8, math.floor(Voices.levels.crystal * 15))
  g:led(8, 8, 8)  -- master

  g:refresh()
end

function UI.grid_key(x, y, z)
  if z ~= 1 then return end

  -- rows 1-4: dig into layer
  if y >= 1 and y <= 4 then
    local layer = World.layers[y]
    if layer then
      Voices.play_surface(layer)
    end
    return true
  end

  -- row 5: tectonic
  if y == 5 then
    if x <= 2 then
      World.manual_quake(0.5 + x * 0.25)
      UI.quake_flash = 3
    elseif x <= 4 then
      World.toggle_crystal()
    end
    return true
  end

  -- row 6: time scale
  if y == 6 then
    local scales = {0.1, 0.5, 1, 2, 4, 8}
    if x <= 6 then
      World.time_scale = scales[x]
      World.running = true
    elseif x == 7 then
      World.running = not World.running
    elseif x == 8 then
      World.time_scale = -math.abs(World.time_scale)
    end
    return true
  end

  -- row 7: ghost trigger
  if y == 7 then
    local fossils = World.get_fossils()
    if fossils[x] then
      Voices.play_ghost(fossils[x], {
        rate = 0.5,
        reverse = math.random() > 0.5
      })
    end
    return true
  end

  return false
end

-- ============ ENC/KEY HELPERS ============

function UI.next_page()
  UI.page = UI.page % UI.NUM_PAGES + 1
end

function UI.prev_page()
  UI.page = ((UI.page - 2) % UI.NUM_PAGES) + 1
end

return UI
