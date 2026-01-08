CREATE USER [app-y7njcffivri2q] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_datawriter ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_ddladmin ADD MEMBER [app-y7njcffivri2q];
GO