module TestExamples2DLatticeBoltzmann

using Test
using Trixi

include("test_trixi.jl")

# pathof(Trixi) returns /path/to/Trixi/src/Trixi.jl, dirname gives the parent directory
EXAMPLES_DIR = joinpath(pathof(Trixi) |> dirname |> dirname, "examples", "2d")

@testset "Lattice-Boltzmann" begin
  @testset "elixir_lbm_constant.jl" begin
    @test_trixi_include(joinpath(EXAMPLES_DIR, "elixir_lbm_constant.jl"),
      l2   = [5.019809140581347e-15, 4.896755819526798e-15, 6.320897309084063e-16,
              6.153570835219355e-16, 2.068942634230956e-15, 5.730768604283376e-16,
              2.1243821779085842e-16, 6.5292701013301e-16, 9.793181942190569e-15],
      linf = [5.995204332975845e-15, 5.440092820663267e-15, 9.43689570931383e-16,
              1.5543122344752192e-15, 2.345346139520643e-15, 7.494005416219807e-16,
              3.677613769070831e-16, 8.465450562766819e-16, 1.176836406102666e-14])
  end

  @testset "elixir_lbm_couette.jl" begin
    @test_trixi_include(joinpath(EXAMPLES_DIR, "elixir_lbm_couette.jl"),
      l2   = [0.0007905194378504636, 1.70140522879544e-5, 0.0007459405350479714,
              7.711268509067856e-6, 0.00029487708499692023, 0.00027795435775872744,
              0.00013031623771130323, 0.0001372248938998687, 4.5011036066285266e-5],
      linf = [0.005596903092642783, 0.00012111558687910584, 0.0052705461719205204,
              4.6023482471249655e-5, 0.0020683532934497526, 0.0019472377065719963,
              0.0007915213810092622, 0.0008280900785695398, 0.0003263569207270778],
      tspan = (0, 1))
  end

  @testset "elixir_lbm_lid_driven_cavity.jl" begin
    @test_trixi_include(joinpath(EXAMPLES_DIR, "elixir_lbm_lid_driven_cavity.jl"),
      l2   = [0.0013650620243295737, 0.00022198751341744345, 0.0012598874493851212,
              0.0003717179135582976, 0.00043781314171344746, 0.0003981707759011124,
              0.00025217328296380794, 0.0002648703108851751, 0.0004424433618466238],
      linf = [0.024202160934374467, 0.011909887052248352, 0.0217875153015466, 0.036180368381527356,
              0.008017773117001796, 0.006848205899982397, 0.010286155761876685,
              0.009919734283157303, 0.055681556789206055],
      tspan = (0, 1))
  end
end

end # module
