function computeCost(θ_est::V,
                     odeProblem::ODEProblem,
                     odeSolverOptions::ODESolverOptions,
                     ssSolverOptions::SteadyStateSolverOptions,
                     petabModel::PEtabModel,
                     simulationInfo::SimulationInfo,
                     θ_indices::ParameterIndices,
                     measurementInfo::MeasurementsInfo,
                     parameterInfo::ParametersInfo,
                     priorInfo::PriorInfo,
                     petabODECache::PEtabODEProblemCache,
                     petabODESolverCache::PEtabODESolverCache,
                     expIDSolve::Vector{Symbol},
                     computeCost::Bool,
                     computeHessian::Bool,
                     computeResiduals::Bool) where V

    θ_dynamic, θ_observable, θ_sd, θ_nonDynamic = splitParameterVector(θ_est, θ_indices)

    cost = computeCostSolveODE(θ_dynamic, θ_sd, θ_observable, θ_nonDynamic, odeProblem, odeSolverOptions, ssSolverOptions, petabModel,
                               simulationInfo, θ_indices, measurementInfo, parameterInfo, petabODECache, petabODESolverCache,
                               computeCost=computeCost,
                               computeHessian=computeHessian,
                               computeResiduals=computeResiduals,
                               expIDSolve=expIDSolve)

    if priorInfo.hasPriors == true && computeHessian == false
        θ_estT = transformθ(θ_est, θ_indices.θ_estNames, θ_indices)
        cost -= computePriors(θ_est, θ_estT, θ_indices.θ_estNames, priorInfo) # We work with -loglik
    end

    return cost
end


function computeCostSolveODE(θ_dynamic::AbstractVector,
                             θ_sd::AbstractVector,
                             θ_observable::AbstractVector,
                             θ_nonDynamic::AbstractVector,
                             odeProblem::ODEProblem,
                             odeSolverOptions::ODESolverOptions,
                             ssSolverOptions::SteadyStateSolverOptions,
                             petabModel::PEtabModel,
                             simulationInfo::SimulationInfo,
                             θ_indices::ParameterIndices,
                             measurementInfo::MeasurementsInfo,
                             parameterInfo::ParametersInfo,
                             petabODECache::PEtabODEProblemCache,
                             petabODESolverCache::PEtabODESolverCache;
                             computeCost::Bool=false,
                             computeHessian::Bool=false,
                             computeGradientDynamicθ::Bool=false,
                             computeResiduals::Bool=false,
                             expIDSolve::Vector{Symbol} = [:all])::Real

    if computeGradientDynamicθ == true && petabODECache.nθ_dynamicEst[1] != length(θ_dynamic)
        _θ_dynamic = θ_dynamic[petabODECache.θ_dynamicOutputOrder]
        θ_dynamicT = transformθ(_θ_dynamic, θ_indices.θ_dynamicNames, θ_indices, :θ_dynamic, petabODECache)
    else
        θ_dynamicT = transformθ(θ_dynamic, θ_indices.θ_dynamicNames, θ_indices, :θ_dynamic, petabODECache)
    end

    θ_sdT = transformθ(θ_sd, θ_indices.θ_sdNames, θ_indices, :θ_sd, petabODECache)
    θ_observableT = transformθ(θ_observable, θ_indices.θ_observableNames, θ_indices, :θ_observable, petabODECache)
    θ_nonDynamicT = transformθ(θ_nonDynamic, θ_indices.θ_nonDynamicNames, θ_indices, :θ_nonDynamic, petabODECache)

    _odeProblem = remake(odeProblem, p = convert.(eltype(θ_dynamicT), odeProblem.p), u0 = convert.(eltype(θ_dynamicT), odeProblem.u0))
    changeODEProblemParameters!(_odeProblem.p, _odeProblem.u0, θ_dynamicT, θ_indices, petabModel)

    # If computing hessian or gradient store ODE solution in arrary with dual numbers, else use
    # solution array with floats
    if computeHessian == true || computeGradientDynamicθ == true
        success = solveODEAllExperimentalConditions!(simulationInfo.odeSolutionsDerivatives, _odeProblem, petabModel, θ_dynamicT, petabODESolverCache, simulationInfo, θ_indices, odeSolverOptions, ssSolverOptions, expIDSolve=expIDSolve, denseSolution=false, onlySaveAtObservedTimes=true)
    elseif computeCost == true
        success = solveODEAllExperimentalConditions!(simulationInfo.odeSolutions, _odeProblem, petabModel, θ_dynamicT, petabODESolverCache, simulationInfo, θ_indices, odeSolverOptions, ssSolverOptions, expIDSolve=expIDSolve, denseSolution=false, onlySaveAtObservedTimes=true)
    end
    if success != true
        @warn "Failed to solve ODE model"
        return Inf
    end

    cost = _computeCost(θ_sdT, θ_observableT, θ_nonDynamicT, petabModel, simulationInfo, θ_indices, measurementInfo,
                        parameterInfo, expIDSolve,
                        computeHessian=computeHessian,
                        computeGradientDynamicθ=computeGradientDynamicθ,
                        computeResiduals=computeResiduals)

    return cost
