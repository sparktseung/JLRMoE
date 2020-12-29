struct ZIWeibullExpert{T<:Real} <: ZIContinuousExpert
    p::T
    k::T
    θ::T
    ZIWeibullExpert{T}(p::T, k::T, θ::T) where {T<:Real} = new{T}(p, k, θ)
end


function ZIWeibullExpert(p::T, k::T, θ::T; check_args=true) where {T <: Real}
    check_args && @check_args(ZIWeibullExpert, 0 <= p <= 1 && k >= one(k) && θ > zero(θ))
    return ZIWeibullExpert{T}(p, k, θ)
end


#### Outer constructors
ZIWeibullExpert(p::Real, k::Real, θ::Real) = ZIWeibullExpert(promote(p, k, θ)...)
ZIWeibullExpert(p::Integer, k::Integer, θ::Integer) = ZIWeibullExpert(float(p), float(k), float(θ))
ZIWeibullExpert() = ZIWeibullExpert(0.5, 2.0, 1.0)

## Conversion
function convert(::Type{ZIWeibullExpert{T}}, p::S, k::S, θ::S) where {T <: Real, S <: Real}
    ZIWeibullExpert(T(p), T(k), T(θ))
end
function convert(::Type{ZIWeibullExpert{T}}, d::ZIWeibullExpert{S}) where {T <: Real, S <: Real}
    ZIWeibullExpert(T(d.p), T(d.k), T(d.θ), check_args=false)
end
copy(d::ZIWeibullExpert) = ZIWeibullExpert(d.p, d.k, d.θ, check_args=false)

## Loglikelihood of Expoert
logpdf(d::ZIWeibullExpert, x...) = Distributions.logpdf.(Distributions.Weibull(d.k, d.θ), x...)
pdf(d::ZIWeibullExpert, x...) = Distributions.pdf.(Distributions.Weibull(d.k, d.θ), x...)
logcdf(d::ZIWeibullExpert, x...) = Distributions.logcdf.(Distributions.Weibull(d.k, d.θ), x...)
cdf(d::ZIWeibullExpert, x...) = Distributions.cdf.(Distributions.Weibull(d.k, d.θ), x...)

## Parameters
params(d::ZIWeibullExpert) = (d.p, d.k, d.θ)
function params_init(y, d::ZIWeibullExpert)
    p_init = sum(y .== 0.0) / sum(y .>= 0.0)
    pos_idx = (y .> 0.0)

    k_init, θ_init = params(params_init(y[pos_idx], WeibullExpert()))
    try 
        return ZIWeibullExpert(p_init, k_init, θ_init)
    catch; 
        ZIWeibullExpert()
    end
end

## KS stats for parameter initialization
function ks_distance(y, d::ZIWeibullExpert)
    p_zero = sum(y .== 0.0) / sum(y .>= 0.0)
    return max(abs(p_zero-d.p), (1-d.p)*HypothesisTests.ksstats(y[y .> 0.0], Distributions.Weibull(d.k, d.θ))[2])
end

## Simululation
sim_expert(d::ZIWeibullExpert, sample_size) = (1 .- Distributions.rand(Distributions.Bernoulli(d.p), sample_size)) .* Distributions.rand(Distributions.Weibull(d.k, d.θ), sample_size)

## penalty
penalty_init(d::ZIWeibullExpert) = [2.0 10.0 2.0 10.0]
no_penalty_init(d::ZIWeibullExpert) = [1.0 Inf 1.0 Inf]
penalize(d::ZIWeibullExpert, p) = (p[1]-1)*log(d.k) - d.k/p[2] + (p[3]-1)*log(d.θ) - d.θ/p[4]

## statistics
mean(d::ZIWeibullExpert) = (1-d.p)*mean(Distributions.Weibull(d.k, d.θ))
var(d::ZIWeibullExpert) = (1-d.p)*var(Distributions.Weibull(d.k, d.θ)) + d.p*(1-d.p)*(mean(Distributions.Weibull(d.k, d.θ)))^2
quantile(d::ZIWeibullExpert, p) = p <= d.p ? 0.0 : quantile(Distributions.Weibull(d.k, d.θ), p-d.p)
lev(d::ZIWeibullExpert, u) = (1-d.p)*lev(WeibullExpert(d.k, d.θ), u)
excess(d::ZIWeibullExpert, u) = mean(d) - lev(d, u)

## EM: M-Step
function EM_M_expert(d::ZIWeibullExpert,
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
    tmp_exp = WeibullExpert(d.k, d.θ)
    tmp_update = EM_M_expert(tmp_exp,
                            tl, yl, yu, tu,
                            expert_ll_pos,
                            expert_tn_pos,
                            expert_tn_bar_pos,
                            # z_e_obs, z_e_lat, k_e,
                            z_pos_e_obs, z_pos_e_lat, k_e,
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZIWeibullExpert(p_new, tmp_update.k, tmp_update.θ)
end

## EM: M-Step, exact observations
function EM_M_expert_exact(d::ZIWeibullExpert,
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
    tmp_exp = WeibullExpert(d.k, d.θ)
    tmp_update = EM_M_expert_exact(tmp_exp,
                            ye,
                            expert_ll_pos,
                            z_pos_e_obs;
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZIWeibullExpert(p_new, tmp_update.k, tmp_update.θ)
end