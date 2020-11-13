
# Abstract base type for time integration schemes of storage class `2N`
abstract type SimpleAlgorithm2N end


"""
    CarpenterKennedy2N54()

The following structures and methods provide a minimal implementation of
the low-storage explicit Runge-Kutta method of

    Carpenter, Kennedy (1994) Fourth order 2N storage RK schemes, Solution 3

using the same interface as OrdinaryDiffEq.jl.
"""
struct CarpenterKennedy2N54 <: SimpleAlgorithm2N
  a::SVector{5, Float64}
  b::SVector{5, Float64}
  c::SVector{5, Float64}

  function CarpenterKennedy2N54()
    a = @SVector [0.0, 567301805773.0 / 1357537059087.0,2404267990393.0 / 2016746695238.0,
       3550918686646.0 / 2091501179385.0, 1275806237668.0 / 842570457699.0]
    b = @SVector [1432997174477.0 / 9575080441755.0, 5161836677717.0 / 13612068292357.0,
        1720146321549.0 / 2090206949498.0, 3134564353537.0 / 4481467310338.0,
        2277821191437.0 / 14882151754819.0]
    c = @SVector [0.0, 1432997174477.0 / 9575080441755.0, 2526269341429.0 / 6820363962896.0,
        2006345519317.0 / 3224310063776.0, 2802321613138.0 / 2924317926251.0]

    new(a, b, c)
  end
end


"""
      CarpenterKennedy2N43()

Carpenter, Kennedy (1994) Third order 2N storage RK schemes with error control
"""
struct CarpenterKennedy2N43 <: SimpleAlgorithm2N
  a::SVector{4, Float64}
  b::SVector{4, Float64}
  c::SVector{4, Float64}

  function CarpenterKennedy2N43()
    a = @SVector [0, 756391 / 934407, 36441873 / 15625000, 1953125 / 1085297]
    b = @SVector [8 / 141, 6627 / 2000, 609375 / 1085297, 198961 / 526383]
    c = @SVector [0, 8 / 141, 86 / 125, 1]

    new(a, b, c)
  end
end


# This struct is needed to fake https://github.com/SciML/OrdinaryDiffEq.jl/blob/0c2048a502101647ac35faabd80da8a5645beac7/src/integrators/type.jl#L1
mutable struct SimpleIntegrator2NOptions{Callback}
  callback::Callback # callbacks; used in Trixi
  adaptive::Bool # whether the algorithm is adaptive; ignored
  dtmax::Float64 # ignored
  maxiters::Int # maximal numer of time steps
  tstops::Vector{Float64} # tstops from https://diffeq.sciml.ai/v6.8/basics/common_solver_opts/#Output-Control-1; ignored
end

function SimpleIntegrator2NOptions(callback, tspan; maxiters=typemax(Int), kwargs...)
  SimpleIntegrator2NOptions{typeof(callback)}(
    callback, false, Inf, maxiters, [last(tspan)])
end

# This struct is needed to fake https://github.com/SciML/OrdinaryDiffEq.jl/blob/0c2048a502101647ac35faabd80da8a5645beac7/src/integrators/type.jl#L77
# This implements the interface components described at
# https://diffeq.sciml.ai/v6.8/basics/integrator/#Handing-Integrators-1
# which are used in Trixi.
mutable struct SimpleIntegrator2N{RealT<:Real, uType, Params, Sol, Alg, SimpleIntegrator2NOptions}
  u::uType #
  du::uType
  u_tmp::uType
  t::RealT
  dt::RealT # current time step
  dtcache::RealT # ignored
  iter::Int # current number of time step (iteration)
  p::Params # will be the semidiscretization from Trixi
  sol::Sol # faked
  alg::Alg
  opts::SimpleIntegrator2NOptions
  finalstep::Bool # added for convenience
end

# Fakes `solve`: https://diffeq.sciml.ai/v6.8/basics/overview/#Solving-the-Problems-1
function solve(ode::ODEProblem, alg::T;
               dt, callback=nothing, kwargs...) where {T<:SimpleAlgorithm2N}
  u = copy(ode.u0)
  du = similar(u)
  u_tmp = similar(u)
  t = first(ode.tspan)
  iter = 0
  integrator = SimpleIntegrator2N(u, du, u_tmp, t, dt, zero(dt), iter, ode.p,
                  (prob=ode,), alg,
                  SimpleIntegrator2NOptions(callback, ode.tspan; kwargs...), false)

  # initialize callbacks
  if callback isa CallbackSet
    for cb in callback.continuous_callbacks
      error("unsupported")
    end
    for cb in callback.discrete_callbacks
      cb.initialize(cb, integrator.u, integrator.t, integrator)
    end
  elseif !isnothing(callback)
    error("unsupported")
  end

  solve!(integrator)
