using HTTP
using JSON
using MySQL
include("simulation.jl")
# 非支配排序函数
function non_dominated_sort(decision_matrix)
    n = size(decision_matrix, 1)  # 获取解的数量
    domination_count = zeros(Int, n)  # 每个解被支配的次数

    # 计算每个解的支配关系
    for i in 1:n
        for j in 1:n
            if i != j
                # 解 i 支配解 j
                if all(decision_matrix[i, :] .>= decision_matrix[j, :]) && any(decision_matrix[i, :] .> decision_matrix[j, :])
                    # push!(dominated_solutions[i], j)
                    domination_count[j] += 1
                # # 解 j 支配解 i
                # elseif all(decision_matrix[j, :] .>= decision_matrix[i, :]) && any(decision_matrix[j, :] .> decision_matrix[i, :])
                #     domination_count[i] += 1
                end
            end
        end
    end
    return domination_count
end
# 处理 GET POST 请求的函数
function extractparam(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)   
    # 设置 CORS 头
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "POST, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        # 处理 OPTIONS 预检请求
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end

        # 解析 JSON 数据
        data = JSON.parse(String(req.body))
        body = data["numValues"]
        # 定义设备名称列表
        devices = ["pv", "wind", "storage", "electrolyzer", "tank"]

        # 循环调用 update_systemparam
        for name in devices
            data = body[name]
            update_systemparam(
                conn,
                data["maxCapacity"],
                data["minCapacity"],
                data["investmentCost"],
                data["maintenanceCost"],
                data["lifespan"],
                name
            )
        end
        # 返回成功响应
        return HTTP.Response(200, headers, body=JSON.json(Dict("message" => "Data updated successfully")))
    catch e
        # 捕获并返回错误信息
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error: $e")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end

