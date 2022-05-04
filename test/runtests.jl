using MutatePlainDataArray
using Test

struct TAB
    x::Int
    y::Float64
end
struct TAI
    x::Int
    s::String
end
mutable struct TAM
    x::Int
    y::Float64
end

struct TBB
    a1::TAB
    a2::TAB
end
struct TBI
    x::Int
    a::TAI
end
mutable struct TBM
    a1::TAB
    a2::TAB
end

struct TC
    _2  ::Val{1}
    __1 ::Val{2}
    a   ::Val{3}
end
TC() = TC(Val(1), Val(2), Val(3))

@testset "MutatePlainDataArray.jl" begin
    @test isbitstype(TAB)
    @test !isbitstype(TAI) && !ismutabletype(TAI)
    @test ismutabletype(TAM)
    @test isbitstype(TBB)
    @test !isbitstype(TBI) && !ismutabletype(TBI)
    @test ismutabletype(TBM)
    @test isbitstype(TC)

    @testset "ARef validation" begin
        v1 = [1, 2]
        v2 = [TAB(1, 2), TAB(3, 4)]
        v3 = [TAI(1, "a"), TAI(2, "b")]
        v4 = [TAM(1, 2), TAM(3, 4)]
        v5 = [TAB(1, 2) TAB(3, 4); TAB(5, 6) TAB(7, 8)]
        t1 = (1, 2)
        t2 = (TAB(1, 2), TAB(3, 4))
        t3 = (TAI(1, "a"), TAI(2, "b"))
        t4 = (TAM(1, 2), TAM(3, 4))

        @test ARef(v1) isa Any
        @test ARef(v2) isa Any
        @test ARef(v3) isa Any
        @test_throws ErrorException ARef(v4)
        @test ARef(v5) isa Any
        @test_throws MethodError ARef(t1)
        @test_throws MethodError ARef(t2)
        @test_throws MethodError ARef(t3)
        @test_throws MethodError ARef(t4)

        @test ARef([1,2]) isa Any
        @test ARef(([1,2],)[1]) isa Any
        @test_throws MethodError ARef((1,2))
    end

    @testset "ARef indexing" begin
        v1 = [TAI(1, "a"), TAI(2, "b")]
        r1 = ARef(v1)

        @test r1[1] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError r1[0]
        @test_throws Exception r1[1] = TAI(3, "c")

        v2 = zeros(5, 5)
        # Currently, multi-indexing array directly is not supported.
        view2 = view(v2, 1:2:5, :)
        r2 = ARef(v2)
        rview2 = ARef(view2)

        @test r2[25] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError r2[26]
        @test rview2[15] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError rview2[16]
        @test rview2[3,4] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError rview2[4,4]
        GC.@preserve v2 begin
            @test getfield(rview2[3,5], :p) == getfield(r2[25], :p)
            @test getfield(r2[1], :p) + sizeof(Float64) * 2 == getfield(rview2[2,1], :p)
        end
    end

    @testset "Field type chaining" begin
        v1 = [TBI(1, TAI(2, "a")), TBI(3, TAI(4, "b"))]
        r1 = ARef(v1)

        @test MutatePlainDataArray.atype(r1) == Vector{TBI}
        e1 = r1[1]
        @test MutatePlainDataArray.atype(e1) == Vector{TBI}
        @test MutatePlainDataArray.eltype(e1) == TBI

        let e12 = e1.x
            @test MutatePlainDataArray.atype(e12) == Vector{TBI}
            @test MutatePlainDataArray.eltype(e12) == Int
            @test_throws ErrorException e12.x
            @test_throws ErrorException e12._1
        end
        let e12 = e1._1
            @test e12 == e1.x
        end
        let e12 = e1.a
            @test MutatePlainDataArray.atype(e12) == Vector{TBI}
            @test MutatePlainDataArray.eltype(e12) == TAI
            let e13 = e12.x
                @test MutatePlainDataArray.atype(e13) == Vector{TBI}
                @test MutatePlainDataArray.eltype(e13) == Int
            end
            # Cannot chain a mutable type.
            @test_throws ErrorException e12.a
            @test_throws ErrorException e12._2
        end
        @test_throws BoundsError e1._0
        @test_throws BoundsError e1._3

        v2 = [TC(), TC()]
        r2 = ARef(v2)
        e2 = r2[2]
        @test MutatePlainDataArray.atype(e2) == Vector{TC}
        @test MutatePlainDataArray.eltype(e2) == TC

        @test MutatePlainDataArray.eltype(e2._1) == Val{1}
        # "_2" is the name of the first field.
        @test MutatePlainDataArray.eltype(e2._2) == Val{1}
        @test MutatePlainDataArray.eltype(e2._3) == Val{3}
        @test MutatePlainDataArray.eltype(e2.__1) == Val{2}
    end

    @testset "Field mutation" begin
        v1 = [TBI(1, TAI(2, "a")), TBI(3, TAI(4, "b"))]
        r1 = ARef(v1)

        @test_throws ErrorException r1[1][] = TBI(5, TAI(6, "c"))
        @test_throws ErrorException r1[1].a[] = TAI(6, "c")
        @test_throws ErrorException r1[1].a.s[] = "c"
        @test_throws ErrorException r1[1].x = -1
        @test_throws ErrorException r1[1].a.x = -1

        r1[1].x[] = 50
        @test v1 == [TBI(50, TAI(2, "a")), TBI(3, TAI(4, "b"))]
        r1[1].x[] *= 2
        @test v1 == [TBI(100, TAI(2, "a")), TBI(3, TAI(4, "b"))]
        r1[2].x[] <<= 1
        @test v1 == [TBI(100, TAI(2, "a")), TBI(6, TAI(4, "b"))]

        r1[1].a.x[] = 200
        @test v1 == [TBI(100, TAI(200, "a")), TBI(6, TAI(4, "b"))]
        r1[1].a.x[] /= 2
        @test v1 == [TBI(100, TAI(100, "a")), TBI(6, TAI(4, "b"))]
        r1[2].a.x[] %= 3
        @test v1 == [TBI(100, TAI(100, "a")), TBI(6, TAI(1, "b"))]
        @test_throws MethodError r1[1].a.x[] = "some string"
    end
end
