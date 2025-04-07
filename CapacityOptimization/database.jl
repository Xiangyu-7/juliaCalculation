using MySQL
# 数据库连接信息
host = "localhost"
username = "root"
password = "123456"
database = "newenergy"

# 建立连接
conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)

# 更新systemparam表中的数据
function update_systemparam(conn, max_capacity, min_capacity, capex, opex,lifespan,name)

    query = """
    UPDATE systemparam
    SET max_capacity = ?, min_capacity = ?, capex = ?, opex = ?, lifespan = ?
    WHERE name = ?
    """
    stmt = DBInterface.prepare(conn, query,)
    DBInterface.execute(stmt,(max_capacity, min_capacity, capex, opex, lifespan, name))
end
# # 调用函数
# update_systemparam(conn, 100, 50, 2800,62.2,20,"pv")

# # 关闭连接
# DBInterface.close!(conn::MySQL.Connection)