module Table5WelfareTests

using Test, TOML
include(joinpath(@__DIR__, "..", "experiments", "make_table5_welfare.jl"))

@testset "Table 5: source integrity without release labels" begin
    mktempdir() do root
        mkpath(joinpath(root, "data"))
        mkpath(joinpath(root, "experiments", "designs"))
        write(joinpath(root, "data", "io.csv"), "accounts\n")
        write(joinpath(root, "data", "programme.csv"), "programme\n")
        id = "table5-fixture-BF-F1"
        cell = Dict{String,Any}("labor" => "BF", "financing" => "F1", "eta" => 0.0,
            "eta_s" => 0.0, "theta" => 0.5, "epsilon" => 0.5, "sigma" => 0.9)
        design = Dict{String,Any}("design" => "table5-fixture",
            "data" => Dict("source_table" => "data/io.csv"),
            "programme" => Dict("source" => "data/programme.csv"), "cells" => Dict(id => cell))
        open(design_path(design["design"]; root), "w") do io
            TOML.print(io, design)
        end
        tree = repeat("a", 40)
        man = Dict{String,Any}("run_id" => id, "cell" => id, "design" => design["design"],
            "status" => "executed", "gates" => Dict("overall" => "pass"),
            "scenario" => Dict("labour" => "BF", "financing" => "F1", "eta" => 0.0,
                "eta_s" => 0.0, "theta" => 0.5, "epsilon" => 0.5, "sigma" => 0.9),
            "provenance" => Dict("design_sha256" => design_sha256(design["design"]; root),
                "data_sha256" => Dict(path => sha256_file(joinpath(root, path))
                    for path in ("data/io.csv", "data/programme.csv")),
                "opencge" => Dict("git_tree_sha1" => tree)))
        # Labels may be absent or renamed; identities and content remain fixed.
        @test check_table5_source(man, design, cell, id; root) == tree
        for label in ("former-release", "v1.0.0")
            labelled = deepcopy(man)
            labelled["provenance"]["opencge"]["repo_rev"] = label
            labelled["provenance"]["opencge"]["version"] = "arbitrary metadata"
            @test check_table5_source(labelled, design, cell, id; root, source_tree = tree) == tree
        end
        @test_throws ErrorException check_table5_source(man, design, cell, id;
            root, source_tree = repeat("b", 40))
        for (section, key, value) in (("gates", "overall", "fail"),
                ("scenario", "financing", "F2"), ("scenario", "theta", 0.7),
                ("provenance", "design_sha256", "stale"))
            changed = deepcopy(man)
            changed[section][key] = value
            @test_throws ErrorException check_table5_source(changed, design, cell, id; root)
        end
        changed = deepcopy(man)
        changed["run_id"] = "different-cell"
        @test_throws ErrorException check_table5_source(changed, design, cell, id; root)
        for path in ("data/io.csv", "data/programme.csv")
            original = read(joinpath(root, path), String)
            write(joinpath(root, path), "changed input\n")
            @test_throws ErrorException check_table5_source(man, design, cell, id; root)
            write(joinpath(root, path), original)
        end
    end
end

@testset "Table 5: reject numerical drift and failed current gates" begin
    metrics = Dict{String,Any}("consumption_rel" => -0.02, "gdp_rel" => 0.0)
    man = Dict("metrics" => metrics)
    evaluated = (; gates = Dict("overall" => "pass"), metrics = copy(metrics))
    @test isapprox(check_table5_result(man, evaluated, "fixture"), 0.0; atol = 1e-12)
    # Consumption can still agree while another recorded result has changed.
    evaluated.metrics["gdp_rel"] = 0.01
    @test_throws ErrorException check_table5_result(man, evaluated, "fixture")
    evaluated.metrics["gdp_rel"] = 0.0
    evaluated.gates["overall"] = "fail"
    @test_throws ErrorException check_table5_result(man, evaluated, "fixture")
    evaluated.gates["overall"] = "pass"
    delete!(evaluated.metrics, "gdp_rel")
    @test_throws ErrorException check_table5_result(man, evaluated, "fixture")
    evaluated.metrics["gdp_rel"] = NaN
    @test_throws ErrorException check_table5_result(man, evaluated, "fixture")
end

end
