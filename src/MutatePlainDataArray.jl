module MutatePlainDataArray

export aref


#---------------------------------------
# Common functions.
#---------------------------------------

# A is a strided array
# This doesn't do bounds checking
function indices_to_byte_offset(A::AbstractArray{T,N}, ind::CartesianIndex{N}) where {T, N}
    offset::Int = 0
    for d in 1:N
        stride_in_bytes = stride(A, d) * Base.elsize(typeof(A))
        first_idx = first(axes(A, d))
        offset += (ind[d] - first_idx) * stride_in_bytes
    end
    offset
end

function field_offset_type_impl(::Type{T}, ::Val{S}) where {T,S}
    if !isstructtype(T)
        error("$T is not struct type.")
    end
    if S isa Symbol
        fs = fieldnames(T)
        findex = findfirst(==(S), fs)
        if isnothing(findex)
            if VERSION ≥ v"1.12"
                throw(FieldError(T, S))
            else
                error("Cannot find field $S in type $T.")
            end
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
If `S` is a symbol, the function will try to find the field with that name.
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
        if !isbitstype(ET)
            error("Element type $ET is not isbitstype.")
        end
        new{typeof(v)}(v)
    end
end

"""
    aref(v::AbstractArray)

Wraps an array, allowing mutating immutable plain data fields using the following syntax:
```julia
    aref(v)[i].a.b[] = val
```

The nested fields can be accessed using either the field name, or the field index with `getproperty`.
The wrapped vector must implement the strided arrays interface and must have `isbitstype` element type.

Examples:
```julia-repl
julia> a = [1, 2, 3];

julia> aref(a)[1][] = 4
4

julia> a
3-element Vector{Int64}:
 4
 2
 3

julia> b = [(;tup=(1, 2.5), s=4), (;tup=(2, 4.5), s=5)];
 
julia> aref(b)[1].tup.:2[] = Inf
Inf

julia> b
2-element Vector{@NamedTuple{tup::Tuple{Int64, Float64}, s::Int64}}:
 (tup = (1, Inf), s = 4)
 (tup = (2, 4.5), s = 5)

julia> (aref(b)[2].:1).:1[] *= 100
200

julia> b
2-element Vector{@NamedTuple{tup::Tuple{Int64, Float64}, s::Int64}}:
 (tup = (1, Inf), s = 4)
 (tup = (200, 4.5), s = 5)
```
"""
aref(v::AbstractArray) = ARef(v)

struct ElementRef{T, RET, ET}
    # Keep the cconvert of the original vector to keep it alive.
    rcconv::T
    # The offset of pointer to the element.
    offset::Int
end

Base.@propagate_inbounds function Base.getindex(v::ARef{T}, indices...) where T
    ind = CartesianIndices(v.r)[indices...]::CartesianIndex
    rcconv = Base.cconvert(Ptr{Base.eltype(v.r)}, v.r)
    ElementRef{typeof(rcconv), Base.eltype(v.r), Base.eltype(v.r)}(rcconv, indices_to_byte_offset(v.r, ind))
end

function Base.getindex(r::ElementRef{T,RET,ET}) where {T, RET, ET}
    rcconv = getfield(r, :rcconv)
    GC.@preserve rcconv begin
        p = Ptr{ET}(Base.unsafe_convert(Ptr{RET}, rcconv))
        p += getfield(r, :offset)
        unsafe_load(p)
    end
end
function Base.setindex!(r::ElementRef{T,RET,ET}, val) where {T, RET, ET}
    rcconv = getfield(r, :rcconv)
    GC.@preserve rcconv begin
        p = Ptr{ET}(Base.unsafe_convert(Ptr{RET}, rcconv))
        p += getfield(r, :offset)
        unsafe_store!(p, convert(ET, val))
    end
end

function Base.getproperty(r::ElementRef{T,RET,ET}, S::Symbol) where {T, RET, ET}
    offset, type = field_offset_type(ET, Val(S))
    ElementRef{T, RET, type}(getfield(r, :rcconv), getfield(r, :offset) + offset)
end
function Base.getproperty(r::ElementRef{T,RET,ET}, S::Int) where {T, RET, ET}
    offset, type = field_offset_type(ET, Val(S))
    ElementRef{T, RET, type}(getfield(r, :rcconv), getfield(r, :offset) + offset)
end
"This function should not be called."
function Base.setproperty!(::ElementRef{T,ET}, ::Symbol, x) where {T, ET}
    error("setproperty! is not supported. Maybe you want to use r[] = x instead?")
end


#---------------------------------------
# Type extractions.
#---------------------------------------
atype(::ARef{T}) where T = T
atype(::Type{ARef{T}}) where T = T
atype(::ElementRef{T,RET,ET}) where {T,RET,ET} = T
atype(::Type{ElementRef{T,RET,ET}}) where {T,RET,ET} = T
eltype(::ElementRef{T,RET,ET}) where {T,RET,ET} = ET
eltype(::Type{ElementRef{T,RET,ET}}) where {T,RET,ET} = ET


end
