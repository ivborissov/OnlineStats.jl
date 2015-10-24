#---------------------------------------------------------------------# ProxGrad
# θ_t = argmin(η * g'θ + η * J(θ) + B_ψ(θ, θ_t))  where  ψ = .5 * θ' * H * θ
"Proximal Gradient Method with ADAGRAD weights"
type ProxGrad <: Algorithm
    G0::Float64     # sum of squared gradients for intercept
    G::VecF         # sum of squared gradients for everything else
    η::Float64      # constant step size
    function ProxGrad(;η::Real = 1.0, δ::Real = 1e-8)
        @assert η > 0
        @assert δ > 0
        new(Float64(δ), zeros(2), Float64(η))
    end
end

Base.show(io::IO, o::ProxGrad) = print(io, "ProxGrad(η = $(o.η))")

function updateβ!(o::StochasticModel{ProxGrad}, x::AVecF, y::Float64)
    if nobs(o) == 1 # on first update, set the size of o.algorithm.G
        alg(o).G = zeros(length(x)) + alg(o).G0
    end

    g = ∇f(o.model, y, predict(o, x))

    if o.intercept
        alg(o).G0 += g^2
        o.β0 -= alg(o).η * g / sqrt(alg(o).G0)
    end

    @inbounds for j in 1:length(x)
        gi = g * x[j]
        alg(o).G[j] += gi^2
        adagrad_update!(o, gi, j)
    end
end

function updatebatchβ!(o::StochasticModel{ProxGrad}, x::AMatF, y::AVecF)
    if alg(o).G == zeros(2) # on first update, set the size of o.algorithm.G
        alg(o).G = zeros(length(x)) + alg(o).G0
    end
    n = length(y)
    ŷ = predict(o, x)

    # update intercept
    if o.intercept
        g = 0.0
        for i in 1:n
            g += ∇f(o.model, y[i], ŷ[i])
        end
        g /= n
        alg(o).G0 += g^2
        o.β0 -= alg(o).η * g / sqrt(alg(o).G0)
    end

    # update everything else
    for j in 1:size(x, 2)
        g = 0.0
        for i in 1:n
            g += x[i, j] * ∇f(o.model, y[i], ŷ[i])
        end
        g /= n
        alg(o).G[j] += g^2
        proxgrad_update!(o, g, j)
    end
end

# L2Penalty
@inline function proxgrad_update!{M<:ModelDefinition}(o::StochasticModel{ProxGrad,M,L2Penalty}, g::Float64, j::Int)
    o.β[j] -= alg(o).η * (g + pen(o).λ * o.β[j]) / sqrt(alg(o).G[j])
end

# nondifferentiable penalties and NoPenalty
@inline function proxgrad_update!{M<:ModelDefinition, P<:Penalty}(o::StochasticModel{ProxGrad,M,P}, g::Float64, j::Int)
    h = alg(o).η / sqrt(alg(o).G[j])
    o.β[j] = prox(o.penalty, o.β[j] - g * h, h)
end
