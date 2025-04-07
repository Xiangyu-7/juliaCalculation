using MySQL
using DataFrames
# 数据库连接信息
host = "localhost"
username = "root"
password = "123456"
database = "newenergy"

# 建立连接
conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)
# 更新 systemparam 表中的数据
function update_systemparam(conn, max_capacity, min_capacity, capex, opex, lifespan, name)
    query = """
    UPDATE systemparam
    SET max_capacity = ?, min_capacity = ?, capex = ?, opex = ?, lifespan = ?
    WHERE name = ?
    """
    try
        stmt = DBInterface.prepare(conn, query)
        DBInterface.execute(stmt, (max_capacity, min_capacity, capex, opex, lifespan, name))
        println("数据更新成功: name = $name")
    catch e
        println("数据更新失败: $e")
    end
end
function extract_systemparam(conn, name)
    query = "SELECT max_capacity, min_capacity, capex, opex FROM systemparam WHERE name = ?"
    # 执行查询操作
    stmt = DBInterface.prepare(conn, query,)
    result = DBInterface.execute(stmt, (name,))
    # 将查询结果转换为DataFrame
    df = DataFrame(result)
    return df
end
function extract_factor(conn)
    query = "SELECT * FROM factor"
    result = DBInterface.execute(conn, query)
    df = DataFrame(result)
    return df
end
function insert_solutions(conn, solutions)
    query = "insert into solutions (
    wind,
    pv,
    storage,
    electrolyzer,
    tank,
    consumption,
    LCOH,
    Hproduction,
    capex,
    opex
    ) values (?,?,?,?,?,?,?,?,?,?)"
     stmt = DBInterface.prepare(conn, query)
     for row in eachrow(solutions)
         DBInterface.execute(stmt, row)
     end
end
function delete_solutions(conn)
    # 执行删除操作
    query = "DELETE FROM solutions"
    DBInterface.execute(conn, query)
   
end
function update_progress(conn,progress)
    query = "UPDATE progress SET progress = ?"
    stmt = DBInterface.prepare(conn, query)
    DBInterface.execute(stmt, (progress,))
end
function update_steps(conn,  wind,pv, storage, electrolyzer, tank)
    query = "UPDATE steps SET wind = ?,pv = ?,  storage = ?, electrolyzer = ?, tank = ?"
    stmt = DBInterface.prepare(conn, query)
    DBInterface.execute(stmt, (pv, wind, storage, electrolyzer, tank))
end

function extract_steps(conn)
    query = "select * from steps"
    result = DBInterface.execute(conn, query)
    dfstep = DataFrame(result)
    return dfstep
end
function insert_non_dominated_solutions(conn, filtered_df)
    query = "insert into non_dominated_solutions (
    wind,
    pv,
    storage,
    electrolyzer,
    tank,
    consumption,
    LCOH,
    Hproduction,
    capex,
    opex,
    Front
    ) values (?,?,?,?,?,?,?,?,?,?,?)"
     stmt = DBInterface.prepare(conn, query)
     for row in eachrow(filtered_df)
        DBInterface.execute(stmt, row)
     end
end

function delete_non_dominated_solutions(conn)
    # 执行删除操作
    query = "DELETE FROM non_dominated_solutions"
    DBInterface.execute(conn, query)
end
function extract_non_dominated_solutions(conn)
    query = "SELECT * FROM non_dominated_solutions"
    result = DBInterface.execute(conn, query)
    df = DataFrame(result)
    return df
end
function convert_to_frontend_format(df_dominated_solutions)
    return [
        Dict(
            :scheme => "方案$(i)",  # 使用行号i作为ID
            :windPower => row.wind,
            :solarPower => row.pv,
            :storage => row.storage,
            :electrolyzer => row.electrolyzer,
            :hydrogenTanks => row.tank
        ) for (i, row) in enumerate(eachrow(df_dominated_solutions))  # enumerate添加索引
    ]
end

function scheme_details(df_dominated_solutions)
    scheme_dict = Dict{String, Vector{Dict}}()
    for (i, row) in enumerate(eachrow(df_dominated_solutions))        
        scheme_dict["方案$(i)"] = []
        # 添加数据点
        push!(scheme_dict["方案$(i)"],
        Dict("name" => "LCOH(元/kg)", "value" => row.LCOH),
        Dict("name" => "产氢量(万吨)", "value" => row.Hproduction),
        Dict("name" => "风光消纳率(%)", "value" => row.consumption),
        Dict("name" => "总投资成本(元)", "value" => row.capex),
        Dict("name" => "总运维成本(元)", "value" => row.opex)
        )
    end   
    return scheme_dict
end


# df_dominated_solutions = extract_non_dominated_solutions(conn)
# schemes = convert_to_frontend_format(df_dominated_solutions)
# 关闭连接
 DBInterface.close!(conn::MySQL.Connection)