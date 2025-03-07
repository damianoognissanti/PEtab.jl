# Models with pre-equilibration (steady-state simulation)

In this tutorial, we'll create a `PEtabODEproblem` for the Brannmark model, which requires pre-equilibration before comparing the model against data. In other words, the model must first reach a steady state where $du = f(u, p, t) \approx 0$ before it is matches against data. This can be achieved through simulations or root finding.

To run the code, you will need the Brannmark PEtab files which can be found [here](https://github.com/sebapersson/PEtab.jl/tree/main/examples/Brannmark/). A fully runnable example of this tutorial is available [here](https://github.com/sebapersson/PEtab.jl/tree/main/examples/Brannmark.jl).

First, we load the necessary libraries and read the model.

```julia
using PEtab
using OrdinaryDiffEq
using Printf

pathYaml = joinpath(@__DIR__, "Brannmark", "Brannmark_JBC2010.yaml")
petabModel = readPEtabModel(pathYaml, verbose=true)
```
```
PEtabModel for model Brannmark. ODE-system has 9 states and 23 parameters.
Generated Julia files are at ...
```

## Steady-state solver

When dealing with pre-equilibration models, we must first reach a steady state $du = f(u, p, t) ≈ 0$ before running the main simulation. We can do this in two ways: i) using `:Rootfinding`, where we use any algorithm from [NonlinearSolve.jl](https://github.com/SciML/NonlinearSolve.jl) to find the roots of $f$, and ii) using `:Simulate`, where we simulate the model from the initial condition until it reaches a steady state. The latter method is more stable and often performs better.

When creating a `PEtabODEProblem`, we can set steady-state solver options via `SteadyStateSolverOptions`. The first argument is the method to use, either `:Rootfinding` or `:Simulate` (recommended). For `:Simulate`, we can choose how to terminate the steady-state simulation using the `howCheckSimulationReachedSteadyState` argument, which accepts two options:

1. `:wrms`: the weighted root-mean square $\sqrt{\sum_{i=1}^n \bigg( \frac{du[i]}{\mathrm{reltol}*u[i] + \mathrm{abstol}} \bigg)  \frac{1}{n}} \leq 1$, where $n$ is the number of ODEs.
2. `:Newton`: if the Newton-step $\Delta u$ is sufficiently small $\sqrt{\sum_{i=1}^n \bigg( \frac{\Delta u[i]}{\mathrm{reltol}*u[i] + \mathrm{abstol}} \bigg)  \frac{1}{n}} \leq 1$.

Newton often performs better, but it requires an invertible Jacobian. If the Jacobian is non-invertible, the code automatically switches to `:wrms`. The default values for `abstol` and `reltol` are the tolerances of the ODE solver divided by 100.

In the example below, we use `:Simulate` with `:wrms` termination:

```julia
petabProblem = createPEtabODEProblem(petabModel, 
                                     odeSolverOptions=ODESolverOptions(Rodas5P()),
                                     ssSolverOptions=SteadyStateSolverOptions(:Simulate,
                                                     howCheckSimulationReachedSteadyState=:wrms),
                                     gradientMethod=:ForwardDiff) 
p = petabProblem.θ_nominalT 
gradient = zeros(length(p)) 
cost = petabProblem.computeCost(p)
petabProblem.computeGradient!(gradient, p)
@printf("Cost= %.2f\n", cost)
@printf("First element in the gradient = %.2e\n", gradient[1])
```
```
Cost = 141.89
First element in the gradient = 2.70e-03
```

Some useful notes regarding the steady-state solver:

* If you do not specify a `SteadyStateSolverOption`, the default option is `:Simulate` with `:wrms`.
* You can also set a separate steady-state solver option for the gradient using `ssSolverGradientOptions`.
* All gradient and hessian options are compatible with `:Simulate`. However, `:Rootfinding` is only compatible with approaches that use forward-mode automatic differentiation.
