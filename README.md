# MutatePlainDataArray.jl

[![Build Status](https://github.com/medyan-dev/MutatePlainDataArray.jl/workflows/CI/badge.svg)](https://github.com/medyan-dev/MutatePlainDataArray.jl/actions)

Enable mutating immutable plain data fields using `aref` wrapper, allowing mutating immutable plain data fields using the following syntax:
```julia
    aref(v)[i].a.b[] = val
```

The nested fields can be accessed using either the field name, or the field index with `getproperty`.
The wrapped vector must implement the strided arrays interface and must have `isbitstype` element type.

Examples:
```julia-repl
julia> using MutatePlainDataArray

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

The mutation provided by this package is
- **Efficient**. Under the hood, the mutation is achieved by pointer load/store, where the address offset is known at type inference time.
- **Safe**. Compile-time type check is enforced. Reference to the original vector is obtained to prevent garbage collection. Bounds check is performed unless `@inbounds` is used. This package is inspired by and acts as a safer counterpart to [UnsafePointers.jl](https://github.com/cjdoris/UnsafePointers.jl).