end


function computeCostNotSolveODE(θ_sd::AbstractVector,
                                θ_observable::AbstractVector,
                                θ_nonDynamic::AbstractVector,
                                petabModel::PEtabModel,
                                simulationInfo::SimulationInfo,
                                θ_indices::ParameterIndices,
                                measurementInfo::MeasurementsInfo,
                                parameterInfo::ParametersInfo,
                                petabODECache::PEtabODEProblemCache;
                                computeGradientNotSolveAutoDiff::Bool=false,
                                computeGradientNotSolveAdjoint::Bool=false,
                                computeGradientNotSolveForward::Bool=false,
                                expIDSolve::Vector{Symbol} = [:all])::Real

    # To be able to use ReverseDiff sdParamEstUse and obsParamEstUse cannot be overwritten.
    # Hence new vectors have to be created. Minimal overhead.
    θ_sdT = transformθ(θ_sd, θ_indices.θ_sdNames, θ_indices, :θ_sd, petabODECache)
    θ_observableT = transformθ(θ_observable, θ_indices.θ_observableNames, θ_indices, :θ_observable, petabODECache)
    θ_nonDynamicT = transformθ(θ_nonDynamic, θ_indices.θ_nonDynamicNames, θ_indices, :θ_nonDynamic, petabODECache)

    cost = _computeCost(θ_sdT, θ_observableT, θ_nonDynamicT, petabModel, simulationInfo, θ_indices,
                        measurementInfo, parameterInfo, expIDSolve,
                        computeGradientNotSolveAutoDiff=computeGradientNotSolveAutoDiff,
                        computeGradientNotSolveAdjoint=computeGradientNotSolveAdjoint,
                        computeGradientNotSolveForward=computeGradientNotSolveForward)

    return cost
end


function _computeCost(θ_sd::AbstractVector,
                      θ_observable::AbstractVector,
                      θ_nonDynamic::AbstractVector,
                      petabModel::PEtabModel,
                      simulationInfo::SimulationInfo,
                      θ_indices::ParameterIndices,
                      measurementInfo::MeasurementsInfo,
                      parameterInfo::ParametersInfo,
                      expIDSolve::Vector{Symbol} = [:all];
                      computeHessian::Bool=false,
                      computeGradientDynamicθ::Bool=false,
                      computeResiduals::Bool=false,
                      computeGradientNotSolveAdjoint::Bool=false,
                      computeGradientNotSolveForward::Bool=false,
                      computeGradientNotSolveAutoDiff::Bool=false)::Real

    if computeHessian == true || computeGradientDynamicθ == true || computeGradientNotSolveAdjoint == true || computeGradientNotSolveForward == true || computeGradientNotSolveAutoDiff == true
        odeSolutions = simulationInfo.odeSolutionsDerivatives
    else
        odeSolutions = simulationInfo.odeSolutions
    end

    cost = 0.0
    for experimentalConditionId in simulationInfo.experimentalConditionId

        if expIDSolve[1] != :all && experimentalConditionId ∉ expIDSolve
            continue
        end

        # Extract the ODE-solution for specific condition ID
        odeSolution = odeSolutions[experimentalConditionId]
        cost += computeCostExpCond(odeSolution, Float64[], θ_sd, θ_observable, θ_nonDynamic, petabModel,
                                   experimentalConditionId, θ_indices, measurementInfo, parameterInfo, simulationInfo,
                                   computeResiduals=computeResiduals,
                                   computeGradientNotSolveAdjoint=computeGradientNotSolveAdjoint,
                                   computeGradientNotSolveForward=computeGradientNotSolveForward,
                                   computeGradientNotSolveAutoDiff=computeGradientNotSolveAutoDiff)

        if isinf(cost)
            return Inf
        end
    end

    return cost
end


