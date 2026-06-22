-- ============================================
-- Complete CDC Setup - Safe Version
-- Run this on: primaryserver.database.windows.net
-- Database: primdb
-- ============================================

-- Enable CDC on database (safe - won't fail if already enabled)
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'primdb' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
    PRINT 'Step 1: CDC enabled on database';
END
ELSE
BEGIN
    PRINT 'Step 1: CDC already enabled on database (GOOD!)';
END
GO

-- Enable CDC on Customers (safe - checks first)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Customers' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Customers',
        @role_name = NULL,
        @supports_net_changes = 1;
    PRINT 'Step 2: CDC enabled on Customers';
END
ELSE
BEGIN
    PRINT 'Step 2: CDC already enabled on Customers (GOOD!)';
END
GO

-- Enable CDC on Orders (safe - checks first)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Orders' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Orders',
        @role_name = NULL,
        @supports_net_changes = 1;
    PRINT 'Step 3: CDC enabled on Orders';
END
ELSE
BEGIN
    PRINT 'Step 3: CDC already enabled on Orders (GOOD!)';
END
GO

-- Enable CDC on Products (safe - checks first)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Products' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Products',
        @role_name = NULL,
        @supports_net_changes = 1;
    PRINT 'Step 4: CDC enabled on Products';
END
ELSE
BEGIN
    PRINT 'Step 4: CDC already enabled on Products (GOOD!)';
END
GO

-- Insert data (safe - checks if empty)
IF NOT EXISTS (SELECT 1 FROM dbo.Customers)
BEGIN
    INSERT INTO dbo.Customers (first_name, last_name, email, phone)
    VALUES
        ('John', 'Doe', 'john.doe@example.com', '+1-555-0101'),
        ('Jane', 'Smith', 'jane.smith@example.com', '+1-555-0102'),
        ('Robert', 'Johnson', 'robert.j@example.com', '+1-555-0103'),
        ('Emily', 'Williams', 'emily.w@example.com', '+1-555-0104'),
        ('Michael', 'Brown', 'michael.b@example.com', '+1-555-0105');
    PRINT 'Step 5: 5 customers inserted';
END
ELSE
BEGIN
    PRINT 'Step 5: Customers already have data (GOOD!)';
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Products)
BEGIN
    INSERT INTO dbo.Products (product_name, description, price, stock_quantity)
    VALUES
        ('Laptop Pro 15', '15-inch professional laptop', 1299.99, 50),
        ('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 200),
        ('USB-C Hub', '7-in-1 USB-C hub adapter', 49.99, 150),
        ('Monitor 27"', '27-inch 4K monitor', 399.99, 75),
        ('Mechanical Keyboard', 'RGB mechanical keyboard', 89.99, 100);
    PRINT 'Step 6: 5 products inserted';
END
ELSE
BEGIN
    PRINT 'Step 6: Products already have data (GOOD!)';
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Orders)
BEGIN
    INSERT INTO dbo.Orders (customer_id, total_amount, status)
    VALUES
        (1, 1329.98, 'COMPLETED'),
        (2, 449.98, 'COMPLETED'),
        (3, 89.99, 'PENDING'),
        (4, 1699.97, 'SHIPPED'),
        (5, 29.99, 'COMPLETED');
    PRINT 'Step 7: 5 orders inserted';
END
ELSE
BEGIN
    PRINT 'Step 7: Orders already have data (GOOD!)';
END
GO

-- Show final status
SELECT 'Customers' AS TableName, COUNT(*) AS RecordCount FROM dbo.Customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL
SELECT 'Products', COUNT(*) FROM dbo.Products;
GO

PRINT '';
PRINT '===========================================';
PRINT '         SUCCESS! SETUP COMPLETE!          ';
PRINT '===========================================';
PRINT 'CDC is enabled and data is ready.';
PRINT 'Wait 10 minutes for geo-replication to secondary.';
PRINT '===========================================';
GO
