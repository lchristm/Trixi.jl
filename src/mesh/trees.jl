module Trees

using StaticArrays: MVector


abstract type AbstractContainer end
abstract type AbstractTree{D<:Integer} <: AbstractContainer end


mutable struct Tree{D} <: AbstractTree{D}
  parent_ids::Vector{Int}
  child_ids::Matrix{Int}
  neighbor_ids::Matrix{Int}
  levels::Vector{Int}
  coordinates::Matrix{Float64}

  capacity::Int
  size::Int
  dummy::Int

  center::MVector{D, Float64}
  length::Float64

  function Tree{D}(capacity::Int, center::AbstractArray{Float64}, length::Float64) where D
    # Create instance
    b = new()

    # Initialize fields with defaults
    # Note: size as capacity + 1 is to use `capacity + 1` as temporary storage for swap operations
    b.parent_ids = Vector{Int}(0, capacity + 1)
    b.child_ids = Matrix{Int}(0, 2^D, capacity + 1)
    b.neighbor_ids = Matrix{Int}(0, 2*D, capacity + 1)
    b.levels = Vector{Int}(-1, capacity + 1)
    b.coordinates = Matrix{Float64}(NaN, D, capacity + 1)

    b.capacity = capacity
    b.size = 0
    b.dummy = capacity + 1

    b.center = center
    b.length = length

    # Create initial node
    b.size += 1
    b.levels[1] = 0
    b.coordinates[:, 1] = b.center
  end
end

Tree(::Val{D}, args...) where D = Tree{D}(args...)


has_parent(t::Tree, node_id::Int) = t.parent_ids[node_id] > 0
has_child(t::Tree, node_id::Int, child_id::Int) = t.parent_ids[child_id, node_id] > 0
has_children(t::Tree, node_id::Int) = n_children(t, node_id) > 0
n_children(t::Tree, node_id::Int) = count(x -> (x > 0), @view t.child_ids[:, node_id])
has_neighbor(t::Tree, node_id::Int, direction::Int) = t.neighbor_ids[direction, node_id] > 0
function has_any_neighbor(t::Tree, node_id::Int, direction::Int)
  return (has_neighbor(t, node_id, direction) ||
         (has_parent(t, node_id) && has_neighbor(t, t.parent_ids[node_id], direction)))
end

n_children_per_node(::Tree{D}) where D = 2^D
n_neighbors_per_node(::Tree{D}) where D = 2 * D
opposite_neighbor(direction::Int) = direction + 1 - 2 * ((direction + 1) % 2)


function invalidate!(t::Tree, first::Int, last::Int)
  @assert first > 0
  @assert first <= last
  @assert last <= t.capacity + 1

  b.parent_ids[first:last] = 0
  b.child_ids[:, first:last] = 0
  b.neighbor_ids[:, first:last] = 0
  b.levels[first:last] = -1
  b.coordinates[:, first:last] = NaN
end
invalidate!(t::Tree, id::Int) = invalidate!(t, id, id)
invalidate!(t::Tree) = invalidate!(t, 1, size(t))


# Delete connectivity with parents/children/neighbors before nodes are erased
function delete_connectivity!(t::Tree, first::Int, last::Int)
  @assert first > 0
  @assert first <= last
  @assert last <= t.capacity + 1

  # Iterate over all cells
  for node_id in first:last
    # Delete connectivity from parent node
    if has_parent(t, node_id)
      parent_id = t.parent_ids[node_id]
      for child in 1:n_children_per_node(t)
        if t.child_ids[child, parent_id] == node_id
          t.child_ids[child, parent_id] = 0
          break
        end
      end
    end

    # Delete connectivity from child nodes
    for child in 1:n_children_per_node(t)
      if has_child(t, node_id, child)
        t.parent_ids[t._child_ids[child, node_id]] = 0
      end
    end

    # Delete connectivity from neighboring nodes
    for neighbor in 1:n_neighbors_per_node(t)
      if has_neighbor(t, node_id, neighbor)
        t.neighbor_ids[opposite_neighbor(neighbor), t.neighbor_ids[neighbor, node_id]] = 0
      end
    end
  end
end