function start_enumerate(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
     # 重置停止标志
     global should_stop[] = false
    # 读取系统参数
    wind_data = extract_systemparam(conn, "wind")
    pv_data = extract_systemparam(conn, "pv")
    storage_data = extract_systemparam(conn, "storage")
    electrolyzer_data = extract_systemparam(conn, "electrolyzer")
    tank_data = extract_systemparam(conn, "tank")
    lower_bounds = [wind_data.min_capacity[1], pv_data.min_capacity[1], storage_data.min_capacity[1], electrolyzer_data.min_capacity[1], tank_data.min_capacity[1]]
    upper_bounds = [wind_data.max_capacity[1], pv_data.max_capacity[1], storage_data.max_capacity[1], electrolyzer_data.max_capacity[1], tank_data.max_capacity[1]]
    dfstep = extract_steps(conn)
    step_sizes = [dfstep.wind[1],dfstep.pv[1],dfstep.storage[1],dfstep.electrolyzer[1],dfstep.tank[1]] 

    # 设置 CORS 头
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        # 处理 OPTIONS 预检请求
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end

        # 用于存储所有的解（包含变量取值以及对应的目标函数值）
        #solutions = Vector{Any}(undef, 0)
        solutions = DataFrame(
            x1 = Float64[],
            x2 = Float64[],
            x3 = Float64[],
            x4 = Float64[],
            x5 = Float64[],
            obj1 = Float64[],
            obj2 = Float64[],
            obj3 = Float64[],
            capex = Float64[],
            opex = Float64[],
        )
        ranges = [lower_bounds[i]:step_sizes[i]:upper_bounds[i] for i in 1:5]
        total_iterations = length(Iterators.product(ranges...))

        let current_iteration = 0
        # 生成所有可能的组合# 迭代器，枚举变量空间并计算对应的目标函数值
            for x in Iterators.product(ranges...)
                if should_stop[]
                    @info "计算已手动终止"
                    return HTTP.Response(200, headers, body=JSON.json(Dict("start_enumerate" => "stopped")))
                end
                current_iteration =  current_iteration + 1
                # 调用simulation函数获取目标函数值
                objective_values = simulation(x)
                # 将当前解（变量取值和目标函数值）添加到结果数组中
                push!(solutions, (
                    x[1], x[2], x[3], x[4], x[5],
                    objective_values[1][1],
                    objective_values[1][2],
                    objective_values[1][3],
                    objective_values[2],
                    objective_values[3],
                    ))
                progress = round(current_iteration / total_iterations * 100)
                println("计算进度：$progress %")
                update_progress(conn, progress)
            end
        end
        delete_solutions(conn)
        insert_solutions(conn, solutions)
        # 提取解集最后 3 列数据
        decision_matrix = hcat(solutions.obj1, solutions.obj2, solutions.obj3)
        # # 正向化
        max_value = maximum(decision_matrix[:, 2])  # 找到第二列的最大值
        decision_matrix[:, 2] .= (max_value .- decision_matrix[:, 2])
        # 执行非支配排序
        domination_count = non_dominated_sort(decision_matrix)
        solutions[!, :Front] = domination_count
        filtered_df = solutions[solutions[!, :Front] .== 0, :]  # 筛选出非支配解
        delete_non_dominated_solutions(conn)
        insert_non_dominated_solutions(conn, filtered_df)
        println("true")
        # 返回成功响应
         return HTTP.Response(200, headers, body=JSON.json(Dict("start_enumerate" => "successful")))
    catch e
        # 捕获并返回错误信息
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error: $e")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end

const should_stop = Ref{Bool}(false)

    """
        stop_computation()

    设置停止计算标志，用于终止正在进行的枚举计算。
    """
function stop_computation()
    should_stop[] = true
    @info "计算停止请求已接收"
end
function stop_enumerate(req::HTTP.Request)
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "POST, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    
    try
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end
        
        stop_computation()
        return HTTP.Response(200, headers, body=JSON.json(Dict("status" => "stop_signal_sent")))
    catch e
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Failed to send stop signal: $e")))
    end
end

function get_progress(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end
        result = DBInterface.execute(conn, "SELECT progress FROM progress LIMIT 1")
        progress = first(DataFrame(result))["progress"]
        return HTTP.Response(200, headers, body=JSON.json(Dict("progress" => progress)))
    catch e
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error: $e")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end

function get_factor(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end
        df = extract_factor(conn)
        wind_factor = df.wind_factor
        solar_factor = df.solar_factor
        factor = Dict("solar_factor" => solar_factor, "wind_factor" => wind_factor)
        return HTTP.Response(200, headers, body=JSON.json(factor))
    catch e
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error: $e")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end

function setsteps(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)   
    # 设置 CORS 头
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "POST, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        # 处理 OPTIONS 预检请求
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end
        # 解析 JSON 数据
        data = JSON.parse(String(req.body))
        println(data)
        wind = data["steps"]["step1"]
        pv = data["steps"]["step2"]    
        storage = data["steps"]["step3"]
        electrolyzer = data["steps"]["step4"]
        tank = data["steps"]["step5"]
        # 更新步长
        update_steps(conn, pv, wind, storage, electrolyzer, tank)
        # 返回成功响应
        return HTTP.Response(200, headers, body=JSON.json(Dict("message" => "Step size updated successfully")))
    catch    
        # 捕获并返回错误信息
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end

function get_schemes(req::HTTP.Request)
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
        "Content-Type" => "application/json"
    ]
    try
        if req.method == "OPTIONS"
            return HTTP.Response(200, headers)
        end
        df_dominated_solutions = extract_non_dominated_solutions(conn)
        schemes_dict = convert_to_frontend_format(df_dominated_solutions)
        details_dict = scheme_details(df_dominated_solutions)
        response = Dict(
        "schemes" => schemes_dict,
        "details" => details_dict,
        )
        return HTTP.Response(200, headers, body=JSON.json(response))
    catch e
        return HTTP.Response(500, headers, body=JSON.json(Dict("error" => "Internal server error: $e")))
    end
    DBInterface.close!(conn::MySQL.Connection)
end
# 创建路由对象
const ROUTER = HTTP.Router()

# 向路由对象中注册POST请求对应的处理函数，这里路径为/calculate，当收到此路径的POST请求时会调用handle_calculation函数处理
HTTP.register!(ROUTER, "POST", "/calculate", extractparam)
HTTP.register!(ROUTER, "OPTIONS", "/calculate", extractparam)

HTTP.register!(ROUTER, "GET", "/enumerate", start_enumerate)
HTTP.register!(ROUTER, "OPTIONS", "/enumerate", start_enumerate)

HTTP.register!(ROUTER, "GET", "/stop_enumerate", stop_enumerate)
HTTP.register!(ROUTER, "OPTIONS", "/stop_enumerate", stop_enumerate)

HTTP.register!(ROUTER, "GET", "/progress", get_progress)
HTTP.register!(ROUTER, "OPTIONS", "/progress", get_progress)

HTTP.register!(ROUTER, "GET", "/factor", get_factor)
HTTP.register!(ROUTER, "OPTIONS", "/factor", get_factor)

HTTP.register!(ROUTER, "POST", "/setsteps", setsteps)
HTTP.register!(ROUTER, "OPTIONS", "/setsteps", setsteps)

HTTP.register!(ROUTER, "GET", "/schemes", get_schemes)
HTTP.register!(ROUTER, "OPTIONS", "/schemes", get_schemes)
# 启动服务器，监听在本地的127.0.0.1地址的8080端口（0.0.0.0表示监听所有可用网络接口）
server = HTTP.serve(ROUTER, "127.0.0.1", 8080)
println("服务器已启动，监听在 http://localhost:8080")
wait(server.task)