# include("parameters.jl")
 include("moduleDB.jl")
using SymPy
# x =[x1,x2,x3,x4,x5,]
#离网
function simulation(x)

    windpower_capacity = x[1]
    pv_capacity = x[2]
    storage_capacity = x[3]
    electrolyzer_capacity = x[4]
    tank_number = x[5]
    # 调用数据库参数
    conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
    factor = extract_factor(conn)
    wind_factor = factor.wind_factor
    solar_factor = factor.solar_factor
    wind_data = extract_systemparam(conn, "wind")
    pv_data = extract_systemparam(conn, "pv")
    storage_data = extract_systemparam(conn, "storage")
    electrolyzer_data = extract_systemparam(conn, "electrolyzer")
    tank_data = extract_systemparam(conn, "tank")
    DBInterface.close!(conn::MySQL.Connection)
    hydro_availability = 0.42
    hydro_m3_load = 5
    storage_power = 10 #（kw·h）储能充放电限制
    Auxiliary_load_factor = 1 #辅助负荷系数
    charging_efficiency = 0.9 #充电效率
    discharge_efficiency = 0.9 #放电效率
    # 计算
    photovoltaic_ac = solar_factor .* pv_capacity
    windpower_ac = wind_factor .* windpower_capacity
    new_energy = windpower_ac .+ photovoltaic_ac

    system_m3_load = Auxiliary_load_factor*hydro_m3_load; # 制氢系统（含辅机）每标方氢用电量（kWh）
    system_load = electrolyzer_capacity*Auxiliary_load_factor; # 制氢系统（含辅机）额定负荷(MW)
    Auxiliary_load = system_load-electrolyzer_capacity; # 辅机负荷（MW）
    # 低于30#负荷出力 # 高于额定制氢出力
    new_energy_low_electrolyzer=zeros(8760,1)
    new_energy_high_electrolyzer=zeros(8760,1)
  
    for i = 1:8760
        if new_energy[i] < system_load * 0.3
            new_energy_low_electrolyzer[i] = new_energy[i]
        else
            new_energy_low_electrolyzer[i] = 0
        end

        if new_energy[i] > system_load 
            new_energy_high_electrolyzer[i] = new_energy[i] - system_load
        else
            new_energy_high_electrolyzer[i] = 0
        end
    
    end

    # 化工逐时用氢电负荷
    load_H2_MW = hydro_availability * 10000 * system_m3_load / 1000
    
