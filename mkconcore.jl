using LightXML
using Logging
using Printf

# --- Configuration & Constants ---
const MKCONCORE_VER = "26-02-19"
const CONCOREPATH = "."
const JULIAEXE = "julia"
const PYTHONEXE = "python3"
const PYTHONWIN = "python"
const CPPEXE = "g++"
const VEXE = "iverilog"

# --- XML Recursive Finder ---
function get_all_tags(root_elem, tagname)
    results = []
    for c in child_elements(root_elem)
        n = name(c)
        if n == tagname || endswith(n, ":" * tagname) || endswith(n, tagname)
            push!(results, c)
        end
        append!(results, get_all_tags(c, tagname))
    end
    return results
end

# --- Main Execution Function ---
function main()
    # --- Argument Parsing ---
    if length(ARGS) < 3
        println("usage: julia mkconcore.jl file.graphml sourcedir outdir [type]")
        println(" type must be posix (macos or ubuntu), windows, or docker")
        exit(1)
    end

    graphml_file = ARGS[1]
    sourcedir = ARGS[2]
    outdir = ARGS[3]
    concore_type = length(ARGS) >= 4 ? ARGS[4] : "docker"

    if !isdir(sourcedir)
        println("$sourcedir does not exist")
        exit(1)
    end

    if ispath(outdir)
        println("$outdir already exists. Remove or rename it first.")
        exit(1)
    end

    # ==========================================
    # 1. PARSE GRAPHML FIRST
    # ==========================================
    xdoc = parse_file(graphml_file)
    xroot = root(xdoc)

    nodes_dict = Dict{String, String}()
    edges_dict = Dict{String, Tuple{String, Vector{String}}}()

    # Parse Nodes
    for node in get_all_tags(xroot, "node")
        node_id = attribute(node, "id")
        for label in get_all_tags(node, "NodeLabel")
            label_text = strip(content(label))
            nodes_dict[node_id] = replace(label_text, r"(\s+|\n)" => " ")
        end
    end

    # Parse Edges
    for edge in get_all_tags(xroot, "edge")
        source_id = attribute(edge, "source")
        target_id = attribute(edge, "target")
        for label in get_all_tags(edge, "EdgeLabel")
            edge_label = strip(content(label))
            source_node = get(nodes_dict, source_id, "")
            target_node = get(nodes_dict, target_id, "")
            
            if source_node != "" && target_node != ""
                if haskey(edges_dict, edge_label)
                    push!(edges_dict[edge_label][2], target_node)
                else
                    edges_dict[edge_label] = (source_node, [target_node])
                end
            end
        end
    end

    if isempty(nodes_dict)
        println("Error: No nodes found in $graphml_file. XML parsing failed.")
        exit(1)
    end

    # ==========================================
    # 2. CREATE DIRECTORIES AND FILES
    # ==========================================
    mkpath(outdir)
    mkpath(joinpath(outdir, "src"))

    is_windows = (concore_type == "windows")
    ext = is_windows ? ".bat" : ""

    fbuild = open(joinpath(outdir, "build$ext"), "w")
    frun = open(joinpath(outdir, "run$ext"), "w")
    fdebug = open(joinpath(outdir, "debug$ext"), "w")
    fstop = open(joinpath(outdir, "stop$ext"), "w")
    fclear = open(joinpath(outdir, "clear$ext"), "w")
    fmaxtime = open(joinpath(outdir, "maxtime$ext"), "w")
    funlock = open(joinpath(outdir, "unlock$ext"), "w")

    # --- Port Map Logic ---
    num_nodes = length(nodes_dict)
    
    # Safely create the mapping without global scope issues
    nodes_num = Dict{String, Int}()
    for (idx, node_val) in enumerate(values(nodes_dict))
        nodes_num[node_val] = idx
    end

    indir = [String[] for _ in 1:num_nodes]
    volsro = ["" for _ in 1:num_nodes]

    for (edges, (src_node, targets)) in edges_dict
        for dest in targets
            dest_idx = nodes_num[dest]
            incount = count(x -> x == "-v", split(volsro[dest_idx]))
            volIndirPair = edges * ":/in" * string(incount + 1)
            push!(indir[dest_idx], volIndirPair)
            volsro[dest_idx] *= " -v " * volIndirPair * ":ro"
        end
    end

    outcount = zeros(Int, num_nodes)
    oportmap_dict = [Dict{String, Int}() for _ in 1:num_nodes]

    for (edges, (src_node, targets)) in edges_dict
        src_idx = nodes_num[src_node]
        outcount[src_idx] += 1
        oportmap_dict[src_idx][edges] = outcount[src_idx]
    end

    # Copy Source Files and Generate .iport / .oport in /src
    for (node_id, node_val) in nodes_dict
        container, source = split(node_val, ':')
        src_idx = nodes_num[node_val]
        
        if contains(source, ".")
            dockername, langext = splitext(source)
            dockername = String(dockername)
            
            # Copy user source code to src
            cp(joinpath(sourcedir, String(source)), joinpath(outdir, "src", String(source)), force=true)
            
            # Copy Concore library to src
            lib_to_copy = ""
            if langext == ".py"
                lib_to_copy = (concore_type == "docker") ? "concoredocker.py" : "concore.py"
                if isfile(joinpath(CONCOREPATH, lib_to_copy))
                    cp(joinpath(CONCOREPATH, lib_to_copy), joinpath(outdir, "src", "concore.py"), force=true)
                end
            elseif langext == ".jl"
                lib_to_copy = (concore_type == "docker") ? "concoredocker.jl" : "concore.jl"
                if isfile(joinpath(CONCOREPATH, lib_to_copy))
                    cp(joinpath(CONCOREPATH, lib_to_copy), joinpath(outdir, "src", "concore.jl"), force=true)
                end
            end
            
            # Generate iport
            iportmap_dict = Dict{String, Int}()
            for pair in indir[src_idx]
                volname, portnum_str = split(pair, ":/in")
                iportmap_dict[volname] = parse(Int, portnum_str)
            end
            open(joinpath(outdir, "src", "$dockername.iport"), "w") do fport
                dict_str = "{" * join(["'$(k)': $(v)" for (k,v) in iportmap_dict], ", ") * "}"
                write(fport, dict_str)
            end
            
            # Generate oport
            open(joinpath(outdir, "src", "$dockername.oport"), "w") do fport
                dict_str = "{" * join(["'$(k)': $(v)" for (k,v) in oportmap_dict[src_idx]], ", ") * "}"
                write(fport, dict_str)
            end
        end
    end

    # --- Build Script Generation ---
    if is_windows
        for (node_id, node_val) in nodes_dict
            container, source = split(node_val, ':')
            if contains(source, ".")
                dockername, langext = splitext(source)
                write(fbuild, "mkdir $container\n")
                write(fbuild, "copy .\\src\\$source .\\$container\\$source\n")
                if langext == ".jl"
                    write(fbuild, "copy .\\src\\concore.jl .\\$container\\concore.jl\n")
                elseif langext == ".py"
                    write(fbuild, "copy .\\src\\concore.py .\\$container\\concore.py\n")
                end
                write(fbuild, "copy .\\src\\$dockername.iport .\\$container\\concore.iport\n")
                write(fbuild, "copy .\\src\\$dockername.oport .\\$container\\concore.oport\n")
            end
        end
        
        for edges in keys(edges_dict)
            write(fbuild, "mkdir $edges\n")
        end
        
        outcount_link = zeros(Int, num_nodes)
        for (edges, (src_node, targets)) in edges_dict
            src_idx = nodes_num[src_node]
            outcount_link[src_idx] += 1
            container, _ = split(src_node, ':')
            write(fbuild, "cd $container\n")
            write(fbuild, "mklink /J out$(outcount_link[src_idx]) ..\\$edges\n")
            write(fbuild, "cd ..\n")
        end
        
        for (node_id, node_val) in nodes_dict
            container, _ = split(node_val, ':')
            dest_idx = nodes_num[node_val]
            if !isempty(indir[dest_idx])
                write(fbuild, "cd $container\n")
                for pair in indir[dest_idx]
                    volname, dirname = split(pair, ":/")
                    write(fbuild, "mklink /J $dirname ..\\$volname\n")
                end
                write(fbuild, "cd ..\n")
            end
        end
    else
        for (node_id, node_val) in nodes_dict
            container, source = split(node_val, ':')
            if contains(source, ".")
                dockername, langext = splitext(source)
                write(fbuild, "mkdir -p $container\n")
                write(fbuild, "cp ./src/$source ./$container/$source\n")
                if langext == ".jl"
                    write(fbuild, "cp ./src/concore.jl ./$container/concore.jl\n")
                elseif langext == ".py"
                    write(fbuild, "cp ./src/concore.py ./$container/concore.py\n")
                end
                write(fbuild, "cp ./src/$dockername.iport ./$container/concore.iport\n")
                write(fbuild, "cp ./src/$dockername.oport ./$container/concore.oport\n")
            end
        end
        
        for edges in keys(edges_dict)
            write(fbuild, "mkdir -p $edges\n")
        end
        
        outcount_link = zeros(Int, num_nodes)
        for (edges, (src_node, targets)) in edges_dict
            src_idx = nodes_num[src_node]
            outcount_link[src_idx] += 1
            container, _ = split(src_node, ':')
            write(fbuild, "cd $container\n")
            write(fbuild, "ln -s ../$edges out$(outcount_link[src_idx])\n")
            write(fbuild, "cd ..\n")
        end
        
        for (node_id, node_val) in nodes_dict
            container, _ = split(node_val, ':')
            dest_idx = nodes_num[node_val]
            if !isempty(indir[dest_idx])
                write(fbuild, "cd $container\n")
                for pair in indir[dest_idx]
                    volname, dirname = split(pair, ":/")
                    write(fbuild, "ln -s ../$volname $dirname\n")
                end
                write(fbuild, "cd ..\n")
            end
        end
    end

    # --- Run, Stop, Clear, Debug, Maxtime, Unlock Script Generation ---
    if is_windows
        for (node_id, node_val) in nodes_dict
            container, source = split(node_val, ':')
            if contains(source, ".")
                dockername, langext = splitext(source)
                if langext == ".jl"
                    write(frun, "start /B /D $container $JULIAEXE $source >$container\\concoreout.txt\n")
                    write(fdebug, "start /D $container cmd /K $JULIAEXE $source\n")
                elseif langext == ".py"
                    write(frun, "start /B /D $container $PYTHONWIN $source >$container\\concoreout.txt\n")
                    write(fdebug, "start /D $container cmd /K $PYTHONWIN $source\n")
                end
                write(fstop, "if exist $container\\concorekill.bat cmd /C $container\\concorekill\n")
                write(fstop, "if exist $container\\concorekill.bat del $container\\concorekill.bat\n")
            end
        end
        for edges in keys(edges_dict)
            write(fclear, "del /Q $edges\\*\n")
            write(fmaxtime, "echo %1 > $edges\\concore.maxtime\n")
            write(funlock, "copy %HOMEDRIVE%%HOMEPATH%\\concore.apikey $edges\\concore.apikey\n")
        end
    else
        for (node_id, node_val) in nodes_dict
            container, source = split(node_val, ':')
            if contains(source, ".")
                dockername, langext = splitext(source)
                if langext == ".jl"
                    write(frun, "(cd $container; $JULIAEXE $source >concoreout.txt & echo \$! >concorepid)&\n")
                    write(fdebug, "xterm -e bash -c \"cd $container; $JULIAEXE $source; bash\" &\n")
                elseif langext == ".py"
                    write(frun, "(cd $container; $PYTHONEXE $source >concoreout.txt & echo \$! >concorepid)&\n")
                    write(fdebug, "xterm -e bash -c \"cd $container; $PYTHONEXE $source; bash\" &\n")
                end
                write(fstop, "kill -9 `cat $container/concorepid` 2>/dev/null\n")
                write(fstop, "rm -f $container/concorepid\n")
            end
        end
        for edges in keys(edges_dict)
            write(fclear, "rm -f $edges/*\n")
            write(fmaxtime, "echo \"\$1\" > $edges/concore.maxtime\n")
            write(funlock, "cp ~/concore.apikey $edges/concore.apikey\n")
        end
    end

    close(fbuild)
    close(frun)
    close(fdebug)
    close(fstop)
    close(fclear)
    close(fmaxtime)
    close(funlock)

    if !is_windows
        for f in ["build", "run", "stop", "clear", "maxtime", "unlock"]
            chmod(joinpath(outdir, f), 0o755)
        end
    end

    println("Successfully generated study in $outdir")
end

# Execute main
main()