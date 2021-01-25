module StatusPage

using InfluxDB, TOML, DataFrames, Dates, OrderedCollections, Artifacts

function run(config="config.toml")
    config = abspath(config)
    # Read config
    toml = TOML.parsefile(config)
    # TODO: Defaults
    server = InfluxServer(toml["influxdb"]["server"])
    measurement = toml["influxdb"]["measurement"]
    db = toml["influxdb"]["db"]
    output_directory = abspath(dirname(config), toml["output_directory"])
    mkpath(output_directory)
    interval = toml["interval"]
    ## Build the output structure
    group_service_map = OrderedDict()
    for service in toml["services"]
        vect = get!(Vector, group_service_map, get(service, "group", nothing))
        push!(vect, service)
    end
    ## Sort by group array
    if (groups = get(toml, "groups", nothing); groups !== nothing)
        # TODO: ...
    end
    sort!(group_service_map; lt = (x, y) -> x === nothing ? false : y === nothing ? true : x < y)
    ## All urls we are interested in
    all_urls = Set{String}(url for s in toml["services"] for url in s["checks"])

    while true
        t0 = time()
        # Make the InfluxDB query
        q = SELECT(measurements=[measurement], condition="time > now() - 91d")
        dfs = InfluxDB.query(server, db, q)
        if dfs === nothing
            df = DataFrame(time=String[], result=String[], server=String[])
        else
            df = dfs[1]
        end
        ## Keep only what we need
        select!(df, [:time, :result, :server])
        ## Convert to DateTime Date
        conv_dt(X) = map(x -> DateTime(x, dateformat"yyyy-mm-dd\THH:MM:SS\Z"), X)
        transform!(df, :time => conv_dt => :time)
        transform!(df, :time => (X -> Date.(X)) => :date)
        # Filter out from the config
        filter!(:server => (x -> x in all_urls), df)
        ## Add service and group from the config
        function assign_name_group(X)
            n = String[]
            g = Union{String,Nothing}[]
            for x in X
                for (group, services) in group_service_map, service in services
                    if x in service["checks"]
                        push!(n, service["name"])
                        push!(g, group)
                        break
                    end
                end
            end
            return (name=n, group=g) # ??
        end
        transform!(df, :server => assign_name_group => [:config_name, :config_group])
        # Convert result to binary
        transform!(df, :result => (X -> map(x -> x == "success", X)) => :result)

        # Generate html
        index = joinpath(output_directory, "index.html")
        index_tmp = index * ".tmp"
        try
            open(index_tmp, "w") do io
                generate_html(io, df, group_service_map, toml)
            end
            mv(index_tmp, index; force=true)
        finally
            rm(index_tmp; force=true)
        end
        ## Copy asset files
        copy_assets(output_directory)

        sleeptime = interval - (time() - t0)
        @info "Generated status page, regenerating in $(round(Int, sleeptime)) seconds."
        if sleeptime > 0
            sleep(sleeptime)
        end
    end
end

function copy_safe(src, dst)
    if filesize(src) == filesize(dst)
        return # Assume file has not changed...
    end
    tmp = dst * ".tmp"
    try
        open(tmp, "w") do io; open(src, "r") do io2
            write(io, io2)
        end end
        mv(tmp, dst; force=true)
    catch err
        @error "Something went wrong when copying asset..." src dst exception=(err, catch_backtrace())
    finally
        rm(tmp; force=true)
    end
end

function copy_assets(out)
    # CSS file
    src_files = joinpath.(@__DIR__, ["status-page.css", "status-page.js"])
    # JuliaMono webfonts
    jlmono = joinpath.(artifact"JuliaMono", "juliamono-0.030", "webfonts", [
            "JuliaMono-RegularLatin.woff2",
            "JuliaMono-BoldLatin.woff2",
            "JuliaMono-Regular.woff2", 
            "JuliaMono-Bold.woff2"
        ])
    append!(src_files, jlmono)
    dst = joinpath(out, "assets")
    mkpath(dst)
    for src_file in src_files
        dst_file = joinpath(dst, basename(src_file))
        copy_safe(src_file, dst_file)
    end
end


function generate_html(io, df, group_service_map, toml)
    title = get(toml, "title", "Status page")
    desc = get(toml, "desc", "")
    print(io, """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="description" content="$(desc)">
        <title>$(title)</title>
        <link rel="stylesheet" href="/assets/status-page.css">
        </head>
        <body>
        <div class="container">
        <div class="header">
        <h1 class="title">$(title)</h1>
        <h4 class="description">$(desc)</h4>
        </div>
        """)
    # Groups
    dfg = groupby(df, [:config_group, :config_name])
    for (group_name, services) in group_service_map
        # df_group = df_groups[(cg,)]
        # gname = group_name === nothing ? "" : group_name
        print(io, """
            <div class="service-group">
            <h2>$(something(group_name, ""))</h2>
            """)
        # config_services = [x["name"] for x in toml["services"] if get(x, "group", nothing) == cg]
        # df_services = groupby(df_group, :config_name)
        for service in services
            df_service = get(dfg, (group_name, service["name"]), DataFrame(date=Date[], result=Bool[], server=String[]))
            print_service(io, df_service, service)
        end
        println(io, """</div>""")
    end
    last_update = Dates.format(unix2datetime(time()), dateformat"yyyy-mm-dd\THH:MM:SS\Z")
    print(io, """
        </div>
        <div class="footer">Status page built with <a href="https://github.com/fredrikekre/StatusPage.jl">StatusPage.jl</a>. Last update: <span class="last-update">$(last_update)</span>.</div>
        <script src="/assets/status-page.js"></script>
        </body>
        </html>
        """)
