-- ============================================
-- Check Active Connections on Secondary
-- Run this on: secondaryserver.database.windows.net
-- Database: primdb
-- ============================================

-- Check 1: Show all active sessions
SELECT
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    database_id,
    DB_NAME(database_id) AS database_name,
    cpu_time,
    reads,
    writes,
    login_time,
    last_request_start_time,
    last_request_end_time
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb')
    AND is_user_process = 1
ORDER BY login_time DESC;
GO

-- Check 2: Show connections from Debezium/Kafka Connect
SELECT
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    cpu_time,
    reads,
    writes,
    login_time,
    DATEDIFF(MINUTE, login_time, GETDATE()) AS minutes_connected
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb')
    AND is_user_process = 1
    AND (
        program_name LIKE '%Debezium%' OR
        program_name LIKE '%Java%' OR
        program_name LIKE '%JDBC%' OR
        login_name = 'sqladmin'
    )
ORDER BY login_time DESC;
GO

-- Check 3: Show current SQL being executed
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status AS request_status,
    r.command,
    t.text AS current_sql,
    r.cpu_time,
    r.reads,
    r.writes,
    r.start_time
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.database_id = DB_ID('primdb')
    AND s.is_user_process = 1
ORDER BY r.start_time DESC;
GO

-- Check 4: Count connections by application
SELECT
    program_name,
    COUNT(*) AS connection_count,
    SUM(cpu_time) AS total_cpu_time,
    SUM(reads) AS total_reads
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb')
    AND is_user_process = 1
GROUP BY program_name
ORDER BY connection_count DESC;
GO

PRINT 'If you see connections from Java/JDBC/sqladmin, Debezium is connected to the secondary!';
GO
