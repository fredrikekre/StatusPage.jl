#!/usr/bin/env julia
import TOML

toml = Dict()
toml["interval"] = 60
toml["output_directory"] = "/www-root"
toml["title"] = "status.julialang.org"
toml["desc"] = "Status page for services hosted by JuliaLang"
toml["influxdb"] = Dict(
    "server" => "http://influxdb:8086",
    "db" => "telegraf",
    "measurement" => "http_response",
)

services = []
for pkgserver in [
        "https://eu-central.pkg.julialang.org",
        "https://us-west.pkg.julialang.org",
        "https://us-east.pkg.julialang.org",
        "https://kr.pkg.julialang.org",
        "https://sg.pkg.julialang.org",
        "https://in.pkg.julialang.org",
        "https://au.pkg.julialang.org",
        "https://sa.pkg.julialang.org",
        "https://cn-southeast.pkg.julialang.org",
        "https://cn-east.pkg.julialang.org",
        "https://cn-northeast.pkg.julialang.org",
    ]
    name = String(match(r"https://(.*)", pkgserver)[1])
    # checks = [pkgserver * "/meta", pkgserver * "/registries"]
    checks = [pkgserver * "/meta"]
    group = "Package servers"
    push!(services, Dict("name"=>name, "checks"=>checks, "group"=>group))
end

for sserver in ["https://us-east.storage.juliahub.com", "https://kr.storage.juliahub.com"]
    name = String(match(r"https://(.*)", sserver)[1])
    checks = [sserver * "/meta"]
    group = "Storage servers"
    push!(services, Dict("name"=>name, "checks"=>checks, "group"=>group))
end
toml["services"] = services

open(joinpath(@__DIR__, "config.toml"), "w") do io
    TOML.print(io, toml)
end
