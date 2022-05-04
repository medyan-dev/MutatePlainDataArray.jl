using MutatePlainDataArray
using BenchmarkTools
using Setfield

struct BAB
    a::Int
    b::Int
    c::Int
    d::Int
end
BAB() = BAB(0, 0, 0, 0)

struct BAI1
    a::Int
    b::Int
    c::Int
    d::Int
    bab::BAB
    m::Matrix{Float64}
end
BAI1() = BAI1(0, 0, 0, 0, BAB(), zeros(100, 100))


function inbounds_setinner!_mutate(v, i)
    @inbounds ARef(v)[i].bab.a[] += 1
end
function inbounds_setinner!_setfield(v, i)
    @inbounds @set! v[i].bab.a += 1
end

function runbench()
    v = fill(BAI1(), 100)

    bench_mutate = @benchmark inbounds_setinner!_mutate($v, 20)
    bench_setfield = @benchmark inbounds_setinner!_setfield($v, 20)

    @show bench_mutate
    display(bench_mutate)
    @show bench_setfield
    display(bench_setfield)
end

runbench()