# Move connectivity with parents/children/neighbors after nodes have been moved
function move_connectivity!(t::Tree, first::Int, last::Int, destination::Int)
  @assert first > 0
  @assert first <= last
  @assert last <= t.capacity + 1
  @assert destination > 0
  @assert destination <= t.capacity + 1

  # Strategy
  # 1) Loop over moved nodes (at target location)
  # 2) Check if parent/children/neighbors connections are to a node that was moved
  #    a) if node was moved: apply offset to current node
  #    b) if node was not moved: go to connected node and update connectivity there

  offset = destination - first
  has_moved(n) = (first <= n <= last)

  for source in first:last
    target = source + offset

    # Update parent
    if has_parent(t, target)
      # Get parent node
      parent_id = t.parent_ids[target]
      if has_moved(parent_id)
        # If parent itself was moved, just update parent id accordingly
        t.parent_ids[target] += offset
      else
        # If parent was not moved, update its corresponding child id
        for child in 1:n_children_per_node(t)
          if t.child_ids[child, parent_id] == source
            t.child_ids[child, parent_id] = target
          end
        end
      end
    end

    # Update children
    for child in 1:n_children_per_node(t)
      if has_child(t, target, child)
        # Get child node
        child_id = t.child_ids[child, target]
        if has_moved(child_id)
          # If child itself was moved, just update child id accordingly
          t.child_ids[child_id, target] += offset
        else
          # If child was not moved, update its parent id
          t.parent_ids[child_id] = target
        end
      end
    end

    # Update neighbors
    for neighbor in 1:n_neighbors_per_node(t)
      if has_neighbor(t, target, neighbor)
        # Get neighbor node
        neighbor_id = t.neighbor_ids[neighbor, target]
        if has_moved(neighbor_id)
          # If neighbor itself was moved, just update neighbor id accordingly
          t.neighbor_ids[neighbor, target] += offset
        else
          # If neighbor was not moved, update its opposing neighbor id
          t.neighbor_ids[opposite_neighbor(neighbor), neighbor_id] = source
        end
      end
    end
  end
end


# Raw copy operation for ranges of cells
function raw_copy!(target::Tree, source::Tree, first::Int, last::Int, destination::Int)
  copy_data!(target.parent_ids, source.parent_ids, first, last, destination)
  copy_data!(target.child_ids, source.child_ids, first, last, destination,
             n_children_per_node(target))
  copy_data!(target.neighbor_ids, source.neighbor_ids, first, last,
             destination, n_neighbors_per_node(target))
  copy_data!(target.levels, source.levels, first, last, destination)
  copy_data!(target.coordinates, source.coordinates, first, last, destination)
end
function raw_copy!(c::AbstractContainer, first::Int, last::Int, destination::Int)
  raw_copy!(c, c, first, last, destination)
end
function raw_copy!(target::AbstractContainer, source::AbstractContainer,
                   from::Int, destination::Int)
  raw_copy!(target, source, from, from, destination)
end
function raw_copy!(c::AbstractContainer, from::Int, destination::Int)
  raw_copy!(c, c, from, from, destination)
end


# Reset data structures
function reset_data_structures!(t::Tree{D}) where D
  t.parent_ids = Vector{Int}(0, t.capacity + 1)
  t.child_ids = Matrix{Int}(0, 2^D, t.capacity + 1)
  t.neighbor_ids = Matrix{Int}(0, 2*D, t.capacity + 1)
  t.levels = Vector{Int}(-1, t.capacity + 1)
  t.coordinates = Matrix{Float64}(NaN, D, t.capacity + 1)
end


# Auxiliary copy function
function copy_data!(target::AbstractArray{T, N}, source::AbstractArray{T, N},
                    first::Int, last::Int, destination::Int, block_size::Int=1) where {T, N}
  # Determine block size for each index
  block_size = 1
  for d in 1:(ndims(target) - 1)
    block_size *= size(target, d)
  end

  if destination <= first || destination > last
    # In this case it is safe to copy forward (left-to-right) without overwriting data
    for i in first:last, j in 1:block_size
      target[block_size*(i-1) + j] = source[block_size*(i-1) + j]
    end
  else
    # In this case we need to copy backward (right-to-left) to prevent overwriting data
    for i in reverse(first:last), j in 1:block_size
      target[block_size*(i-1) + j] = source[block_size*(i-1) + j]
    end
  end
end


####################################################################################################
# Here follows the implementation for a generic container
####################################################################################################

# Inquire about capacity and size
capacity(c::AbstractContainer) = c.capacity
size(c::AbstractContainer) = c.size

# Methods for extending or shrinking the size at the end of the container
function append!(c::AbstractContainer, count::Int)
  @assert count >= 0
  size(c) + count <= capacity(c) || error("new size exceeds container capacity of $(capacity(c))")

  invalidate(c, size(c) + 1, size(c) + count)
end
append!(c::AbstractContainer) = append(c, 1)
function shrink!(c::AbstractContainer, count::Int)
  @assert count >= 0
  @assert size(c) >= count

  remove_shift(c, size(c) + 1 - count, size())
end
shrink!(c::AbstractContainer) = shrink(c, 1)