end


const OPERATIONAL_SYMBOL = """<svg version="1.1" viewBox="0 0 512 512"><path pid="0" _fill="currentColor" d="M504 256c0 136.967-111.033 248-248 248S8 392.967 8 256 119.033 8 256 8s248 111.033 248 248zM227.314 387.314l184-184c6.248-6.248 6.248-16.379 0-22.627l-22.627-22.627c-6.248-6.249-16.379-6.249-22.628 0L216 308.118l-70.059-70.059c-6.248-6.248-16.379-6.248-22.628 0l-22.627 22.627c-6.248 6.248-6.248 16.379 0 22.627l104 104c6.249 6.249 16.379 6.249 22.628.001z"></path></svg>"""
const PARTIAL_SYMBOL = """<svg version="1.1" viewBox="0 0 512 512"><path pid="0" _fill="currentColor" d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zM124 296c-6.6 0-12-5.4-12-12v-56c0-6.6 5.4-12 12-12h264c6.6 0 12 5.4 12 12v56c0 6.6-5.4 12-12 12H124z"></path></svg>"""
const MAJOR_SYMBOL = """<svg version="1.1" viewBox="0 0 512 512"><path pid="0" _fill="currentColor" d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm121.6 313.1c4.7 4.7 4.7 12.3 0 17L338 377.6c-4.7 4.7-12.3 4.7-17 0L256 312l-65.1 65.6c-4.7 4.7-12.3 4.7-17 0L134.4 338c-4.7-4.7-4.7-12.3 0-17l65.6-65-65.6-65.1c-4.7-4.7-4.7-12.3 0-17l39.6-39.6c4.7-4.7 12.3-4.7 17 0l65 65.7 65.1-65.6c4.7-4.7 12.3-4.7 17 0l39.6 39.6c4.7 4.7 4.7 12.3 0 17L312 256l65.6 65.1z"></path></svg>"""


function print_service(io::IO, df_service, service)
    service_name = service["name"]
    ## Compute average for last 90 days
    day_avgs = combine(groupby(df_service, :date), :result => (X -> sum(X)/length(X)) => :daily_avg)
    dict = Dict(day_avgs.date .=> day_avgs.daily_avg)
    today = Date(unix2datetime(time()))
    avgs = [get(dict, day, nothing) for day in (today - Day(89)):Day(1):today]
    history = mapreduce(*, avgs) do uptime
        st = uptime === nothing ? "unknown" :
             uptime > 0.9965 ? "operational" :   # <  5 minutes/day
             uptime > 0.993 ? "partial-outage" : # < 10 minutes/day
                            "major-outage"
        return """<div class="service-status-day status-$(st)"></div>\n"""
    end
    ## Compute current
    gdf = groupby(df_service, :server)
    if length(gdf) < length(service["checks"]) # no measurement for some checks
        status_text = "Unknown"
        status_css = "unknown"
        status_sym = PARTIAL_SYMBOL
        last_update = "N/A"
    else
        g_last = Bool[last(g).result for g in gdf]
        current = sum(g_last) / length(service["checks"])
        if current > 0.99
            status_text = "Operational"
            status_css = "operational"
            status_sym = OPERATIONAL_SYMBOL
        elseif current < 0.1
            status_text = "Major outage"
            status_css = "major-outage"
            status_sym = MAJOR_SYMBOL
        else
            status_text = "Partial outage"
            status_css = "partial-outage"
            status_sym = PARTIAL_SYMBOL
        end
        oldest_current_time = minimum(DateTime[last(g).time for g in gdf])
        last_update = Dates.format(oldest_current_time, dateformat"yyyy-mm-dd\THH:MM:SS\Z")
    end
    ## Print it out
    print(io, """
        <div class="service-entry">
        <input id="$(service_name)" type="checkbox" checked="false" style="display: none;">
        <div class="service-entry-header">
        <p>
        <span>$(service_name)</span>
        <label for="$(service_name)">
        <span class="status-badge status-$(status_css)">$(status_text) $(status_sym)</span>
        </label>
        </p>
        </div>
        <div class="service-entry-details">
        <div class="service-entry-details-days">
        $(history)
        </div>
        <div class="service-entry-details-row">
        <p>
        <span>90 days ago</span>
        <span style="float: right;">Today</span>
        </p>
        </div>
        <div class="service-entry-details-row">
        <p style="text-align: right;">
        Last update: <span class="last-update">$(last_update)</span>
        </p>
        </div>
        <!-- <div class="service-entry-details-row">
        <span style="float: right;">Avg. uptime: 0.999 (1 day), 0.998 (7 days), 0.995 (30 days)</span>
        </div> -->
        </div>
        </div>
        """)
end

end # module
