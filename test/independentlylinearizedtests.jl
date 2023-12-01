using Test, DiffEqCallbacks
using DiffEqCallbacks: sample, store!, IndependentlyLinearizedSolutionChunks, finish!

@testset "IndependentlyLinearizedSolution" begin
    ils = IndependentlyLinearizedSolution{Float64,Float64}([0.0, 0.5, 0.75, 1.0],
        [
            [0.0, 0.5, 1.0],
            [0.0, 0.75, 1.0],
            [0.0, 1.0],
        ],
        BitMatrix([1 1 0 1
            1 0 1 1
            1 0 0 1]'),
        nothing)

    # Test `iterate()`
    for (t, u) in ils
        @test all(t .== u)
    end
    # Test `sample()`
    ts = range(0.0, 1.0; length = 11)
    us = sample(ils, ts)
    for (t_idx, t) in enumerate(ts)
        @test all(t .== us[t_idx, :])
    end
end

# Quick benchmark of ILS
#=
ts = [0.0, (sort(rand(10000)) .+ 0.5)..., 2.0]
us = [randn(100 + rand(200:800)) for _ in 1:50]
time_mask = zeros(Bool, length(ts), length(us))
time_mask[1, :] .= 1
time_mask[end, :] .= 1
for u_idx in 1:length(us)
    time_mask[sortperm(randn(length(ts)-2))[1:(length(us[u_idx])-2)] .+ 1,u_idx] .= 1
end
ils = IndependentlyLinearizedSolution(ts, us, time_mask)

@info("collect(ils)")
display(@benchmark collect(ils))
@info("sample(ils, 1 sample per timepoint)")
display(@benchmark sample(ils, ils.ts))
@info("sample(ils, ~100 samples per timepoint)")
many_ts = sort(2.0*rand(10000*100))
display(@benchmark sample(ils, many_ts))
=#

@testset "IndependentlyLinearizedSolutionChunks" begin
    num_us = 10
    chunk_size = 10
    num_timepoints = 105
    ilsc = IndependentlyLinearizedSolutionChunks{Float64, Float64}(num_us, chunk_size)
    for t in 1:num_timepoints
        # Storing at `1` and `num_timepoints` is to satisfy that we must sample all points at the start and end
        store!(ilsc,
            Float64(t),
            repeat([Float64(t)], 10),
            BitVector([(t % u == 0) || (t == 1 || t == num_timepoints) for u in 1:num_us]))
    end
    # Test that `u_chunks` looks right
    @test length(ilsc.u_chunks) == num_us
    @test length.(ilsc.u_chunks) == [11, 6, 4, 3, 3, 2, 2, 2, 2, 2]
    @test ilsc.u_chunks[1][1] == Float64.(1:chunk_size)
    @test ilsc.u_chunks[2][end][1:2] == [100, 102]
    @test ilsc.u_chunks[10][1][1:10] == [1.0, Float64.(10 .* (1:9))...]

    # Test that `t_chunks` looks right
    @test length(ilsc.t_chunks) == 11
    @test all([t_chunks[1] % chunk_size == 1 for t_chunks in ilsc.t_chunks])

    # Test that `time_masks` looks right
    @test sum(ilsc.time_masks[1], dims = 1)[:] == [10, 6, 4, 3, 3, 2, 2, 2, 2, 2]
    @test sum(sum.(ilsc.time_masks[1:10], dims = 1))[:] ==
          [div(100, idx) + ((idx > 1) ? 1 : 0) for idx in 1:10]

    ils = IndependentlyLinearizedSolution(ilsc)

    # Muck with the `ilsc` here to explore some failure options
    # Error: timepoints longer than time_matrix
    ilsc.t_offset += 1
    @test_throws ArgumentError finish!(ils)
    ilsc.t_offset -= 1

    # Error: time matrix row two has N elements, but `us` has N+1
    ilsc.u_offsets[2] += 1
    @test_throws ArgumentError finish!(ils)
    ilsc.u_offsets[2] -= 1

    # Error: one of our time masks doesn't start with `1`
    ilsc.time_masks[1][1, 1] = 0
    @test_throws ArgumentError finish!(ils)
    ilsc.time_masks[1][1, 1] = 1

    finish!(ils)
    @test sample(ils, ils.ts) == repeat(1:num_timepoints, 1, num_us)
end
