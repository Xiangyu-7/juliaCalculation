using Random
using Plots
include("simulation.jl")
# 参数设置
const POPULATION_SIZE = 20       # 种群大小
const MAX_GENERATIONS = 10     # 最大迭代次数
const CROSSOVER_RATE = 0.8      # 交叉率
const MUTATION_RATE = 0.1       # 变异率
const ELITISM_COUNT = 2         # 精英保留的个体数
const DIMENSIONS = 5            # 解的维度
const BOUNDS = [(70, 130), (0, 0), (0, 50), (55, 130), (0, 10)]  # 每个维度的取值范围
solutions = Vector{Any}(undef, 0)
# 目标函数：LCOH指标
function lcoh(x)
    return simulation(x)[1][2]
end

# 初始化种群
function initialize_population()
    return [rand_individual() for _ in 1:POPULATION_SIZE]
end

# 随机生成一个个体
function rand_individual()
    return [rand(BOUND_LOW:BOUND_UP) for (BOUND_LOW, BOUND_UP) in BOUNDS]
end

# 选择操作：锦标赛选择
function selection(population, fitness_values)
    selected = []
    for _ in 1:POPULATION_SIZE
        # 随机选择两个个体
        candidates = rand(1:POPULATION_SIZE, 2)
        # 选择适应度更好的个体
        if fitness_values[candidates[1]] < fitness_values[candidates[2]]
            push!(selected, population[candidates[1]])
        else
            push!(selected, population[candidates[2]])
        end
    end
    return selected
end

# 交叉操作：单点交叉
function crossover(parent1, parent2)
    if rand() < CROSSOVER_RATE
        crossover_point = rand(1:DIMENSIONS-1)
        child1 = vcat(parent1[1:crossover_point], parent2[crossover_point+1:end])
        child2 = vcat(parent2[1:crossover_point], parent1[crossover_point+1:end])
        return child1, child2
    end
    return parent1, parent2
end

# 变异操作：随机扰动
function mutate(individual)
    for i in 1:DIMENSIONS
        if rand() < MUTATION_RATE
            individual[i] = rand(BOUNDS[i][1]:BOUNDS[i][2])
        end
    end
    return individual
end

# 遗传算法主函数
function genetic_algorithm()
    population = initialize_population()
    best_fitness_history = Float64[]
    
    for generation in 1:MAX_GENERATIONS
        # 计算适应度
        fitness_values = [lcoh(ind) for ind in population]
        
        # 找出当前最优
        best_idx = argmin(fitness_values)
        current_best = population[best_idx]
        current_best_fitness = fitness_values[best_idx]
        push!(best_fitness_history, current_best_fitness)
        
        # 选择 (改进的选择方式)
        selected = []
        fitness_probs = 1 ./ (fitness_values .+ 1e-6)  # 避免除零
        fitness_probs ./= sum(fitness_probs)
        for _ in 1:POPULATION_SIZE
            push!(selected, population[rand(Categorical(fitness_probs))])
        end
        
        # 交叉和变异 (保留精英)
        new_population = [current_best]  # 保留最优个体
        
        while length(new_population) < POPULATION_SIZE
            parent1, parent2 = rand(selected, 2)
            child1, child2 = crossover(parent1, parent2)
            push!(new_population, mutate(child1))
            if length(new_population) < POPULATION_SIZE
                push!(new_population, mutate(child2))
            end
        end
        
        population = new_population
        println("Generation $generation: Best Fitness = $current_best_fitness")
    end
    
    best_idx = argmin([lcoh(ind) for ind in population])
    return population[best_idx], lcoh(population[best_idx]), best_fitness_history
end

# 运行遗传算法
best_individual, best_fitness = genetic_algorithm()

plot(1:MAX_GENERATIONS, best_fitness_history, 
     xlabel="Generation", 
     ylabel="Best Fitness", 
     title="Genetic Algorithm Convergence",
     label="Best Fitness",
     linewidth=2,
     markershape=:circle)

# 显示图表
display(plot!())
