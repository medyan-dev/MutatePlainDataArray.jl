module MutatePlainDataArray

export aref

using Compat

#---------------------------------------
# Common functions.
#---------------------------------------
unsafe_pointer(v) = pointer(v)
unsafe_pointer(v, i) = pointer(v, i)
unsafe_pointer(v, i1, i2, is...) = pointer(v, CartesianIndex((i1, i2, is...)))

function field_offset_type_impl(::Type{T}, ::Val{S}) where {T,S}
    if !isstructtype(T)
        error("$T is not struct type.")
    end
    if S isa Symbol
        fs = fieldnames(T)
        findex = findfirst(==(S), fs)
        if isnothing(findex)
            # Cannot find the field name.
            s = string(S)
            if startswith(s, '_')
                # Try to parse it as a number.
                findex = tryparse(Int, s[2:end])
            end
        end
        if isnothing(findex)
            error("Cannot find field $S in type $T.")
        end
    elseif S isa Integer
        findex = S
    else
        error("$S is not a symbol or an integer.")
    end

    fieldoffset(T, findex), fieldtype(T, findex)
end

"""
    field_offset_type(type, Val(S))

Given struct `type` and the field name or index `S`, return the offset and type of the field.

If `S` is an integer, it is represents the index of the field.
If `S` is a symbol, the function will first try to find the field with that name. If the name is not found, it will try to parse it with form `_index` where index is the field index.
"""
@generated function field_offset_type(::Type{T}, ::Val{S}) where {T,S}
    offset, type = field_offset_type_impl(T, Val(S))
    :(($offset, $type))
end


#---------------------------------------
# Implementation using reference chaining.
#---------------------------------------

struct ARef{T}
    r::T
    function ARef(v::AbstractArray{ET,N}) where {ET,N}
        if ismutabletype(ET)
            error("Element type $ET is not immutable.")
        end
        new{typeof(v)}(v)
    end
end

"""
    aref(v::AbstractArray)

Wraps an array, allowing mutating immutable plain data fields using the following syntax:
```julia
    aref(v)[i].a.b._i._j = val
```

The nested fields can be accessed using either the field name, or the field index prefixed with `_`.
Except for the wrapped vector, every field in the chain must be immutable. The final type to be mutated must be bits type.

Examples:
```julia-repl
julia> a = [1, 2, 3];

julia> aref(a)[1] = 4
4

julia> a
3-element Vector{Int64}:
 4
 2
 3

julia> b = [(tup=(1, 2.5), s="a"), (tup=(2, 4.5), s="b")];
 
julia> aref(b)[1].tup._2 = Inf
Inf

julia> b
2-element Vector{NamedTuple{(:tup, :s), Tuple{Tuple{Int64, Float64}, String}}}:
 (tup = (1, Inf), s = "a")
 (tup = (2, 4.5), s = "b")

julia> aref(b)[2]._1._1 *= 100
200

julia> b
2-element Vector{NamedTuple{(:tup, :s), Tuple{Tuple{Int64, Float64}, String}}}:
 (tup = (1, Inf), s = "a")
 (tup = (200, 4.5), s = "b")

julia> aref(b)[1].s = "invalid"
ERROR: The field type String (field s in NamedTuple{(:tup, :s), Tuple{Tuple{Int64, Float64}, String}}) is not immutable.
Stacktrace:
 ...
```
"""
aref(v::AbstractArray) = ARef(v)

struct ElementRef{T, ET}
    # Keep the reference to original vector to keep it alive.
    r::T
    # The actual pointer to the element.
    p::Ptr{ET}
end


Base.@propagate_inbounds function Base.getindex(v::ARef{T}, indices...) where T
    @boundscheck checkbounds(v.r, indices...)
    ElementRef(v.r, unsafe_pointer(v.r, indices...))
end
Base.@propagate_inbounds function Base.setindex!(v::ARef{T}, x, indices...) where T
    v.r[indices...] = x
end

function Base.getindex(r::ElementRef{T,ET}) where {T, ET}
    if isbitstype(ET)
        rr = getfield(r, :r)
        GC.@preserve rr unsafe_load(getfield(r, :p))
    else
        error("Type $ET is not bits type.")
    end
end
function Base.setindex!(r::ElementRef{T,ET}, val) where {T, ET}
    if isbitstype(ET)
        rr = getfield(r, :r)
        GC.@preserve rr unsafe_store!(getfield(r, :p), convert(ET, val))
    else
        error("Type $ET is not bits type.")
    end
end

@generated function chain_offsettype(::ElementRef{T,ET}, ::Val{S}) where {T, ET, S}
    offset, type = field_offset_type(ET, Val(S))
    if ismutabletype(type)
        error("The field type $type (field $S in $ET) is not immutable.")
    end
    :(($offset, $type))
end

function Base.getproperty(r::ElementRef{T,ET}, name::Symbol) where {T, ET}
    offset, type = chain_offsettype(r, Val(name))
    ElementRef(getfield(r, :r), Base.unsafe_convert(Ptr{type}, getfield(r, :p)) + offset)
end
function Base.setproperty!(r::ElementRef{T,ET}, name::Symbol, x) where {T, ET}
    setindex!(getproperty(r, name), x)
end

macro forward_binary_op(ops...)
    defop(op::Symbol) = quote
        Base.$op(r::ElementRef{T,ET}, x) where {T,ET} = $op(getindex(r), x)
    end
    Expr(:block, defop.(ops)...)
end
@forward_binary_op(+, -, *, /, \, ÷, %, ^, &, |, ⊻, >>>, >>, <<)

#---------------------------------------
# Type extractions.
#---------------------------------------
atype(::ARef{T}) where T = T
atype(::Type{ARef{T}}) where T = T
atype(::ElementRef{T,ET}) where {T,ET} = T
atype(::Type{ElementRef{T,ET}}) where {T,ET} = T
eltype(::ElementRef{T,ET}) where {T,ET} = ET
eltype(::Type{ElementRef{T,ET}}) where {T,ET} = ET


end
