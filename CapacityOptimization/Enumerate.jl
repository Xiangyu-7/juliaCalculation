
# 定义变量的上下限以及步长（这里以示例数据表示，需替换为json文件中读取的实际数据）
lower_bounds = [70, 0,0, 55, 0]  # 变量x1, x2, x3, x4, x5的下限，分别对应
upper_bounds = [130, 0, 50, 130, 10]  # 变量的上限
step_sizes = [10,5,10,15,10]  # 每个变量的步长

# 用于存储所有的解（包含变量取值以及对应的目标函数值）
solutions = Vector{Any}(undef, 0)
ranges = [lower_bounds[i]:step_sizes[i]:upper_bounds[i] for i in 1:5]
global should_stop[] = false
total_iterations = length(Iterators.product(ranges...))
let current_iteration = 0
# 生成所有可能的组合# 迭代器，枚举变量空间并计算对应的目标函数值
    for x in Iterators.product(ranges...)
        if should_stop[]
            @info "计算已手动终止"
            return HTTP.Response(200, headers, body=JSON.json(Dict("enumerate" => "stopped")))
        end
        current_iteration =  current_iteration + 1
        # 调用simulation函数获取目标函数值
        objective_values = x
        # 将当前解（变量取值和目标函数值）添加到结果数组中
        push!(solutions, (x[1], x[2], x[3], x[4], x[5], objective_values))
        println("已完成迭代：$current_iteration / $total_iterations")
    end
end



