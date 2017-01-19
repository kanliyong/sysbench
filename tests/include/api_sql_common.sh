########################################################################
# Common code for SQL API tests
#
# Expects the following variables and callback functions to be defined by the
# caller:
#
#   DB_DRIVER_ARGS -- extra driver-specific arguments to pass to sysbench
#
########################################################################

set -eu

SB_ARGS="--verbosity=1 --test=$CRAMTMP/api_sql.lua --max-requests=1 --num-threads=1 $DB_DRIVER_ARGS"
cat >$CRAMTMP/api_sql.lua <<EOF
function thread_init()
  drv = sysbench.sql.driver()
  con = drv:connect()
end

function event()
  local e, m

  print("drv:name() = " .. drv:name())
  print("SQL types:")
  for k,v in pairs(sysbench.sql.type) do print(k .. " = " .. v) end
  print('--')

  print("SQL error codes:")
  for k,v in pairs(sysbench.sql.error) do print(k .. " = " .. v) end
  print('--')

  e, m = pcall(sysbench.sql.driver, "non-existing")
  print(m)

  con:query("DROP TABLE IF EXISTS t")
  con:query("CREATE TABLE t(a INT)")
  con:bulk_insert_init("INSERT INTO t VALUES")
  for i = 1,100 do
    con:bulk_insert_next(string.format("(%d)", i))
  end
  con:bulk_insert_done()
  print(con:query_row("SELECT COUNT(DISTINCT a) FROM t"))
  print('--')
  con:query("DROP TABLE IF EXISTS t2")
  con:query("CREATE TABLE t2(a INT, b VARCHAR(120), c FLOAT)")
  con:query("INSERT INTO t2 VALUES (1, 'foo', 0.4)")
  con:query("INSERT INTO t2 VALUES (NULL, 'bar', 0.2)")
  con:query("INSERT INTO t2 VALUES (2, NULL, 0.3)")
  con:query("INSERT INTO t2 VALUES (NULL, NULL, 0.1)")

  print('--')
  local rs = con:query("SELECT * FROM t2 ORDER BY a")
  for i = 1, rs.nrows do
     print(string.format("%s %s %s", unpack(rs:fetch_row(), 1, rs.nfields)))
  end
  print('--')

  print(string.format("%s %s", con:query_row("SELECT b, a FROM t2 ORDER BY b")))
  print('--')
  con:query("DROP TABLE t2")
  con:query("ALTER TABLE t ADD COLUMN b CHAR(10)")

  local stmt = con:prepare("UPDATE t SET a = a + ?, b = ?")
  local a = stmt:bind_create(sysbench.sql.type.INT)
  local b = stmt:bind_create(sysbench.sql.type.CHAR, 10)

  print(a)
  print(b)

  e, m = pcall(stmt.bind_create, stmt, sysbench.sql.type.DATE)
  print(m)

  print(stmt:bind_param())

  stmt:bind_param(a, b)
  a:set(100)
  rs1 = stmt:execute()
  print(rs1)
  a:set(200)
  b:set("01234567890")
  rs2 = stmt:execute()
  row = rs2:fetch_row()
  print(rs2)
  rs2:free()

  e, m = pcall(rs2.free, rs)
  print(m)

  e, m = pcall(rs1.free, rs)
  print(m)

  stmt:close()

  print('--')
  con:disconnect()
  e, m = pcall(con.query, con, "SELECT 1")
  print(m)

  con:disconnect()

  print('--')
  con = drv:connect()
  rs = con:query("SELECT MIN(a), MAX(a), MIN(b), MAX(b) FROM t")
  print(rs.nfields)
  for i = 1, rs.nrows do
     print(string.format("%s %s %s %s", unpack(rs:fetch_row(), 1, rs.nfields)))
  end
  con:query("DROP TABLE t")
  print('--')
end
EOF


# Failed connection handling
sysbench $SB_ARGS run

SB_ARGS="--verbosity=1 --test=$CRAMTMP/api_sql.lua --max-requests=1 --num-threads=1 $DB_DRIVER_ARGS"
cat >$CRAMTMP/api_sql.lua <<EOF
function event()
  local drv = sysbench.sql.driver()
  local e,m = pcall(drv.connect, drv)
  print(m)
end
EOF

sysbench $SB_ARGS --mysql-host="non-existing" --pgsql-host="non-existing" run

########################################################################
# Multiple connections test
########################################################################
cat >$CRAMTMP/api_sql.lua <<EOF
function thread_init()
  drv = sysbench.sql.driver()
  con = {}
  for i=1,10 do
    con[i] = drv:connect()
  end
end

function event()
  con[1]:query("DROP TABLE IF EXISTS t")
  con[2]:query("CREATE TABLE t(a INT)")
  for i=1,10 do
    con[i]:query("INSERT INTO t VALUES (" .. i .. ")")
  end
  rs = con[1]:query("SELECT * FROM t")
  for i = 1, rs.nrows do
     print(string.format("%s", unpack(rs:fetch_row(), 1, rs.nfields)))
  end
  con[1]:query("DROP TABLE t")
end
EOF

sysbench $SB_ARGS run
