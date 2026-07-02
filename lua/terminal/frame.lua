-- terminal.nvim: pure frame-tree layout engine
--
-- A Lua port of Neovim's window frame model (src/nvim/window.c). A tab's pane
-- layout is a tree of nodes:
--
--   leaf:   { t = "leaf", buf = <bufnr>, w = <cols>, h = <rows> }
--   branch: { t = "row"|"col", children = {node...}, w = <cols>, h = <rows> }
--
-- "row" children sit side by side (vsplit), "col" children are stacked
-- (split). Sizes are content cells; siblings are separated by 1 cell, so a
-- branch dimension along its axis is sum(children) + (#children - 1).
--
-- Invariant (same as vim frames): a row never directly contains a row, a col
-- never a col. Upheld at split() and re-established by flatten() after
-- remove().
--
-- No vim API is used here; everything is unit-testable. Structural functions
-- take and return the root (the root node can be replaced).

local M = {}

local MIN = 1 -- winminwidth/winminheight equivalent

local function other_axis(t)
	return t == "row" and "col" or "row"
end

-- Axis helpers: dimension governed by a branch type.
-- A row divides width among children; a col divides height.
local function axis_dim(t)
	return t == "row" and "w" or "h"
end

local function dim_axis(dim)
	return dim == "w" and "row" or "col"
end

function M.is_leaf(node)
	return node.t == "leaf"
end

-- DFS leaf buffers, topleft to bottomright (matches vim window order).
function M.leaves(node, out)
	out = out or {}
	if node.t == "leaf" then
		table.insert(out, node.buf)
	else
		for _, child in ipairs(node.children) do
			M.leaves(child, out)
		end
	end
	return out
end

-- DFS leaf nodes (not just bufs), same order as leaves().
function M.leaf_nodes(node, out)
	out = out or {}
	if node.t == "leaf" then
		table.insert(out, node)
	else
		for _, child in ipairs(node.children) do
			M.leaf_nodes(child, out)
		end
	end
	return out
end

function M.leaf_count(node)
	if node.t == "leaf" then
		return 1
	end
	local n = 0
	for _, child in ipairs(node.children) do
		n = n + M.leaf_count(child)
	end
	return n
end

-- Path from root to the leaf holding buf: a list of {node=, idx=} entries
-- where idx is the node's position in its parent (idx of entry 1 is nil).
-- Returns nil when buf is not in the tree.
local function find_path(node, buf, path)
	path = path or {}
	table.insert(path, { node = node })
	if node.t == "leaf" then
		if node.buf == buf then
			return path
		end
	else
		for i, child in ipairs(node.children) do
			local depth = #path
			if find_path(child, buf, path) then
				path[depth + 1].idx = i
				return path
			end
		end
	end
	table.remove(path)
	return nil
end

function M.find(root, buf)
	return find_path(root, buf)
end

-- frame2win: representative buf of a frame (descend first children).
function M.first_leaf_buf(node)
	while node.t ~= "leaf" do
		node = node.children[1]
	end
	return node.buf
end

-- Minimum size of a frame in a dimension (frame_minwidth/minheight).
function M.min_size(node, dim)
	if node.t == "leaf" then
		return MIN
	end
	if axis_dim(node.t) == dim then
		-- children share this dimension out, plus separators
		local total = #node.children - 1
		for _, child in ipairs(node.children) do
			total = total + M.min_size(child, dim)
		end
		return total
	end
	-- children all span this dimension: min is the largest child min
	local max = MIN
	for _, child in ipairs(node.children) do
		local m = M.min_size(child, dim)
		if m > max then
			max = m
		end
	end
	return max
end

--------------------------------------------------------------------------------
-- frame_new_height / frame_new_width: propagate a size change into a subtree
--------------------------------------------------------------------------------

-- Set node's `dim` to `size`, distributing the change inside the subtree.
-- topfirst: for a same-axis branch, resize the first child first (used by
-- drag so shrinking happens from the edge nearest the separator); default
-- resizes the last child first (vim's bottom/right-first).
function M.new_size(node, dim, size, topfirst)
	if node.t == "leaf" then
		node[dim] = size
		return
	end

	if axis_dim(node.t) ~= dim then
		-- cross axis: every child spans the full dimension
		for _, child in ipairs(node.children) do
			M.new_size(child, dim, size, topfirst)
		end
		node[dim] = size
		return
	end

	-- same axis: children divide `size - separators` between them
	local extra = size - node[dim]
	node[dim] = size
	local n = #node.children
	local order = {}
	if topfirst then
		for i = 1, n do
			order[i] = i
		end
	else
		for i = 1, n do
			order[i] = n - i + 1
		end
	end

	if extra >= 0 then
		-- grow: all extra goes to the first frame in resize order
		local child = node.children[order[1]]
		M.new_size(child, dim, child[dim] + extra, topfirst)
	else
		-- shrink: walk frames reducing toward their minimum, carrying overflow
		local remaining = -extra
		for _, i in ipairs(order) do
			if remaining <= 0 then
				break
			end
			local child = node.children[i]
			local min = M.min_size(child, dim)
			local give = math.min(child[dim] - min, remaining)
			if give > 0 then
				M.new_size(child, dim, child[dim] - give, topfirst)
				remaining = remaining - give
			end
		end
		-- remaining > 0 means the caller ignored min_size; clamp silently
	end
end

--------------------------------------------------------------------------------
-- split
--------------------------------------------------------------------------------

-- Split the leaf holding at_buf in direction dir ("row" = vsplit, "col" =
-- split). The new leaf goes after the current one (splitbelow/splitright
-- convention, matching the plugin's existing vsplit). New pane gets half the
-- space (integer division), old keeps the rest minus the 1-cell separator.
-- Returns root, err.
function M.split(root, at_buf, dir, new_buf)
	local path = find_path(root, at_buf)
	if not path then
		return root, "buf not found"
	end
	local leaf = path[#path].node
	local dim = axis_dim(dir)

	local cur = leaf[dim]
	if cur < 2 * MIN + 1 then
		return root, "E36: Not enough room"
	end
	local new_size = math.floor(cur / 2)
	local old_size = cur - new_size - 1

	local new_leaf = { t = "leaf", buf = new_buf, w = leaf.w, h = leaf.h }
	new_leaf[dim] = new_size

	local parent_entry = path[#path - 1]
	local parent = parent_entry and parent_entry.node

	leaf[dim] = old_size

	if parent and parent.t == dir then
		-- same direction: insert as a direct sibling (no new branch)
		table.insert(parent.children, path[#path].idx + 1, new_leaf)
		return root
	end

	-- different direction (or leaf is root): promote the leaf in place
	local branch = { t = dir, w = leaf.w, h = leaf.h, children = { leaf, new_leaf } }
	branch[dim] = cur
	if not parent then
		return branch
	end
	parent.children[path[#path].idx] = branch
	return root
end

--------------------------------------------------------------------------------
-- flatten / remove
--------------------------------------------------------------------------------

-- Re-establish the invariant: collapse single-child branches and splice
-- same-type nested branches into their parent (frame_flatten, applied
-- globally). Returns the (possibly new) root.
function M.flatten(node)
	if node.t == "leaf" then
		return node
	end
	local out = {}
	for _, child in ipairs(node.children) do
		child = M.flatten(child)
		if child.t == node.t then
			for _, grandchild in ipairs(child.children) do
				table.insert(out, grandchild)
			end
		else
			table.insert(out, child)
		end
	end
	node.children = out
	if #out == 1 then
		local only = out[1]
		only.w = node.w
		only.h = node.h
		return only
	end
	return node
end

-- Remove the leaf holding buf. The freed space goes to the next sibling, or
-- the previous one when the leaf is last (win_altframe rule). Returns
-- root, absorbing_buf; root is nil when the last leaf was removed.
function M.remove(root, buf)
	local path = find_path(root, buf)
	if not path then
		return root, nil
	end
	if #path == 1 then
		return nil, nil -- removing the only pane
	end

	local leaf = path[#path].node
	local idx = path[#path].idx
	local parent = path[#path - 1].node
	local dim = axis_dim(parent.t)

	local absorber_idx = idx < #parent.children and idx + 1 or idx - 1
	local absorber = parent.children[absorber_idx]
	-- absorber grows from the edge facing the removed frame
	local topfirst = absorber_idx > idx
	M.new_size(absorber, dim, absorber[dim] + leaf[dim] + 1, topfirst)

	table.remove(parent.children, idx)
	local absorb_buf = M.first_leaf_buf(absorber)
	return M.flatten(root), absorb_buf
end

--------------------------------------------------------------------------------
-- set_size (frame_setheight / frame_setwidth)
--------------------------------------------------------------------------------

local function setsize_frame(path, at, dim, size)
	local node = path[at].node
	local parent_entry = path[at - 1]
	if not parent_entry then
		-- root: fixed outer geometry, nothing to take space from
		return
	end
	local parent = parent_entry.node
	local idx = path[at].idx

	if axis_dim(parent.t) ~= dim then
		-- cross-direction parent: the whole row/col must resize together
		size = math.max(size, M.min_size(parent, dim))
		setsize_frame(path, at - 1, dim, size)
		return
	end

	-- same-direction parent: take from / give to siblings
	local room = node[dim]
	for i, sib in ipairs(parent.children) do
		if i ~= idx then
			room = room + sib[dim] - M.min_size(sib, dim)
		end
	end
	size = math.max(math.min(size, room), M.min_size(node, dim))

	local take = size - node[dim]
	if take == 0 then
		return
	end
	M.new_size(node, dim, size)

	-- two runs: next siblings first (below/right), then previous siblings
	for run = 1, 2 do
		local step = run == 1 and 1 or -1
		local i = idx + step
		while take ~= 0 and parent.children[i] do
			local sib = parent.children[i]
			local min = M.min_size(sib, dim)
			if take > 0 then
				local give = math.min(sib[dim] - min, take)
				if give > 0 then
					-- shrink from the edge facing the resized frame
					M.new_size(sib, dim, sib[dim] - give, step == 1)
					take = take - give
				end
			else
				-- shrinking the frame: the nearest next sibling takes it all
				M.new_size(sib, dim, sib[dim] - take, step == 1)
				take = 0
			end
			i = i + step
		end
	end
end

-- Set the leaf holding buf to `size` in dimension dim ("w"/"h"), cascading
-- through neighbors exactly like CTRL-W +/-/</> (vim frame_setheight).
function M.set_size(root, buf, dim, size)
	local path = find_path(root, buf)
	if not path then
		return root
	end
	size = math.max(size, MIN)
	setsize_frame(path, #path, dim, size)
	return root
end

--------------------------------------------------------------------------------
-- equalize (win_equal_rec)
--------------------------------------------------------------------------------

-- Number of leaf windows arranged along an axis: proportional weight used by
-- vim's win_equal_rec (a nested split holding 2 windows gets twice the room).
local function wincount(node, dim)
	if node.t == "leaf" then
		return 1
	end
	if axis_dim(node.t) == dim then
		local n = 0
		for _, child in ipairs(node.children) do
			n = n + wincount(child, dim)
		end
		return n
	end
	local max = 1
	for _, child in ipairs(node.children) do
		local n = wincount(child, dim)
		if n > max then
			max = n
		end
	end
	return max
end

-- Distribute w x h among the subtree equally (CTRL-W =): proportional to
-- leaf-window count, round-to-nearest, last child absorbs the remainder.
function M.equalize(node, w, h)
	node.w = w
	node.h = h
	if node.t == "leaf" then
		return
	end

	local dim = axis_dim(node.t)
	local total = dim == "w" and w or h
	local avail = total - (#node.children - 1)

	local mins, counts = {}, {}
	local room, totwin = avail, 0
	for i, child in ipairs(node.children) do
		mins[i] = M.min_size(child, dim)
		counts[i] = wincount(child, dim)
		room = room - mins[i]
		totwin = totwin + counts[i]
	end

	local used = 0
	for i, child in ipairs(node.children) do
		local size
		if i == #node.children then
			size = avail - used -- last child soaks up the rounding remainder
		else
			size = mins[i] + math.floor((counts[i] * room + math.floor(totwin / 2)) / totwin)
			room = room - (size - mins[i])
			totwin = totwin - counts[i]
		end
		used = used + size
		if dim == "w" then
			M.equalize(child, size, h)
		else
			M.equalize(child, w, size)
		end
	end
end

--------------------------------------------------------------------------------
-- rects
--------------------------------------------------------------------------------

-- Grid rectangles for every leaf, plus separator segments. Origin (row, col)
-- is the top-left of the layout area. Returns:
--   rects: { [buf] = {row=, col=, w=, h=} }
--   seps:  list of { axis = "v"|"h", row=, col=, len=, node=<branch>, idx=<i> }
--          (the separator between children idx and idx+1 of `node`)
local function walk_rects(node, row, col, rects, seps)
	if node.t == "leaf" then
		rects[node.buf] = { row = row, col = col, w = node.w, h = node.h }
		return
	end
	if node.t == "row" then
		local c = col
		for i, child in ipairs(node.children) do
			walk_rects(child, row, c, rects, seps)
			c = c + child.w
			if i < #node.children then
				table.insert(seps, { axis = "v", row = row, col = c, len = node.h, node = node, idx = i })
				c = c + 1
			end
		end
	else
		local r = row
		for i, child in ipairs(node.children) do
			walk_rects(child, r, col, rects, seps)
			r = r + child.h
			if i < #node.children then
				table.insert(seps, { axis = "h", row = r, col = col, len = node.w, node = node, idx = i })
				r = r + 1
			end
		end
	end
end

function M.rects(root, row, col)
	local rects, seps = {}, {}
	walk_rects(root, row or 0, col or 0, rects, seps)
	return rects, seps
end

-- The separator segment covering grid cell (row, col), or nil.
function M.sep_at(root, row, col, origin_row, origin_col)
	local _, seps = M.rects(root, origin_row or 0, origin_col or 0)
	for _, sep in ipairs(seps) do
		if sep.axis == "v" then
			if col == sep.col and row >= sep.row and row < sep.row + sep.len then
				return sep
			end
		else
			if row == sep.row and col >= sep.col and col < sep.col + sep.len then
				return sep
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- navigate (win_vert_neighbor / win_horz_neighbor)
--------------------------------------------------------------------------------

-- Directional navigation. dir is "h"/"j"/"k"/"l"; cursor is the absolute grid
-- cell {row=, col=} of the cursor inside the current pane (same origin as the
-- rects used for descent). Returns the target buf (may be from_buf when
-- there's no neighbor).
function M.navigate(root, from_buf, dir, count, cursor)
	count = count or 1
	local vertical = dir == "j" or dir == "k"
	local back = dir == "k" or dir == "h" -- toward prev siblings
	local branch_t = vertical and "col" or "row"
	-- positions for every node (branches included), for the descent rule
	local rects = {}
	local function annotate(node, row, col)
		rects[node] = { row = row, col = col }
		if node.t == "leaf" then
			return
		end
		local r, c = row, col
		for _, child in ipairs(node.children) do
			annotate(child, r, c)
			if node.t == "row" then
				c = c + child.w + 1
			else
				r = r + child.h + 1
			end
		end
	end
	annotate(root, 0, 0)

	local path = find_path(root, from_buf)
	if not path then
		return from_buf
	end

	local found = path[#path]
	for _ = 1, count do
		-- phase A: walk up to find a sibling in the wanted direction
		local at = #path
		local nfr
		while true do
			if at == 1 then
				return found.node.buf
			end
			local parent = path[at - 1].node
			local idx = path[at].idx
			local sib_idx = back and idx - 1 or idx + 1
			if parent.t == branch_t and parent.children[sib_idx] then
				nfr = parent.children[sib_idx]
				break
			end
			at = at - 1
		end

		-- phase B: descend into the sibling toward the cursor position
		while nfr.t ~= "leaf" do
			local children = nfr.children
			local pick = children[1]
			if nfr.t == other_axis(branch_t) then
				-- entering a cross frame: choose the child under the cursor
				local i = 1
				while i < #children do
					local rect = rects[children[i]]
					local edge, cur
					if vertical then
						edge = rect.col + children[i].w
						cur = cursor.col
					else
						edge = rect.row + children[i].h
						cur = cursor.row
					end
					if edge > cur then
						break
					end
					i = i + 1
				end
				pick = children[i]
			elseif back then
				-- moving up/left through a same-direction frame: nearest child
				pick = children[#children]
			end
			nfr = pick
		end

		-- rebuild the path for the next iteration
		path = find_path(root, nfr.buf)
		found = path[#path]
	end
	return found.node.buf
end

--------------------------------------------------------------------------------
-- rotate / exchange (win_rotate / win_exchange)
--------------------------------------------------------------------------------

-- Rotate the sibling slots of buf's parent frame (CTRL-W r/R). Buffers move
-- through fixed-size slots (geometry is preserved), so only the leaf .buf
-- fields rotate. E443 when a sibling is itself split. Focus should stay on
-- the same buf (it moves with the rotation), matching vim.
function M.rotate(root, buf, upwards, count)
	local path = find_path(root, buf)
	if not path or #path < 2 then
		return root, "only one pane"
	end
	local parent = path[#path - 1].node
	for _, sib in ipairs(parent.children) do
		if sib.t ~= "leaf" then
			return root, "E443: Cannot rotate when another window is split"
		end
	end
	local n = #parent.children
	for _ = 1, (count or 1) % n do
		if upwards then
			local first = parent.children[1].buf
			for i = 1, n - 1 do
				parent.children[i].buf = parent.children[i + 1].buf
			end
			parent.children[n].buf = first
		else
			local last = parent.children[n].buf
			for i = n, 2, -1 do
				parent.children[i].buf = parent.children[i - 1].buf
			end
			parent.children[1].buf = last
		end
	end
	return root
end

-- Exchange buf with the count'th sibling of its parent frame (or next/prev
-- without count). Leaf-only targets, silent no-op otherwise (vim behavior).
-- Returns root, other_buf; focus should move to other_buf — vim keeps the
-- cursor in the same screen slot, which now shows the other buffer.
function M.exchange(root, buf, count)
	local path = find_path(root, buf)
	if not path or #path < 2 then
		return root, nil
	end
	local parent = path[#path - 1].node
	local idx = path[#path].idx
	local target
	if count and count > 0 then
		target = parent.children[count]
	elseif parent.children[idx + 1] then
		target = parent.children[idx + 1]
	else
		target = parent.children[idx - 1]
	end
	if not target or target.t ~= "leaf" or target.buf == buf then
		return root, nil
	end
	local leaf = path[#path].node
	leaf.buf, target.buf = target.buf, leaf.buf
	return root, leaf.buf
end

--------------------------------------------------------------------------------
-- splitmove (CTRL-W H/J/K/L)
--------------------------------------------------------------------------------

-- Move buf's pane to an edge of the whole layout as a full-width/full-height
-- window. edge: "left"/"right" (H/L, full height) or "top"/"bottom" (J/K,
-- full width). size: optional target size in the split dimension; defaults to
-- half, and for top/bottom the pane's original height is preserved (vim).
function M.splitmove(root, buf, edge, size)
	local path = find_path(root, buf)
	if not path then
		return root
	end
	if #path == 1 then
		return root -- only pane
	end

	local vertical = edge == "left" or edge == "right"
	local dir = vertical and "row" or "col"
	local dim = axis_dim(dir)
	local before = edge == "left" or edge == "top"
	local leaf = path[#path].node
	local old_h = leaf.h

	local W, H = root.w, root.h
	local new_root = select(1, M.remove(root, buf))
	if new_root == nil then
		return root
	end

	local total = dim == "w" and W or H
	local leaf_size
	if size and size > 0 then
		leaf_size = size
	elseif not vertical and old_h > 0 then
		leaf_size = old_h -- J/K preserve the window's height
	else
		leaf_size = math.floor(total / 2)
	end
	leaf_size = math.max(MIN, math.min(leaf_size, total - M.min_size(new_root, dim) - 1))
	local rest = total - leaf_size - 1

	leaf.w = vertical and leaf_size or W
	leaf.h = vertical and H or leaf_size

	M.new_size(new_root, dim, rest, false)
	M.new_size(new_root, dim == "w" and "h" or "w", dim == "w" and H or W, false)

	if new_root.t == dir then
		table.insert(new_root.children, before and 1 or #new_root.children + 1, leaf)
		new_root[dim] = total
		return new_root
	end
	local children = before and { leaf, new_root } or { new_root, leaf }
	local branch = { t = dir, w = W, h = H, children = children }
	return branch
end

--------------------------------------------------------------------------------
-- drag (win_drag_vsep_line / win_drag_status_line)
--------------------------------------------------------------------------------

-- Drag the separator between children sep.idx and sep.idx+1 of sep.node by
-- delta cells (positive = right/down). The growing side gains at its edge
-- nearest the separator; the shrinking side cascades away from it.
function M.drag(root, sep, delta)
	if delta == 0 then
		return root
	end
	local parent = sep.node
	local dim = sep.axis == "v" and "w" or "h"
	local idx = sep.idx

	local grow_from, shrink_from, step
	if delta > 0 then
		grow_from, shrink_from, step = idx, idx + 1, 1
	else
		grow_from, shrink_from, step = idx + 1, idx, -1
		delta = -delta
	end

	local room = 0
	local i = shrink_from
	while parent.children[i] do
		room = room + parent.children[i][dim] - M.min_size(parent.children[i], dim)
		i = i + step
	end
	delta = math.min(delta, room)
	if delta <= 0 then
		return root
	end

	local grow = parent.children[grow_from]
	-- grow at the edge facing the separator
	M.new_size(grow, dim, grow[dim] + delta, step == 1 and false or true)

	local remaining = delta
	i = shrink_from
	while parent.children[i] and remaining > 0 do
		local child = parent.children[i]
		local min = M.min_size(child, dim)
		local give = math.min(child[dim] - min, remaining)
		if give > 0 then
			-- shrink from the edge nearest the separator
			M.new_size(child, dim, child[dim] - give, step == 1)
			remaining = remaining - give
		end
		i = i + step
	end
	return root
end

--------------------------------------------------------------------------------
-- rescale / shape
--------------------------------------------------------------------------------

-- Proportionally resize the whole tree to new outer dimensions (used when the
-- saved layout is reopened at a different terminal size).
function M.rescale(node, w, h)
	if node.t == "leaf" then
		node.w = w
		node.h = h
		return
	end

	local dim = axis_dim(node.t)
	local old_avail = 0
	for _, child in ipairs(node.children) do
		old_avail = old_avail + child[dim]
	end
	local new_avail = (dim == "w" and w or h) - (#node.children - 1)

	local used = 0
	for i, child in ipairs(node.children) do
		local size
		if i == #node.children then
			size = new_avail - used
		elseif old_avail > 0 then
			size = math.max(MIN, math.floor(child[dim] * new_avail / old_avail))
		else
			size = math.max(MIN, math.floor(new_avail / #node.children))
		end
		size = math.min(size, new_avail - used - (#node.children - i))
		used = used + size
		if dim == "w" then
			M.rescale(child, size, h)
		else
			M.rescale(child, w, size)
		end
	end
	node.w = w
	node.h = h
end

-- Overwrite leaf sizes from a DFS-ordered list of {w=,h=} (real window
-- dimensions) and recompute branch dimensions bottom-up. Keeps the tree in
-- sync with what's actually on screen.
function M.set_leaf_sizes(node, sizes, counter)
	counter = counter or { i = 0 }
	if node.t == "leaf" then
		counter.i = counter.i + 1
		local s = sizes[counter.i]
		if s then
			node.w = s.w
			node.h = s.h
		end
		return node.w, node.h
	end
	local total_w, total_h = 0, 0
	for k, child in ipairs(node.children) do
		local cw, ch = M.set_leaf_sizes(child, sizes, counter)
		if node.t == "row" then
			total_w = total_w + cw + (k > 1 and 1 or 0)
			total_h = math.max(total_h, ch)
		else
			total_h = total_h + ch + (k > 1 and 1 or 0)
			total_w = math.max(total_w, cw)
		end
	end
	node.w = total_w
	node.h = total_h
	return node.w, node.h
end

-- Structural equality ignoring bufs and sizes (fast-path tab switching).
function M.same_shape(a, b)
	if a.t ~= b.t then
		return false
	end
	if a.t == "leaf" then
		return true
	end
	if #a.children ~= #b.children then
		return false
	end
	for i = 1, #a.children do
		if not M.same_shape(a.children[i], b.children[i]) then
			return false
		end
	end
	return true
end

-- Build a single-row tree from a flat buf list (v3 migration and new tabs).
function M.from_bufs(bufs, widths, w, h)
	if #bufs == 1 then
		return { t = "leaf", buf = bufs[1], w = w, h = h }
	end
	local children = {}
	for i, buf in ipairs(bufs) do
		table.insert(children, {
			t = "leaf",
			buf = buf,
			w = widths and widths[i] or MIN,
			h = h,
		})
	end
	local root = { t = "row", w = w, h = h, children = children }
	if not widths then
		M.rescale(root, w, h)
	end
	return root
end

return M
