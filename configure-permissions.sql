IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'app-y7njcffivri2q')
BEGIN
    CREATE USER [app-y7njcffivri2q] FROM EXTERNAL PROVIDER;
    PRINT 'User created successfully';
END
ELSE
BEGIN
    PRINT 'User already exists';
END

ALTER ROLE db_datareader ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_datawriter ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_ddladmin ADD MEMBER [app-y7njcffivri2q];

PRINT 'Permissions granted successfully';
