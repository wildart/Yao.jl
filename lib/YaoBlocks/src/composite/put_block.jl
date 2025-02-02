using StatsBase
export PutBlock, put, Swap, swap, PSwap, pswap

"""
    PutBlock{D,C,GT<:AbstractBlock} <: AbstractContainer{GT,D}

Type for putting a block at given locations.
"""
struct PutBlock{D,C,GT<:AbstractBlock} <: AbstractContainer{GT,D}
    n::Int
    content::GT
    locs::NTuple{C,Int}

    function PutBlock(n::Int,block::GT, locs::NTuple{C,Int}) where {D,C,GT<:AbstractBlock{D}}
        @assert_locs_safe n locs
        @assert nqudits(block) == C "number of locations doesn't match the size of block"
        return new{D,C,GT}(n, block, locs)
    end
end
nqudits(pb::PutBlock) = pb.n

"""
    put(total::Int, pair)

Create a [`PutBlock`](@ref) with total number of active qubits, and a pair of
location and block to put on.

# Example

```jldoctest; setup=:(using YaoBlocks)
julia> put(4, 1=>X)
nqudits: 4
put on (1)
└─ X
```

If you want to put a multi-qubit gate on specific locations, you need to write down all possible locations.

```jldoctest; setup=:(using YaoBlocks)
julia> put(4, (1, 3)=>kron(X, Y))
nqudits: 4
put on (1, 3)
└─ kron
   ├─ 1=>X
   └─ 2=>Y
```

The outter locations creates a scope which make it seems to be a contiguous two qubits for the block inside `PutBlock`.

!!! tips
    It is better to use [`subroutine`](@ref) instead of `put` for large blocks, since put will use the matrix of its contents
    directly instead of making use of what's in it. `put` is more efficient for small blocks.
"""
put(total::Int, pa::Pair{NTuple{M,Int},<:AbstractBlock}) where {M} =
    PutBlock(total, pa.second, pa.first)
put(total::Int, pa::Pair{Int,<:AbstractBlock}) = PutBlock(total, pa.second, (pa.first,))
put(total::Int, pa::Pair{<:Any,<:AbstractBlock}) =
    PutBlock(total, pa.second, Tuple(pa.first))

"""
    put(pair) -> f(n)

Lazy curried version of [`put`](@ref).

# Example

```jldoctest; setup=:(using YaoBlocks)
julia> put(1=>X)
(n -> put(n, 1 => X))
```
"""
put(pa::Pair) = @λ(n -> put(n, pa))

occupied_locs(x::PutBlock) = map(i -> x.locs[i], x.content |> occupied_locs)
chsubblocks(x::PutBlock, b::AbstractBlock) = PutBlock(x.n, b, x.locs)
PropertyTrait(::PutBlock) = PreserveAll()
cache_key(pb::PutBlock) = cache_key(pb.content)

mat(::Type{T}, pb::PutBlock{2,1}) where {T} = u1mat(pb.n, mat(T, pb.content), pb.locs...)
mat(::Type{T}, pb::PutBlock{2,C}) where {T,C} = unmat(pb.n, mat(T, pb.content), pb.locs)

function _apply!(r::AbstractRegister, pb::PutBlock{2})
    instruct!(r, mat_matchreg(r, pb.content), pb.locs)
    return r
end

# NOTE: Roger: these specialization should be removed after the new interpret
# mechanism is implemented
# specialization
for G in [:X, :Y, :Z, :T, :S, :Sdag, :Tdag, :H]
    GT = Expr(:(.), :ConstGate, QuoteNode(Symbol(G, :Gate)))
    @eval function _apply!(r::AbstractRegister, pb::PutBlock{2,C,<:$GT}) where {C}
        instruct!(r, Val($(QuoteNode(G))), pb.locs)
        return r
    end
end

Base.adjoint(x::PutBlock) = PutBlock(nqudits(x), adjoint(content(x)), x.locs)
Base.copy(x::PutBlock) = PutBlock(x.n, x.content, x.locs)
function Base.:(==)(lhs::PutBlock{D,C,GT}, rhs::PutBlock{D,C,GT}) where {D,C,GT}
    return (lhs.n == rhs.n) && (lhs.content == rhs.content) && (lhs.locs == rhs.locs)
end

function YaoBase.iscommute(x::PutBlock{D}, y::PutBlock{D}) where {D}
    _check_block_sizes(x, y)
    if x.locs == y.locs
        return iscommute(x.content, y.content)
    else
        return iscommute_fallback(x, y)
    end
end

const Swap = PutBlock{2,2,G} where {G<:ConstGate.SWAPGate}
const PSwap{T} = PutBlock{2,2,RotationGate{2,T,G}} where {G<:ConstGate.SWAPGate}
Swap(n::Int, locs::Tuple{Int,Int}) = PutBlock(n, ConstGate.SWAPGate(), locs)
PSwap(n::Int, locs::Tuple{Int,Int}, θ::Real) =
    PutBlock(n, rot(ConstGate.SWAPGate(), θ), locs)

"""
    swap(n, loc1, loc2)

Create a `n`-qubit [`Swap`](@ref) gate which swap `loc1` and `loc2`.

# Example

```jldoctest; setup=:(using YaoBlocks)
julia> swap(4, 1, 2)
nqudits: 4
put on (1, 2)
└─ SWAP
```
"""
swap(n::Int, loc1::Int, loc2::Int) = Swap(n, (loc1, loc2))

"""
    swap(loc1, loc2) -> f(n)

Create a lambda that takes the total number of active qubits as input. Lazy curried
version of `swap(n, loc1, loc2)`. See also [`Swap`](@ref).

# Example

```jldoctest; setup=:(using YaoBlocks)
julia> swap(1, 2)
(n -> swap(n, 1, 2))
```
"""
swap(loc1::Int, loc2::Int) = @λ(n -> swap(n, loc1, loc2))

function mat(::Type{T}, g::Swap) where {T}
    mask = bmask(g.locs[1], g.locs[2])
    orders = map(b -> swapbits(b, mask) + 1, basis(g.n))
    return PermMatrix(orders, ones(T, nlevel(g)^g.n))
end

_apply!(r::AbstractRegister, g::Swap) = (instruct!(r, Val(:SWAP), g.locs); r)
occupied_locs(g::Swap) = g.locs

"""
    pswap(n::Int, i::Int, j::Int, α::Real)
    pswap(i::Int, j::Int, α::Real) -> f(n)

parametrized swap gate.
"""
pswap(n::Int, i::Int, j::Int, α::Real) = PSwap(n, (i, j), α)
pswap(i::Int, j::Int, α::Real) = n -> pswap(n, i, j, α)

for (G, GT) in [
    (:Rx, :(PutBlock{2,1,RotationGate{T,XGate}} where {T})),
    (:Ry, :(PutBlock{2,1,RotationGate{T,YGate}} where {T})),
    (:Rz, :(PutBlock{2,1,RotationGate{T,ZGate}} where {T})),
    (:PSWAP, :(PSwap)),
]
    @eval function _apply!(reg::AbstractRegister, g::$GT)
        instruct!(reg, Val($(QuoteNode(G))), g.locs, g.content.theta)
        return reg
    end
end