function copy!(target::AbstractContainer, source::AbstractContainer,
               first::Int, last::Int, destination::Int)
  @assert 0 <= first <= size(source) "First node out of range"
  @assert 0 <= last <= size(source) "Last node out of range"
  @assert 0 <= destination <= size(target) "Destination out of range"
  @assert destination + (last - first) <= size(target) "Target range out of bounds"

  # Return if copy would be a no-op
  if last < first || (source === target && first == destination)
    return
  end

  raw_copy!(target, source, first, last, destination)
end
function copy!(target::AbstractContainer, source::AbstractContainer, from::Int, destination::Int)
  copy!(target, source, from, from, destination)
end
function copy!(c::AbstractContainer, first::Int, last::Int, destination::Int)
  copy!(c, c, first, last, destination)
end
function copy!(c::AbstractContainer, from::Int, destination::Int)
  copy!(c, c, from, from, destination)
end

function move!(c::AbstractContainer, first::Int, last::Int, destination::Int)
  @assert 0 <= first <= size(c) "First node out of range"
  @assert 0 <= last <= size(c) "Last node out of range"
  @assert 0 <= destination <= size(c) "Destination out of range"
  @assert destination + (last - first) <= size(c) "Target range out of bounds"

  # Return if move would be a no-op
  if last < first || first == destination
    return
  end

  # Copy nodes to new location
  raw_copy!(c, c, first, last, destination)

  # Move connectivity
  move_connectivity!(c, first, last, destination)

  # Invalidate original node locations
  invalidate!(c, first, last)
end
move!(c::AbstractContainer, from::Int, destination::Int) = move!(c, from, from, destination)


function swap!(c::AbstractContainer, a::Int, b::Int)
  @assert 0 <= a <= size(c) "a out of range"
  @assert 0 <= b <= size(c) "b out of range"

  # Return if swap would be a no-op
  if a == b
    return
  end

  # Move a to dummy location
  raw_copy!(c, a, c.dummy)
  move_connectivity(c, a, c.dummy)

  # Move b to a
  raw_copy!(c, b, a)
  move_connectivity(c, b, a)

  # Move from dummy location to b
  raw_copy!(c, c.dummy, b)
  move_connectivity(c, c.dummy, b)

  # Invalidate dummy to be sure
  invalidate(c, c.dummy)
end


function insert!(c::AbstractContainer, position::Int, count::Int)
  @assert 0 <= position <= size(c) + 1 "Insert position out of range"
  @assert count >= 0 "Count must be non-negative"
  @assert count + size(c) <= capacity(c) "New size would exceed capacity"

  # Return if insertation would be a no-op
  if count == 0
    return
  end

  # Increase size
  c.size += count

  # Move original nodes that currently occupy the insertion region
  move(c, position, size(c) - count, position + count)
end
insert!(c) = insert!(c, position, 1)


function erase!(c::AbstractContainer, first::Int, last::Int)
  @assert 0 <= first <= size(c) "First node out of range"
  @assert 0 <= last <= size(c) "Last node out of range"

  # Return if eraseure would be a no-op
  if last < first
    return
  end

  # Delete connectivity and invalidate nodes
  delete_connectivity!(c, first, last)
  invalidate!(c, first, last)
end
erase!(c::AbstractContainer, id::Int) = erase!(c, id, id)


# Remove nodes and shift existing nodes forward
function remove_shift(c::AbstractContainer, first::Int, last::Int)
  @assert 0 <= first <= size(c) "First node out of range"
  @assert 0 <= last <= size(c) "Last node out of range"

  # Return if removal would be a no-op
  if last < first
    return
  end

  # Delete connectivity of nodes to be removed
  delete_connectivity!(c, first, last)

  if last == size
    # If everything up to the last node is removed, no shifting is required
    invalidate!(c, first, last)
  else
    # Otherwise, the corresponding nodes are moved forward
    move!(c, last + 1, size(c), first)
  end

  # Reduce size
  count = last - first + 1
  c.size -= count
end


# Remove nodes and fill gap with nodes from the end of the container (to reduce copy operations)
function remove_fill(c::AbstractContainer, first::Int, last::Int)
  @assert 0 <= first <= size(c) "First node out of range"
  @assert 0 <= last <= size(c) "Last node out of range"

  # Return if removal would be a no-op
  if last < first
    return
  end

  # Delete connectivity of nodes to be removed and then invalidate them
  delete_connectivity!(c, first, last)
  invalidate!(c, first, last)

  # Copy cells from end (unless last is already the last cell)
  count = last - first + 1
  if last < size(c)
    move(c, max(size(c) - count, last + 1), size(c), first)
  end

  # Reduce size
  c.size -= count
end


function reset!(c::AbstractContainer, capacity::Int)
  @assert capacity >=0

  c.capacity = capacity
  c.size = 0
  c.dummy = capacity + 1
  reset_data_structures!(c::AbstractContainer)
end


function clear!(c::AbstractContainer)
  invalidate!(c)
  c.size = 0
end