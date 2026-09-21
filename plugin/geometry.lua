---Pure pane-geometry helpers, over a `tab:panes_with_info()` snapshot taken once per event by the
---caller. Ported from backend-zellij's `has_neighbor()`/`move_or_wrap()`
---(smart-splits-backend-zellij/init.lua) — same algorithm, WezTerm's `PaneInformation` field names
---(`left`/`top`/`width`/`height`/`index`) in place of Zellij's `pane_x`/`pane_y`/`pane_columns`/
---`pane_rows`/`id`. No caching here: the snapshot is already current, taken inside the GUI process
---at the moment of the keypress.
local M = {}

local opposite = {
  left = 'right',
  right = 'left',
  up = 'down',
  down = 'up',
}

---@param a_start number
---@param a_length number
---@param b_start number
---@param b_length number
---@return boolean
local function intervals_overlap(a_start, a_length, b_start, b_length)
  return a_start < b_start + b_length and b_start < a_start + a_length
end

---@param a table PaneInformation
---@param b table PaneInformation
---@param axis 'x'|'y'
---@return boolean
local function axis_overlap(a, b, axis)
  if axis == 'x' then
    return intervals_overlap(a.left, a.width, b.left, b.width)
  end
  return intervals_overlap(a.top, a.height, b.top, b.height)
end

---@param origin table PaneInformation
---@param target table PaneInformation
---@param direction SmartSplitsDirection
---@return boolean in_direction, boolean is_aligned
local function relation(origin, target, direction)
  if direction == 'left' then
    return origin.left > target.left, axis_overlap(origin, target, 'y')
  elseif direction == 'right' then
    return target.left > origin.left, axis_overlap(origin, target, 'y')
  elseif direction == 'up' then
    return origin.top > target.top, axis_overlap(origin, target, 'x')
  else -- 'down'
    return target.top > origin.top, axis_overlap(origin, target, 'x')
  end
end

---Is there a pane bordering `origin` in `direction`, within the same tab?
---@param panes table[] PaneInformation[]
---@param origin table PaneInformation
---@param direction SmartSplitsDirection
---@return boolean
function M.has_neighbor(panes, origin, direction)
  for _, target in ipairs(panes) do
    if target.index ~= origin.index then
      local in_direction, is_aligned = relation(origin, target, direction)
      if in_direction and is_aligned then
        return true
      end
    end
  end
  return false
end

---Panes bordering the tab's far edge in `direction` (i.e. candidates to wrap to), ordered by how
---well they align with `origin`'s span on the perpendicular axis, best first. Empty when `origin`
---is the only pane. Ties (equal overlap, including "no overlap with anything") keep list order,
---which is `panes_with_info()`'s order — deterministic, not meaningful beyond that.
---@param panes table[] PaneInformation[]
---@param origin table PaneInformation
---@param direction SmartSplitsDirection
---@return table[]
function M.far_edge_panes(panes, origin, direction)
  local wrap_direction = opposite[direction]
  local candidates = {}
  local best_delta = -1

  for _, target in ipairs(panes) do
    if target.index ~= origin.index then
      local delta
      if wrap_direction == 'left' then
        delta = origin.left - target.left
      elseif wrap_direction == 'right' then
        delta = (target.left + target.width) - origin.left
      elseif wrap_direction == 'up' then
        delta = origin.top - target.top
      else -- 'down'
        delta = (target.top + target.height) - origin.top
      end

      if delta > best_delta then
        best_delta = delta
        candidates = { target }
      elseif delta == best_delta then
        table.insert(candidates, target)
      end
    end
  end

  if #candidates <= 1 then
    return candidates
  end

  -- tie-break: prefer the candidate overlapping origin's span the most on the perpendicular axis
  local axis = (direction == 'left' or direction == 'right') and 'y' or 'x'
  local function overlap_amount(target)
    if axis == 'y' then
      local lo = math.max(origin.top, target.top)
      local hi = math.min(origin.top + origin.height, target.top + target.height)
      return math.max(0, hi - lo)
    end
    local lo = math.max(origin.left, target.left)
    local hi = math.min(origin.left + origin.width, target.left + target.width)
    return math.max(0, hi - lo)
  end

  -- `table.sort` is not stable (ties may have their relative order changed), so a tie in
  -- overlap_amount is broken explicitly by original list order below, rather than left to
  -- whatever the sort happens to do — that's what actually makes the "ties keep list order"
  -- guarantee above true
  local indexed = {}
  for i, target in ipairs(candidates) do
    indexed[i] = { target = target, order = i, overlap = overlap_amount(target) }
  end

  table.sort(indexed, function(a, b)
    if a.overlap ~= b.overlap then
      return a.overlap > b.overlap
    end
    return a.order < b.order
  end)

  local sorted = {}
  for i, entry in ipairs(indexed) do
    sorted[i] = entry.target
  end
  return sorted
end

return M