# 储能系统
    global table_storage_system = zeros(8760, 13) # 初始化8760小时，13列的储能系统状态矩阵
    # 设置第一行的储能系统状态
    table_storage_system[1, 1] = storage_capacity * 0.2
    if new_energy[1,1] < system_load * 0.3 # 低于30%负荷输出
        if new_energy_low_electrolyzer[1,1] + (table_storage_system[1, 1]-storage_capacity * 0.2) >= system_load * 0.3 
            table_storage_system[1, 2] = 0; # 大于30%负荷输出储能不充电
        else
            table_storage_system[1, 2] = new_energy_low_electrolyzer[1,1];
        end
    else
        if new_energy[1,1] > system_load
            table_storage_system[1, 2] = new_energy_high_electrolyzer[1,1];
        else
            table_storage_system[1, 2] = 0;
        end
    end

    # 计算充电情况
        if table_storage_system[1,2] > storage_power
            if table_storage_system[1,1] + storage_power < storage_capacity
                table_storage_system[1, 3] = storage_power;
            else
                table_storage_system[1, 3] = storage_capacity - table_storage_system[1, 1];
            end
        else
            if table_storage_system[1,1] + table_storage_system[1, 2] >= storage_capacity
                table_storage_system[1, 3] = storage_capacity - table_storage_system[1, 1];
            else
                table_storage_system[1, 3] = table_storage_system[1, 2];
            end
        end



    # 计算充电后的实际储能增加量和损失量

    table_storage_system[1, 4] = table_storage_system[1, 3] * charging_efficiency;
    table_storage_system[1, 5] = table_storage_system[1, 3] - table_storage_system[1, 4];
    table_storage_system[1, 6] = table_storage_system[1, 1] + table_storage_system[1, 4];
    table_storage_system[1, 9] = table_storage_system[1, 8] * discharge_efficiency;

    # 计算放电情况
    if new_energy[1] < system_load
        table_storage_system[1, 7] = -(new_energy[1] - system_load);
    else
        table_storage_system[1, 7] = 0;
    end
    # 计算放电后的实际储能减少量和损失量
    if new_energy[1] + table_storage_system[1, 6]  > system_load * 0.3 # 低于30%负荷输出
        if table_storage_system[1, 3] > 0
            table_storage_system[1, 8] = 0;
        else   
            if table_storage_system[1, 7] > storage_power
                if table_storage_system[1, 6] - storage_power > 0.2*storage_capacity
                    table_storage_system[1, 8] = storage_power
                else
                    table_storage_system[1, 8] = table_storage_system[1, 6] - 0.2*storage_capacity
                end
            else
                if table_storage_system[1, 6] - table_storage_system[1, 7] > 0.2*storage_capacity
                    table_storage_system[1, 8] = table_storage_system[1, 7]
                else
                    table_storage_system[1, 8] = table_storage_system[1, 6] - 0.2*storage_capacity
                end
            end
        end
    else
        table_storage_system[1, 8] = 0
    end

    
    table_storage_system[1, 10] = table_storage_system[1, 8] - table_storage_system[1, 9];
    table_storage_system[1, 11] = table_storage_system[1, 6] - table_storage_system[1, 8];
    table_storage_system[1, 12] = table_storage_system[1, 2] - table_storage_system[1, 3];

    #风光储能总出力
    if new_energy[1] > system_load
        table_storage_system[1, 13] = system_load;
    else
        if new_energy[1] + table_storage_system[1, 1] >= system_load * 0.3
            table_storage_system[1, 13] = new_energy[1] + table_storage_system[1, 9];
        else
            table_storage_system[1, 13] = 0;
        end
    end
    

    for i = 2:8760
        table_storage_system[i, 1] = table_storage_system[i-1, 11] #初态末态平衡
        if storage_capacity > 0
            if new_energy[i,1] < system_load * 0.3 # 低于30%负荷输出
                if new_energy_low_electrolyzer[i,1] + (table_storage_system[i, 1]-storage_capacity * 0.2) >= system_load * 0.3 
                    table_storage_system[i, 2] = 0; # 大于30%负荷输出储能不充电
                else
                    table_storage_system[i, 2] = new_energy_low_electrolyzer[i,1];
                end
            else
                if new_energy[i,1] > system_load
                    table_storage_system[i, 2] = new_energy_high_electrolyzer[i,1];
                else
                    table_storage_system[i, 2] = 0;
                end
            end
        else 
            table_storage_system[i, 2] = 0
        end
        # 计算充电情况
            if table_storage_system[i,2] > storage_power
                if table_storage_system[i,1] + storage_power < storage_capacity
                    table_storage_system[i, 3] = storage_power;
                else
                    table_storage_system[i, 3] = storage_capacity - table_storage_system[i, 1];
                end
            else
                if table_storage_system[i,1] + table_storage_system[i, 2] >= storage_capacity
                    table_storage_system[i, 3] = storage_capacity - table_storage_system[i, 1];
                else
                    table_storage_system[i, 3] = table_storage_system[i, 2];
                end
            end
        # 计算充电后的实际储能增加量和损失量

        table_storage_system[i, 4] = table_storage_system[i, 3] * charging_efficiency;
        table_storage_system[i, 5] = table_storage_system[i, 3] - table_storage_system[i, 4];
        table_storage_system[i, 6] = table_storage_system[i, 1] + table_storage_system[i, 4];
        table_storage_system[i, 9] = table_storage_system[i, 8] * discharge_efficiency;

        # 计算放电情况
        if new_energy[i] < system_load
            table_storage_system[i, 7] = -(new_energy[i] - system_load);
        else
            table_storage_system[i, 7] = 0;
        end
        # 计算放电后的实际储能减少量和损失量
         # 计算放电后的实际储能减少量和损失量
    if new_energy[i] + table_storage_system[i, 6]  > system_load * 0.3 # 低于30%负荷输出
        if table_storage_system[i, 3] > 0
            table_storage_system[i, 8] = 0;
        else   
            if table_storage_system[i, 7] > storage_power
                if table_storage_system[i, 6] - storage_power > 0.2*storage_capacity
                    table_storage_system[i, 8] = storage_power
                else
                    table_storage_system[i, 8] = table_storage_system[i, 6] - 0.2*storage_capacity
                end
            else
                if table_storage_system[i, 6] - table_storage_system[i, 7] > 0.2*storage_capacity
                    table_storage_system[i, 8] = table_storage_system[i, 7]
                else
                    table_storage_system[i, 8] = table_storage_system[i, 6] - 0.2*storage_capacity
                end
            end
        end
    else
        table_storage_system[i, 8] = 0
    end
        table_storage_system[i, 10] = table_storage_system[i, 8] - table_storage_system[i, 9];
        table_storage_system[i, 11] = table_storage_system[i, 6] - table_storage_system[i, 8];
        table_storage_system[i, 12] = table_storage_system[i, 2] - table_storage_system[i, 3];
        #风光储能总出力
        if new_energy[i] > system_load
            table_storage_system[i, 13] = system_load
        else
            if new_energy[i] + table_storage_system[i, 1] >= system_load * 0.3
                table_storage_system[i, 13] = new_energy[i] + table_storage_system[i, 9]
            else
                table_storage_system[i, 13] = 0
            end
        end
            
    end
    direct_hydrogen_supply = zeros(8760,1)
    global table_tank_system = zeros(8760, 7)
    #直供氢
    
    for i = 1:8760
        if table_storage_system[i, 13] >= load_H2_MW
            direct_hydrogen_supply[i] = load_H2_MW
        else
            direct_hydrogen_supply[i] = table_storage_system[i, 13]
        end
    end
    #  储氢罐系统
    #  储氢罐初始氢量
    tank_V = 25666; # 储氢罐容积（m3）
    gas_EFst_MW = tank_V*system_m3_load/1000; # 有效储气容积（MW）
    gas_st = gas_EFst_MW*tank_number; # 储氢规模
    table_tank_system[1, 1] = 0

    #  储氢罐目标供氢量(用氢需求)
    table_tank_system[1, 2] = load_H2_MW - direct_hydrogen_supply[1]

    # 储氢罐实际供氢量(平滑供氢)
    if table_tank_system[1, 1] <= table_tank_system[1, 2]
        table_tank_system[1, 3] = table_tank_system[1, 1]
    else
        table_tank_system[1, 3] = table_tank_system[1, 2]
    end

    #  多余产氢量至储氢罐
    table_tank_system[1, 4] = table_storage_system[1, 13] - direct_hydrogen_supply[1]

    #  实际储氢量
    if table_tank_system[1, 1] + table_tank_system[1, 4] >= gas_st
        table_tank_system[1, 5] = gas_st - table_tank_system[1, 1]
    else
        table_tank_system[1, 5] = table_tank_system[1, 4]
    end

    # 储氢罐末态氢量
    table_tank_system[1, 6] = table_tank_system[1, 1] + table_tank_system[1, 5] - table_tank_system[1, 3]

    #  储氢罐弃电
    table_tank_system[1, 7] = table_tank_system[1, 4] - table_tank_system[1, 5]
    # 循环
   # 循环范围从2到8760，对应处理每个时间步的数据
   
    for i in 2:8760
        # tank_system相关操作

        # tank_initial：将上一个时间步（i - 1）的第6列数据赋值给当前时间步（i）的第1列
        table_tank_system[i, 1] = table_tank_system[i - 1, 6] 

        # tank_target_out：根据load_H2_MW和w_p_s_g_system_20数组当前时间步第4列数据计算当前时间步第2列的值
        table_tank_system[i, 2] = load_H2_MW - direct_hydrogen_supply[i]

        # tank_actual_out：根据当前时间步第1列和第2列数据的大小关系确定第3列的值
        if table_tank_system[i, 1] <= table_tank_system[i, 2]
            table_tank_system[i, 3] = table_tank_system[i, 1]  
        else
            table_tank_system[i, 3] = table_tank_system[i, 2]  
        end

        table_tank_system[i, 4] = table_storage_system[i, 13]  - direct_hydrogen_supply[i]

        # tank_actual_storage：根据当前时间步第1列和第4列数据之和与gas_st的大小关系确定第5列的值
        if table_tank_system[i, 1] + table_tank_system[i, 4] >= gas_st
            table_tank_system[i, 5] = gas_st - table_tank_system[i, 1]  
        else
            table_tank_system[i, 5] = table_tank_system[i, 4]  
        end

        # tank_final_storage：根据当前时间步第1列、第5列和第3列数据计算当前时间步第6列的值
        table_tank_system[i, 6] = table_tank_system[i, 1] + table_tank_system[i, 5] - table_tank_system[i, 3]

        # tank_abandon：根据当前时间步第4列和第5列数据计算当前时间步第7列的值
        table_tank_system[i, 7] = table_tank_system[i, 4] - table_tank_system[i, 5] 
        
        # 系统供氢量
        # 实际制氢出力 新能源消纳
       
    end


    #供氢
    new_energy_consum = zeros(8760,1)
    total_hydrogen_supply = zeros(8760,1)
    for i = 1:8760
        new_energy_consum[i] = table_storage_system[i, 13] - table_tank_system[i, 7]
        total_hydrogen_supply[i] = direct_hydrogen_supply[i] + table_tank_system[i, 3]

    end

    #评价指标
    Total_new_energy = sum(new_energy[:, 1])
    Total_hydrogen_supply = sum(total_hydrogen_supply[:,1])
    Total_H2_Wt_20 = Total_hydrogen_supply / system_m3_load * 1000 / 11.2 / 1000 / 10000
    Total_system_energy_apply = sum(new_energy_consum[:, 1])

    consume_power_rate_20 = Total_system_energy_apply / Total_new_energy * 100;

    n = 20
    r = 0.07
    @syms i H2_price
    # 计算结果
    # 计算npv_A
    # capex = [electrolyzer_capex * electrolyzer_capacity * 1000, wind_capex * windpower_capacity * 1000, storage_capex * storage_capacity * 1000, tank_capex * tank_number]
    # opex = [electrolyzer_opex*electrolyzer_capacity*1000*20, wind_opex*windpower_capacity*1000*20, storage_opex*storage_capacity*1000*20, tank_opex*tank_number*20]
    # npv_A = electrolyzer_capex * electrolyzer_capacity * 1000 + wind_capex * windpower_capacity * 1000 + storage_capex * storage_capacity * 1000 + tank_capex * tank_number
    capex = [wind_data.capex[1]*windpower_capacity*1000, pv_data.capex[1]*pv_capacity*1000, storage_data.capex[1]*storage_capacity*1000, electrolyzer_data.capex[1]*electrolyzer_capacity*1000, tank_data.capex[1]*tank_number]
    opex = [wind_data.opex[1]*windpower_capacity*1000*20, pv_data.opex[1]*pv_capacity*1000*20, storage_data.opex[1]*storage_capacity*1000*20, electrolyzer_data.opex[1]*electrolyzer_capacity*1000*20, tank_data.opex[1]*tank_number*20]
    npv_A = wind_data.capex[1]*windpower_capacity*1000 + pv_data.capex[1]*pv_capacity*1000 + storage_data.capex[1]*storage_capacity*1000 + electrolyzer_data.capex[1]*electrolyzer_capacity*1000 + tank_data.capex[1]*tank_number
    npv_B = sum((electrolyzer_data.opex[1]*electrolyzer_capacity*1000 + wind_data.opex[1]*windpower_capacity*1000 + storage_data.opex[1]*storage_capacity*1000 + tank_data.opex[1]*tank_number + pv_data.opex[1]*pv_capacity*1000  ) / (1 + r) ^ i for i in 1:n)
    # 定义内部收益率和其他参数
  
    # 计算npv_B_20_sym
    #npv_B_20_sym = sum((Total_H2_Wt_20 * 10000 * 1000 * H2_price  - (electrolyzer_opex + wind_opex + storage_opex + tank_opex  )) / (1 + r) ^ i for i in 1:n)
    npv_B_20_sym = sum((Total_H2_Wt_20 * 10000 * 1000 * H2_price  - (electrolyzer_data.opex[1]*electrolyzer_capacity*1000 + wind_data.opex[1]*windpower_capacity*1000 + storage_data.opex[1]*storage_capacity*1000 + tank_data.opex[1]*tank_number + pv_data.opex[1]*pv_capacity*1000  )) / (1 + r) ^ i for i in 1:n)
    # 计算NPV
    NPV = (- npv_A + npv_B_20_sym) / 10^8

    # 求解NPV为零时的H2_price
    solution = solve(NPV, H2_price)

    # 将求解结果转换为数值
    LCOH = solution

    # 计算z1, z2, z3

    z1 = consume_power_rate_20
    z2 = LCOH
    z3 = Total_H2_Wt_20

    # 创建z和reference_values
    z = [z1; z2; z3]
  

    return z,npv_A,npv_B
end


# #检查数据
# x =[71, 0, 16, 58, 9]
# print(simulation(x))
# using CSV
# using DataFrames
# CSV.write("table_storage_system.csv", DataFrame(table_storage_system, :auto), delim=';')
# CSV.write("table_tank_system.csv", DataFrame(table_tank_system, :auto), delim=';')