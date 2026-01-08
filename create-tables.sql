-- Create Products table
CREATE TABLE [Products] (
    [Id] int NOT NULL IDENTITY,
    [Name] nvarchar(100) NOT NULL,
    [Description] nvarchar(500) NULL,
    [Price] decimal(18,2) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Products] PRIMARY KEY ([Id])
);
GO

-- Insert sample data
INSERT INTO [Products] ([Name], [Description], [Price], [CreatedAt])
VALUES 
    ('Sample Product 1', 'This is a test product', 29.99, GETDATE()),
    ('Sample Product 2', 'Another test product', 49.99, GETDATE());
GO

-- Verify table was created
SELECT COUNT(*) as ProductCount FROM [Products];
GO
