@testset "negativebinomial pdf, cdf, etc." begin
    nn = [1, 2, 5, 10, 25, 50, 100]
    pp = [0.01, 0.05, 0.10, 0.50, 0.90, 0.95, 0.99]
    x = collect(0.0:1:50.0)

    for n in nn, p in pp
        l = Distributions.NegativeBinomial(n, p)
        r = LRMoE.NegativeBinomialExpert(n, p)
        @test LRMoE.logpdf.(r, x) ≈ Distributions.logpdf.(l, x)
        @test LRMoE.logcdf.(r, x) ≈ Distributions.logcdf.(l, x)
        @test LRMoE.pdf.(r, x) ≈ Distributions.pdf.(l, x)
        @test LRMoE.cdf.(r, x) ≈ Distributions.cdf.(l, x)
    end
end

@testset "negativebinomial expert_ll" begin
    nn = [1, 2, 5, 10, 25, 50, 100]
    pp = [0.01, 0.05, 0.10, 0.50, 0.90, 0.95, 0.99]
    x = collect(0.0:1:50.0)

    for n in nn, p in pp
        tmp = LRMoE.NegativeBinomialExpert(n, p)

        # exact observations
        @test isapprox(LRMoE.expert_ll_exact.(tmp, x), LRMoE.logpdf.(tmp, x))
        @test isapprox(LRMoE.expert_ll.(tmp, 0.0, x, x, Inf), LRMoE.logpdf.(tmp, x))

        # right censoring
        true_val =
            logcdf.(tmp, Inf) .+ log1mexp.(logcdf.(tmp, ceil.(x) .- 1) .- logcdf.(tmp, Inf))
        @test isapprox(LRMoE.expert_ll.(tmp, 0.0, x, Inf, Inf), true_val, atol=1e-6)

        true_val =
            logcdf.(tmp, 1.25 .* x) .+
            log1mexp.(logcdf.(tmp, ceil.(0.75 .* x) .- 1) .- logcdf.(tmp, 1.25 .* x))
        @test isapprox(
            LRMoE.expert_ll.(tmp, 0.0, 0.75 .* x, 1.25 .* x, Inf), true_val, atol=1e-6
        )

        # exact observations
        @test isapprox(LRMoE.expert_tn.(tmp, 0.0, x, x, Inf), fill(0.0, length(x)))

        # censoring + truncation
        true_val =
            logcdf.(tmp, 1.5 .* x) .+
            log1mexp.(logcdf.(tmp, ceil.(0.25 .* x) .- 1) .- logcdf.(tmp, 1.5 .* x))
        @test isapprox(
            LRMoE.expert_tn.(tmp, 0.25 .* x, 0.75 .* x, 1.25 .* x, 1.5 .* x),
            true_val,
            atol=1e-6,
        )

        # exact observations
        @test isapprox(LRMoE.expert_tn_bar.(tmp, 0.0, x, x, Inf), fill(-Inf, length(x)))

        # censoring + truncation
        true_val =
            log1mexp.(
                logcdf.(tmp, 1.5 .* x) .+
                log1mexp.(logcdf.(tmp, ceil.(0.25 .* x) .- 1) .- logcdf.(tmp, 1.5 .* x))
            )
        @test isapprox(
            LRMoE.expert_tn_bar.(tmp, 0.25 .* x, 0.75 .* x, 1.25 .* x, 1.5 .* x),
            true_val,
            atol=1e-6,
        )
    end
end

@testset "negativebinomial exposurize" begin
    d = NegativeBinomialExpert()
    exposure_vec = [0.5, 1.0, 2.0, 5.0, 10.0]

    for e in exposure_vec
        @test mean(LRMoE.exposurize_expert(d; exposure=e)) == mean(d) * e
    end
end
