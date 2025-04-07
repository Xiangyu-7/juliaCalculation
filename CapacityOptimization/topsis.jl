using LinearAlgebra
using CSV
using DataFrames

# 读取 CSV 文件
df = CSV.read("solutions.csv", DataFrame; header=true)

# 提取最后 3 列数据
decision_matrix = Matrix{Float64}(df[:, end-2:end])
# # 正向化
max_value = maximum(decision_matrix[:, 2])  # 找到第二列的最大值
decision_matrix[:, 2] .= (max_value .- decision_matrix[:, 2])

function topsis(decision_matrix, weights)
    # 假设 decision_matrix 是你的数据矩阵

    # 找到每一列的最小值和最大值
    min_values = minimum(decision_matrix, dims=1)
    max_values = maximum(decision_matrix, dims=1)
  
    # 应用归一化公式
    normalized_matrix = (decision_matrix .- min_values) ./ (max_values .- min_values) 
    print(normalized_matrix)
    # # 1. 标准化决策矩阵
    # normalized_matrix = decision_matrix ./ sqrt.(sum(decision_matrix .^ 2, dims=1))
    # 2. 计算加权标准化矩阵
    weighted_matrix = normalized_matrix .* weights'
    # 3. 确定正理想解和负理想解
    # 计算正理想解 z^+
    ideal_best = maximum(weighted_matrix, dims=1)
    # 计算负理想解 z^-
    ideal_worst = minimum(weighted_matrix, dims=1)
    # 4. 计算距离
    distance_best = sqrt.(sum((weighted_matrix .- ideal_best) .^ 2, dims=2))
    distance_worst = sqrt.(sum((weighted_matrix .- ideal_worst) .^ 2, dims=2))

    # 5. 计算相对接近度
    closeness = distance_worst ./ (distance_best .+ distance_worst)
    # 6. 排序
    ranked_indices = sortperm(closeness[:], rev=true)
    return ranked_indices, closeness
end
                  

weights = [0.3, 0.4, 0.3]  # 目标函数权重
# 调用 TOPSIS
ranked_indices, closeness = topsis(decision_matrix, weights, )
df[!, :Rank] = ranked_indices
# 输出结果

CSV.write("solutions_with_rank.csv", df)