end

function solve!(integrator::SimpleIntegrator2N)
  @unpack prob = integrator.sol
  @unpack alg = integrator
  t_end = last(prob.tspan)
  callbacks = integrator.opts.callback

  integrator.finalstep = false
  @timeit_debug timer() "main loop" while !integrator.finalstep
    if isnan(integrator.dt)
      error("time step size `dt` is NaN")
    end

    # if the next iteration would push the simulation beyond the end time, set dt accordingly
    if integrator.t + integrator.dt > t_end || isapprox(integrator.t + integrator.dt, t_end)
      integrator.dt = t_end - integrator.t
      terminate!(integrator)
    end

    # one time step
    integrator.u_tmp .= 0
    for stage in eachindex(alg.c)
      t_stage = integrator.t + integrator.dt * alg.c[stage]
      prob.f(integrator.du, integrator.u, prob.p, t_stage)

      a_stage    = alg.a[stage]
      b_stage_dt = alg.b[stage] * integrator.dt
      @timeit_debug timer() "Runge-Kutta step" begin
        Threads.@threads for i in eachindex(integrator.u)
          integrator.u_tmp[i] = integrator.du[i] - integrator.u_tmp[i] * a_stage
          integrator.u[i] += integrator.u_tmp[i] * b_stage_dt
        end
      end
    end
    integrator.iter += 1
    integrator.t += integrator.dt

    # handle callbacks
    if callbacks isa CallbackSet
      for cb in callbacks.discrete_callbacks
        if cb.condition(integrator.u, integrator.t, integrator)
          cb.affect!(integrator)
        end
      end
    end
  end

  return (t=prob.tspan,
          u=(copy(prob.u0), copy(integrator.u)),
          prob=integrator.sol.prob)
end

# get a cache where the RHS can be stored
get_du(integrator::SimpleIntegrator2N) = integrator.du

# some algorithms from DiffEq like FSAL-ones need to be informed when a callback has modified u
u_modified!(integrator::SimpleIntegrator2N, ::Bool) = false

# used by adaptive timestepping algorithms in DiffEq
function set_proposed_dt!(integrator::SimpleIntegrator2N, dt)
  integrator.dt = dt
end

# stop the time integration
function terminate!(integrator::SimpleIntegrator2N)
  integrator.finalstep = true
  empty!(integrator.opts.tstops)
end

# used for AMR
function Base.resize!(integrator::SimpleIntegrator2N, new_size)
  resize!(integrator.u, new_size)
  resize!(integrator.du, new_size)
  resize!(integrator.u_tmp, new_size)
end


# Abstract base type for time integration schemes of storage class `3S*`
abstract type SimpleAlgorithm3Sstar end


"""
    HypDiffN3Erk3Sstar52()

Five stage, second-order acurate explicit Runge-Kutta scheme with stability region optimized for
the hyperbolic diffusion equation with LLF flux and polynomials of degree polydeg=3.
"""
struct HypDiffN3Erk3Sstar52 <: SimpleAlgorithm3Sstar
  gamma1::SVector{5, Float64}
  gamma2::SVector{5, Float64}
  gamma3::SVector{5, Float64}
  beta::SVector{5, Float64}
  delta::SVector{5, Float64}
  c::SVector{5, Float64}

  function HypDiffN3Erk3Sstar52()
    gamma1 = @SVector [0.0000000000000000E+00, 5.2656474556752575E-01, 1.0385212774098265E+00, 3.6859755007388034E-01, -6.3350615190506088E-01]
    gamma2 = @SVector [1.0000000000000000E+00, 4.1892580153419307E-01, -2.7595818152587825E-02, 9.1271323651988631E-02, 6.8495995159465062E-01]
    gamma3 = @SVector [0.0000000000000000E+00, 0.0000000000000000E+00, 0.0000000000000000E+00, 4.1301005663300466E-01, -5.4537881202277507E-03]
    beta   = @SVector [4.5158640252832094E-01, 7.5974836561844006E-01, 3.7561630338850771E-01, 2.9356700007428856E-02, 2.5205285143494666E-01]
    delta  = @SVector [1.0000000000000000E+00, 1.3011720142005145E-01, 2.6579275844515687E-01, 9.9687218193685878E-01, 0.0000000000000000E+00]
    c      = @SVector [0.0000000000000000E+00, 4.5158640252832094E-01, 1.0221535725056414E+00, 1.4280257701954349E+00, 7.1581334196229851E-01]

    new(gamma1, gamma2, gamma3, beta, delta, c)
  end
end


