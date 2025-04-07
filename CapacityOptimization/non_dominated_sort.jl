# using CSV
# using DataFrames

# # 读取 CSV 文件
# df = CSV.read("solutions.csv", DataFrame; header=true)

# # 提取最后 3 列数据
# decision_matrix = Matrix{Float64}(df[:, end-2:end])
# # # 正向化
# max_value = maximum(decision_matrix[:, 2])  # 找到第二列的最大值
# decision_matrix[:, 2] .= (max_value .- decision_matrix[:, 2])
# # 非支配排序函数
# function non_dominated_sort(decision_matrix)
#     n = size(decision_matrix, 1)  # 获取解的数量
#     global domination_count = zeros(Int, n)  # 每个解被支配的次数

#     # 计算每个解的支配关系
#     for i in 1:n
#         for j in 1:n
#             if i != j
#                 # 解 i 支配解 j
#                 if all(decision_matrix[i, :] .>= decision_matrix[j, :]) && any(decision_matrix[i, :] .> decision_matrix[j, :])
#                     # push!(dominated_solutions[i], j)
#                     domination_count[j] += 1
#                 # # 解 j 支配解 i
#                 # elseif all(decision_matrix[j, :] .>= decision_matrix[i, :]) && any(decision_matrix[j, :] .> decision_matrix[i, :])
#                 #     domination_count[i] += 1
#                 end
#             end
#         end
#     end
#     return domination_count
# end

# # 执行非支配排序
# fronts = non_dominated_sort(decision_matrix)

# df[!, :Front] = domination_count
# filtered_df = df[df[!, :Front] .== 0, :]  # 筛选出非支配解
# # 输出到新的 CSV 文件
# CSV.write("solutions_with_fronts.csv", filtered_df)
