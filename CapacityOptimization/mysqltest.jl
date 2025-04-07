using MySQL

# 数据库连接信息
host = "localhost"
username = "root"
password = "123456"
database = "newenergy"

# 建立连接
conn = DBInterface.connect(MySQL.Connection,host, username, password, db=database)

# 创建表
query = """
CREATE TABLE IF NOT EXISTS factor (
    wind_factor FLOAT,
    solar_factor FLOAT
);
"""
DBInterface.execute(conn, query)

# query = "DELETE FROM factor"
#         # 执行删除操作
# DBInterface.execute(conn, query)
# # 插入数据
# query = "INSERT INTO factor (wind_factor, solar_factor) VALUES (?, ?)"
# stmt = DBInterface.prepare(conn, query) # 预编译语句（prepared statement） 
# for row in eachrow(df)
#     DBInterface.execute(stmt, row)
# end
# query = "INSERT INTO students (id,name, age) VALUES ('1', 'Alice', 20), ('2', 'Bob', 21), ('3', 'Charlie', 22)"
# DBInterface.execute(conn, query)
# # 查询数据
# select_query = "SELECT * FROM students"
# result = DBInterface.execute(conn, select_query)
# for row in result
#     println("ID: $(row.id), Name: $(row.name), Age: $(row.age)")
# end

# # 更新数据
# update_query = "UPDATE students SET age = 21 WHERE name = 'Alice'"
# DBInterface.execute(conn, update_query)

# # 删除数据
# delete_query = "DELETE FROM students WHERE name = 'Alice'"
# DBInterface.execute(conn, delete_query)

# 关闭连接
DBInterface.close!(conn::MySQL.Connection)