"""
    ParsaniKetchesonDeconinck3Sstar94()

Parsani, Ketcheson, Deconinck (2013)
  Optimized explicit RK schemes for the spectral difference method applied to wave propagation problems
[DOI: 10.1137/120885899](https://doi.org/10.1137/120885899)
"""
struct ParsaniKetchesonDeconinck3Sstar94 <: SimpleAlgorithm3Sstar
  gamma1::SVector{9, Float64}
  gamma2::SVector{9, Float64}
  gamma3::SVector{9, Float64}
  beta::SVector{9, Float64}
  delta::SVector{9, Float64}
  c::SVector{9, Float64}

  function ParsaniKetchesonDeconinck3Sstar94()
    gamma1 = @SVector [0.0000000000000000E+00, -4.6556413837561301E+00, -7.7202649689034453E-01, -4.0244202720632174E+00, -2.1296873883702272E-02, -2.4350219407769953E+00, 1.9856336960249132E-02, -2.8107894116913812E-01, 1.6894354373677900E-01]
    gamma2 = @SVector [1.0000000000000000E+00, 2.4992627683300688E+00, 5.8668202764174726E-01, 1.2051419816240785E+00, 3.4747937498564541E-01, 1.3213458736302766E+00, 3.1196363453264964E-01, 4.3514189245414447E-01, 2.3596980658341213E-01]
    gamma3 = @SVector [0.0000000000000000E+00, 0.0000000000000000E+00, 0.0000000000000000E+00, 7.6209857891449362E-01, -1.9811817832965520E-01, -6.2289587091629484E-01, -3.7522475499063573E-01, -3.3554373281046146E-01, -4.5609629702116454E-02]
    beta   = @SVector [2.8363432481011769E-01, 9.7364980747486463E-01, 3.3823592364196498E-01, -3.5849518935750763E-01, -4.1139587569859462E-03, 1.4279689871485013E+00, 1.8084680519536503E-02, 1.6057708856060501E-01, 2.9522267863254809E-01]
    delta  = @SVector [1.0000000000000000E+00, 1.2629238731608268E+00, 7.5749675232391733E-01, 5.1635907196195419E-01, -2.7463346616574083E-02, -4.3826743572318672E-01, 1.2735870231839268E+00, -6.2947382217730230E-01, 0.0000000000000000E+00]
    c      = @SVector [0.0000000000000000E+00, 2.8363432481011769E-01, 5.4840742446661772E-01, 3.6872298094969475E-01, -6.8061183026103156E-01, 3.5185265855105619E-01, 1.6659419385562171E+00, 9.7152778807463247E-01, 9.0515694340066954E-01]

    new(gamma1, gamma2, gamma3, beta, delta, c)
  end
end


"""
    ParsaniKetchesonDeconinck3Sstar32()

Parsani, Ketcheson, Deconinck (2013)
  Optimized explicit RK schemes for the spectral difference method applied to wave propagation problems
[DOI: 10.1137/120885899](https://doi.org/10.1137/120885899)
"""
struct ParsaniKetchesonDeconinck3Sstar32 <: SimpleAlgorithm3Sstar
  gamma1::SVector{3, Float64}
  gamma2::SVector{3, Float64}
  gamma3::SVector{3, Float64}
  beta::SVector{3, Float64}
  delta::SVector{3, Float64}
  c::SVector{3, Float64}

  function ParsaniKetchesonDeconinck3Sstar32()
    gamma1 = @SVector [0.0000000000000000E+00, -1.2664395576322218E-01, 1.1426980685848858E+00]
    gamma2 = @SVector [1.0000000000000000E+00, 6.5427782599406470E-01, -8.2869287683723744E-02]
    gamma3 = @SVector [0.0000000000000000E+00, 0.0000000000000000E+00, 0.0000000000000000E+00]
    beta   = @SVector [7.2366074728360086E-01, 3.4217876502651023E-01, 3.6640216242653251E-01]
    delta  = @SVector [1.0000000000000000E+00, 7.2196567116037724E-01, 0.0000000000000000E+00]
    c      = @SVector [0.0000000000000000E+00, 7.2366074728360086E-01, 5.9236433182015646E-01]

    new(gamma1, gamma2, gamma3, beta, delta, c)
  end
end


mutable struct SimpleIntegrator3SstarOptions{Callback}
  callback::Callback # callbacks; used in Trixi
  adaptive::Bool # whether the algorithm is adaptive; ignored
  dtmax::Float64 # ignored
  maxiters::Int # maximal numer of time steps
  tstops::Vector{Float64} # tstops from https://diffeq.sciml.ai/v6.8/basics/common_solver_opts/#Output-Control-1; ignored
end

function SimpleIntegrator3SstarOptions(callback, tspan; maxiters=typemax(Int), kwargs...)
  SimpleIntegrator3SstarOptions{typeof(callback)}(
    callback, false, Inf, maxiters, [last(tspan)])