function computeCostExpCond(odeSolution::ODESolution,
                            pODEProblemZygote::AbstractVector,
                            θ_sd::AbstractVector,
                            θ_observable::AbstractVector,
                            θ_nonDynamic::AbstractVector,
                            petabModel::PEtabModel,
                            experimentalConditionId::Symbol,
                            θ_indices::ParameterIndices,
                            measurementInfo::MeasurementsInfo,
                            parameterInfo::ParametersInfo,
                            simulationInfo::SimulationInfo;
                            computeResiduals::Bool=false,
                            computeGradientNotSolveAdjoint::Bool=false,
                            computeGradientNotSolveForward::Bool=false,
                            computeGradientNotSolveAutoDiff::Bool=false,
                            computeGradientθDynamicZygote::Bool=false)::Real

    if !(odeSolution.retcode == ReturnCode.Success || odeSolution.retcode == ReturnCode.Terminated)
        return Inf
    end

    cost = 0.0
    for iMeasurement in simulationInfo.iMeasurements[experimentalConditionId]

        t = measurementInfo.time[iMeasurement]

        # In these cases we only save the ODE at observed time-points and we do not want
        # to extract Dual ODE solution
        if computeGradientNotSolveForward == true || computeGradientNotSolveAutoDiff == true
            nModelStates = length(petabModel.stateNames)
            u = dualToFloat.(odeSolution[1:nModelStates, simulationInfo.iTimeODESolution[iMeasurement]])
            p = dualToFloat.(odeSolution.prob.p)
        # For adjoint sensitivity analysis we have a dense-ode solution
        elseif computeGradientNotSolveAdjoint == true
            # In case we only have sol.t = 0.0 (or similar) interpolation does not work
            u = length(odeSolution.t) > 1 ? odeSolution(t) : odeSolution[1]
            p = odeSolution.prob.p

        elseif computeGradientθDynamicZygote == true
            u = odeSolution[:, simulationInfo.iTimeODESolution[iMeasurement]]
            p = pODEProblemZygote

        # When we want to extract dual number from the ODE solution
        else
            u = odeSolution[:, simulationInfo.iTimeODESolution[iMeasurement]]
            p = odeSolution.prob.p
        end

        h = computeh(u, t, p, θ_observable, θ_nonDynamic, petabModel, iMeasurement, measurementInfo, θ_indices, parameterInfo)
        hTransformed = transformMeasurementOrH(h, measurementInfo.measurementTransformation[iMeasurement])
        σ = computeσ(u, t, p, θ_sd, θ_nonDynamic, petabModel, iMeasurement, measurementInfo, θ_indices, parameterInfo)
        residual = (hTransformed - measurementInfo.measurementT[iMeasurement]) / σ

        # These values might be needed by different software, e.g. PyPesto, to assess things such as parameter uncertainity. By storing them in
        # measurementInfo they can easily be computed given a call to the cost function has been made.
        updateMeasurementInfo!(measurementInfo, h, hTransformed, σ, residual, iMeasurement)

        # By default a positive ODE solution is not enforced (even though the user can provide it as option).
        # In case with transformations on the data the code can crash, hence Inf is returned in case the
        # model data transformation can not be perfomred.
        if isinf(hTransformed)
            println("Warning - transformed observable is non-finite for measurement $iMeasurement")
            return Inf
        end

        # Update log-likelihood. In case of guass newton approximation we are only interested in the residuals, and here
        # we allow the residuals to be computed to test the gauss-newton implementation
        if computeResiduals == false
            if measurementInfo.measurementTransformation[iMeasurement] === :lin
                cost += log(σ) + 0.5*log(2*pi) + 0.5*residual^2
            elseif measurementInfo.measurementTransformation[iMeasurement] === :log10
                cost += log(σ) + 0.5*log(2*pi) + log(log(10)) + log(10)*measurementInfo.measurementT[iMeasurement] + 0.5*residual^2
            elseif measurementInfo.measurementTransformation[iMeasurement] === :log
                cost += log(σ) + 0.5*log(2*pi) + log(measurementInfo.measurement[iMeasurement]) + 0.5*residual^2
            else
                println("Transformation ", measurementInfo.measurementTransformation[iMeasurement], " not yet supported.")
                return Inf
            end
        elseif computeResiduals == true
            cost += residual
        end
    end
    return cost
end


function updateMeasurementInfo!(measurementInfo::MeasurementsInfo, h::T, hTransformed::T, σ::T, residual::T, iMeasurement) where {T<:AbstractFloat}
    ChainRulesCore.@ignore_derivatives begin
        measurementInfo.simulatedValues[iMeasurement] = h
        measurementInfo.chi2Values[iMeasurement] = (hTransformed - measurementInfo.measurementT[iMeasurement])^2 / σ^2
        measurementInfo.residuals[iMeasurement] = residual
    end
end
function updateMeasurementInfo!(measurementInfo::MeasurementsInfo, h, hTransformed, σ, residual, iMeasurement)
    return
end