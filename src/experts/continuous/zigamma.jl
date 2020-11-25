struct ZIGammaExpert{T<:Real} <: ZIContinuousExpert
    p::T
    k::T
    θ::T
    ZIGammaExpert{T}(p::T, k::T, θ::T) where {T<:Real} = new{T}(p, k, θ)
end


function ZIGammaExpert(p::T, k::T, θ::T; check_args=true) where {T <: Real}
    check_args && @check_args(ZIGammaExpert, 0 <= p <= 1 && k >= zero(k) && θ > zero(θ))
    return ZIGammaExpert{T}(p, k, θ)
end


#### Outer constructors
ZIGammaExpert(p::Real, k::Real, θ::Real) = ZIGammaExpert(promote(p, k, θ)...)
ZIGammaExpert(p::Integer, k::Integer, θ::Integer) = ZIGammaExpert(float(p), float(k), float(θ))
ZIGammaExpert() = ZIGammaExpert(0.50, 1.0, 1.0)

## Conversion
function convert(::Type{ZIGammaExpert{T}}, p::S, k::S, θ::S) where {T <: Real, S <: Real}
    ZIGammaExpert(T(p), T(k), T(θ))
end
function convert(::Type{ZIGammaExpert{T}}, d::ZIGammaExpert{S}) where {T <: Real, S <: Real}
    ZIGammaExpert(T(d.p), T(d.k), T(d.θ), check_args=false)
end
copy(d::ZIGammaExpert) = ZIGammaExpert(d.p, d.k, d.θ, check_args=false)

## Loglikelihood of Expoert
logpdf(d::ZIGammaExpert, x...) = (d.k < 1 && x... <= 0.0) ? -Inf : Distributions.logpdf.(Distributions.Gamma(d.k, d.θ), x...)
pdf(d::ZIGammaExpert, x...) = (d.k < 1 && x... <= 0.0) ? 0.0 : Distributions.pdf.(Distributions.Gamma(d.k, d.θ), x...)
logcdf(d::ZIGammaExpert, x...) = (d.k < 1 && x... <= 0.0) ? -Inf : Distributions.logcdf.(Distributions.Gamma(d.k, d.θ), x...)
cdf(d::ZIGammaExpert, x...) = (d.k < 1 && x... <= 0.0) ? 0.0 : Distributions.cdf.(Distributions.Gamma(d.k, d.θ), x...)

## Parameters
params(d::ZIGammaExpert) = (d.p, d.k, d.θ)
function params_init(y, d::ZIGammaExpert)
    p_init = sum(y .== 0.0) / sum(y .>= 0.0)
    pos_idx = (y .> 0.0)
    μ, σ2 = mean(y[pos_idx]), var(y[pos_idx])
    θ_init = σ2/μ
    k_init = μ/θ_init
    if isnan(θ_init) || isnan(k_init)
        return ZIGammaExpert()
    else
        return ZIGammaExpert(p_init, k_init, θ_init)
    end
end

## KS stats for parameter initialization
function ks_distance(y, d::ZIGammaExpert)
    p_zero = sum(y .== 0.0) / sum(y .>= 0.0)
    return max(abs(p_zero-d.p), (1-d.p)*HypothesisTests.ksstats(y[y .> 0.0], Distributions.Gamma(d.k, d.θ))[2])
end

## Simululation
sim_expert(d::ZIGammaExpert, sample_size) = (1 .- Distributions.rand(Distributions.Bernoulli(d.p), sample_size)) .* Distributions.rand(Distributions.Gamma(d.k, d.θ), sample_size)

## penalty
penalty_init(d::ZIGammaExpert) = [2.0 10.0 2.0 10.0]
no_penalty_init(d::ZIGammaExpert) = [1.0 Inf 1.0 Inf]
penalize(d::ZIGammaExpert, p) = (p[1]-1)*log(d.k) - d.k/p[2] + (p[3]-1)*log(d.θ) - d.θ/p[4]

## statistics
mean(d::ZIGammaExpert) = (1-d.p)*mean(Distributions.Gamma(d.k, d.θ))
var(d::ZIGammaExpert) = (1-d.p)*var(Distributions.Gamma(d.k, d.θ)) + d.p*(1-d.p)*(mean(Distributions.Gamma(d.k, d.θ)))^2
quantile(d::ZIGammaExpert, p) = p <= d.p ? 0.0 : quantile(Distributions.Gamma(d.k, d.θ), p-d.p)

## EM: M-Step
function EM_M_expert(d::ZIGammaExpert,
                     tl, yl, yu, tu,
                     expert_ll_pos,
                     expert_tn_pos,
                     expert_tn_bar_pos,
                     z_e_obs, z_e_lat, k_e;
                     penalty = true, pen_pararms_jk = [1.0 Inf 1.0 Inf])
    
    # Old parameters
    p_old = d.p

    # Update zero probability
    z_zero_e_obs = z_e_obs .* EM_E_z_zero_obs(yl, p_old, expert_ll_pos)
    z_pos_e_obs = z_e_obs .- z_zero_e_obs
    z_zero_e_lat = z_e_lat .* EM_E_z_zero_lat(tl, p_old, expert_tn_bar_pos)
    z_pos_e_lat = z_e_lat .- z_zero_e_lat
    p_new = EM_M_zero(z_zero_e_obs, z_pos_e_obs, z_zero_e_lat, z_pos_e_lat, k_e)

    # Update parameters: call its positive part
    tmp_exp = GammaExpert(d.k, d.θ)
    tmp_update = EM_M_expert(tmp_exp,
                            tl, yl, yu, tu,
                            expert_ll_pos,
                            expert_tn_pos,
                            expert_tn_bar_pos,
                            # z_e_obs, z_e_lat, k_e,
                            z_pos_e_obs, z_pos_e_lat, k_e,
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZIGammaExpert(p_new, tmp_update.k, tmp_update.θ)
end

## EM: M-Step, exact observations
function EM_M_expert_exact(d::ZIGammaExpert,
                     ye,
                     expert_ll_pos,
                     z_e_obs;
                     penalty = true, pen_pararms_jk = [Inf 1.0 Inf])
    
    # Old parameters
    p_old = d.p

    # Update zero probability
    z_zero_e_obs = z_e_obs .* EM_E_z_zero_obs(ye, p_old, expert_ll_pos)
    z_pos_e_obs = z_e_obs .- z_zero_e_obs
    z_zero_e_lat = 0.0
    z_pos_e_lat = 0.0
    p_new = EM_M_zero(z_zero_e_obs, z_pos_e_obs, 0.0, 0.0, 0.0)
        # EM_M_zero(z_zero_e_obs, z_pos_e_obs, z_zero_e_lat, z_pos_e_lat, k_e)

    # Update parameters: call its positive part
    tmp_exp = GammaExpert(d.k, d.θ)
    tmp_update = EM_M_expert_exact(tmp_exp,
                            ye,
                            expert_ll_pos,
                            z_pos_e_obs;
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZIGammaExpert(p_new, tmp_update.k, tmp_update.θ)
end