end

mutable struct SimpleIntegrator3Sstar{RealT<:Real, uType, Params, Sol, Alg, SimpleIntegrator3SstarOptions}
  u::uType #
  du::uType
  u_tmp1::uType
  u_tmp2::uType
  t::RealT
  dt::RealT # current time step
  dtcache::RealT # ignored
  iter::Int # current number of time step (iteration)
  p::Params # will be the semidiscretization from Trixi
  sol::Sol # faked
  alg::Alg
  opts::SimpleIntegrator3SstarOptions
  finalstep::Bool # added for convenience
end

# Fakes `solve`: https://diffeq.sciml.ai/v6.8/basics/overview/#Solving-the-Problems-1
function solve(ode::ODEProblem, alg::T;
               dt, callback=nothing, kwargs...) where {T<:SimpleAlgorithm3Sstar}
  u = copy(ode.u0)
  du = similar(u)
  u_tmp1 = similar(u)
  u_tmp2 = similar(u)
  t = first(ode.tspan)
  iter = 0
  integrator = SimpleIntegrator3Sstar(u, du, u_tmp1, u_tmp2, t, dt, zero(dt), iter, ode.p,
                  (prob=ode,), alg,
                  SimpleIntegrator3SstarOptions(callback, ode.tspan; kwargs...), false)

  # initialize callbacks
  if callback isa CallbackSet
    for cb in callback.continuous_callbacks
      error("unsupported")
    end
    for cb in callback.discrete_callbacks
      cb.initialize(cb, integrator.u, integrator.t, integrator)
    end
  elseif !isnothing(callback)
    error("unsupported")
  end

  solve!(integrator)
end

function solve!(integrator::SimpleIntegrator3Sstar)
  @unpack prob = integrator.sol
  @unpack alg = integrator
  t_end = last(prob.tspan)
  callbacks = integrator.opts.callback

  integrator.finalstep = false
  @timeit_debug timer() "main loop" while !integrator.finalstep
    if isnan(integrator.dt)
      error("time step size `dt` is NaN")
    end

    # if the next iteration would push the simulation beyond the end time, set dt accordingly
    if integrator.t + integrator.dt > t_end || isapprox(integrator.t + integrator.dt, t_end)
      integrator.dt = t_end - integrator.t
      terminate!(integrator)
    end

    # one time step
    integrator.u_tmp1 .= zero(eltype(integrator.u_tmp1))
    integrator.u_tmp2 .= integrator.u
    for stage in eachindex(alg.c)
      t_stage = integrator.t + integrator.dt * alg.c[stage]
      prob.f(integrator.du, integrator.u, prob.p, t_stage)

      delta_stage   = alg.delta[stage]
      gamma1_stage  = alg.gamma1[stage]
      gamma2_stage  = alg.gamma2[stage]
      gamma3_stage  = alg.gamma3[stage]
      beta_stage_dt = alg.beta[stage] * integrator.dt
      @timeit_debug timer() "Runge-Kutta step" begin
        Threads.@threads for i in eachindex(integrator.u)
          integrator.u_tmp1[i] += delta_stage * integrator.u[i]
          integrator.u[i]       = (gamma1_stage * integrator.u[i] +
                                   gamma2_stage * integrator.u_tmp1[i] +
                                   gamma3_stage * integrator.u_tmp2[i] +
                                   beta_stage_dt * integrator.du[i])
        end
      end
    end
    integrator.iter += 1
    integrator.t += integrator.dt

    # handle callbacks
    if callbacks isa CallbackSet
      for cb in callbacks.discrete_callbacks
        if cb.condition(integrator.u, integrator.t, integrator)
          cb.affect!(integrator)
        end
      end
    end
  end

  return (t=prob.tspan,
          u=(copy(prob.u0), copy(integrator.u)),
          prob=integrator.sol.prob)
end

# get a cache where the RHS can be stored
get_du(integrator::SimpleIntegrator3Sstar) = integrator.du

# some algorithms from DiffEq like FSAL-ones need to be informed when a callback has modified u
u_modified!(integrator::SimpleIntegrator3Sstar, ::Bool) = false

# used by adaptive timestepping algorithms in DiffEq
function set_proposed_dt!(integrator::SimpleIntegrator3Sstar, dt)
  integrator.dt = dt
end

# stop the time integration
function terminate!(integrator::SimpleIntegrator3Sstar)
  integrator.finalstep = true
  empty!(integrator.opts.tstops)
end

# used for AMR
function Base.resize!(integrator::SimpleIntegrator3Sstar, new_size)
  resize!(integrator.u, new_size)
  resize!(integrator.du, new_size)
  resize!(integrator.u_tmp1, new_size)
  resize!(integrator.u_tmp2, new_size)
end
