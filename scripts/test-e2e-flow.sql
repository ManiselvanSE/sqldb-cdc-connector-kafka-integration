-- ============================================
-- End-to-End Flow Test
-- Run this on: primaryserver.database.windows.net (PRIMARY!)
-- Database: primdb
-- ============================================

-- Insert a unique test record on PRIMARY
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('TestFlow', 'E2E', 'e2e-test@verify.com', '+1-555-TEST');
GO

-- Check it was inserted on primary
SELECT
    customer_id,
    first_name,
    last_name,
    email,
    created_at
FROM dbo.Customers
WHERE email = 'e2e-test@verify.com';
GO

PRINT '========================================';
PRINT 'Test record inserted on PRIMARY!';
PRINT '';
PRINT 'Now wait 60 seconds for:';
PRINT '1. Geo-replication (PRIMARY → SECONDARY): ~30 sec';
PRINT '2. Debezium capture (SECONDARY → Kafka): ~10 sec';
PRINT '';
PRINT 'Then check Kafka topic for this message!';
PRINT '========================================';
GO
