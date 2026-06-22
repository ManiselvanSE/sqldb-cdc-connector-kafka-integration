-- ============================================
-- Check CDC Read Activity
-- Run this on BOTH primary and secondary to compare
-- ============================================

-- Check 1: Recent queries against CDC tables
SELECT TOP 10
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    t.text AS query_text,
    r.start_time,
    r.status,
    r.cpu_time,
    r.reads
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.database_id = DB_ID('primdb')
    AND s.is_user_process = 1
    AND (
        t.text LIKE '%cdc.%' OR
        t.text LIKE '%fn_cdc%' OR
        t.text LIKE '%change_tracking%' OR
        s.program_name LIKE '%JDBC%'
    )
ORDER BY r.start_time DESC;
GO

-- Check 2: Count of sessions reading CDC
SELECT
    'CDC Sessions' AS metric,
    COUNT(*) AS count
FROM sys.dm_exec_sessions s
WHERE s.database_id = DB_ID('primdb')
    AND s.is_user_process = 1
    AND s.login_name = 'sqladmin';
GO

-- Check 3: Last queries executed (includes completed queries)
SELECT TOP 5
    t.text AS query_text,
    s.last_request_start_time,
    s.login_name,
    s.program_name,
    s.host_name
FROM sys.dm_exec_connections c
JOIN sys.dm_exec_sessions s ON c.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
WHERE s.database_id = DB_ID('primdb')
    AND s.login_name = 'sqladmin'
ORDER BY s.last_request_start_time DESC;
GO

PRINT 'If you see CDC-related queries, this server is being actively read by Debezium!';
GO
