using MutatePlainDataArray: MutatePlainDataArray, aref
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
struct TIB
    x::Int
    a::TAB
end

struct TC
    _2  ::Val{1}
    __1 ::Val{2}
    a   ::Val{3}
end
TC() = TC(Val(1), Val(2), Val(3))

struct TAN
    x::Int
    s::String
    TAN(x) = new(x)
    TAN(x, y) = new(x, y)
end

@testset "MutatePlainDataArray.jl" begin
    @test isbitstype(TAB)
    @test !isbitstype(TAI)
    @test !isbitstype(TAM)
    @test isbitstype(TBB)
    @test !isbitstype(TBI)
    @test !isbitstype(TBM)
    @test isbitstype(TC)

    @testset "aref validation" begin
        v1 = [1, 2]
        v2 = [TAB(1, 2), TAB(3, 4)]
        v3 = [TAI(1, "a"), TAI(2, "b")]
        v4 = [TAM(1, 2), TAM(3, 4)]
        v5 = [TAB(1, 2) TAB(3, 4); TAB(5, 6) TAB(7, 8)]
        v6 = [TAN(1, "a"), TAN(2, "b")]
        t1 = (1, 2)
        t2 = (TAB(1, 2), TAB(3, 4))
        t3 = (TAI(1, "a"), TAI(2, "b"))
        t4 = (TAM(1, 2), TAM(3, 4))

        @test aref(v1) isa Any
        @test aref(v2) isa Any
        @test_throws ErrorException aref(v3)
        @test_throws ErrorException aref(v4)
        @test aref(v5) isa Any
        @test_throws ErrorException aref(v6)
        @test_throws MethodError aref(t1)
        @test_throws MethodError aref(t2)
        @test_throws MethodError aref(t3)
        @test_throws MethodError aref(t4)

        @test aref([1,2]) isa Any
        @test aref(([1,2],)[1]) isa Any
        @test_throws MethodError aref((1,2))
    end

    @testset "aref indexing" begin
        v1 = [TAB(1, 2), TAB(3, 4)]
        r1 = aref(v1)

        @test r1[1] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError r1[0]
        @test_throws Exception r1[1] = TAI(3, "c")

        v2 = rand(5, 5)
        # Currently, multi-indexing array directly is not supported.
        view2 = view(v2, 1:2:5, :)
        r2 = aref(v2)
        rview2 = aref(view2)

        @test r2[25] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError r2[26]
        @test rview2[15] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError rview2[16]
        @test rview2[3,4] isa MutatePlainDataArray.ElementRef
        @test_throws BoundsError rview2[4,4]
        GC.@preserve v2 begin
            @test rview2[3,5][] === r2[25][]
            @test r2[3][] === rview2[2,1][]
        end
    end

    @testset "Field type chaining" begin
        v1 = [TIB(1 , TAB(3, 4)), TIB(5, TAB(7, 8))]
        r1 = aref(v1)
        e1 = r1[1]

        if VERSION ≥ v"1.12"
            @test_throws FieldError e1.foo
        else
            @test_throws ErrorException e1.foo
        end

        let e12 = e1.x
            @test_throws ErrorException e12.x
            @test_throws ErrorException e12.:1
        end
        let e12 = e1.:1
            @test e12 == e1.x
        end
        let e12 = e1.a
            @test MutatePlainDataArray.eltype(e12) == TAB
            let e13 = e12.x
                @test MutatePlainDataArray.eltype(e13) == Int
            end
        end
        @test_throws BoundsError e1.:0
        @test_throws BoundsError e1.:3

        v2 = [TC(), TC()]
        r2 = aref(v2)
        e2 = r2[2]
        @test MutatePlainDataArray.eltype(e2) == TC

        @test MutatePlainDataArray.eltype(e2.:1) == Val{1}
        # "_2" is the name of the first field.
        @test MutatePlainDataArray.eltype(e2._2) == Val{1}
        @test MutatePlainDataArray.eltype(e2.:3) == Val{3}
        @test MutatePlainDataArray.eltype(e2.__1) == Val{2}
    end

    @testset "Field mutation" begin
        v1 = [TIB(1 , TAB(3, 4)), TIB(5, TAB(7, 8))]
        r1 = aref(v1)

        r1[1][] = TIB(5 , TAB(6, 7))
        @test v1 == [TIB(5 , TAB(6, 7)), TIB(5, TAB(7, 8))]
        r1[1].a[] = TAB(6, 8)
        @test v1 == [TIB(5 , TAB(6, 8)), TIB(5, TAB(7, 8))]
        r1[1].a.y[] = 10.5
        @test v1 == [TIB(5 , TAB(6, 10.5)), TIB(5, TAB(7, 8))]
        @test_throws ErrorException r1[1].x = -1
        @test_throws ErrorException r1[1].a.x = -1

        r1[1].x[] = 50
        @test v1 == [TIB(50 , TAB(6, 10.5)), TIB(5, TAB(7, 8))]
        r1[1].x[] *= 2
        @test v1 == [TIB(100 , TAB(6, 10.5)), TIB(5, TAB(7, 8))]
        r1[2].x[] <<= 1
        @test v1 == [TIB(100 , TAB(6, 10.5)), TIB(10, TAB(7, 8))]

        r1[1].a.x[] = 200
        @test v1 == [TIB(100 , TAB(200, 10.5)), TIB(10, TAB(7, 8))]
        r1[1].a.x[] /= 2
        @test v1 == [TIB(100 , TAB(100, 10.5)), TIB(10, TAB(7, 8))]
        r1[2].a.x[] %= 3
        @test v1 == [TIB(100 , TAB(100, 10.5)), TIB(10, TAB(1, 8))]
        @test_throws MethodError r1[1].a.x[] = "some string"
    end
end
