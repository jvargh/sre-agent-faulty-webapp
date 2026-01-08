using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using FaultyWebApp.Data;
using Azure.Core;
using Azure.Identity;

namespace FaultyWebApp.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class HealthController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly IConfiguration _configuration;
        private readonly ILogger<HealthController> _logger;

        public HealthController(ApplicationDbContext context, IConfiguration configuration, ILogger<HealthController> logger)
        {
            _context = context;
            _configuration = configuration;
            _logger = logger;
        }

        [HttpGet("sql")]
        public async Task<IActionResult> CheckSqlHealth()
        {
            try
            {
                var connectionString = _configuration.GetConnectionString("DefaultConnection");
                
                if (string.IsNullOrEmpty(connectionString))
                {
                    return Ok(new
                    {
                        status = "unhealthy",
                        error = "Connection string not configured",
                        errorType = "ConfigurationError"
                    });
                }

                // Acquire token for Azure SQL
                var credential = new DefaultAzureCredential();
                var tokenRequestContext = new TokenRequestContext(new[] { "https://database.windows.net/.default" });
                var token = await credential.GetTokenAsync(tokenRequestContext);

                using (var connection = new SqlConnection(connectionString))
                {
                    connection.AccessToken = token.Token;
                    
                    await connection.OpenAsync();
                    
                    // Execute a simple query to verify connection
                    using (var command = connection.CreateCommand())
                    {
                        command.CommandText = "SELECT 1";
                        await command.ExecuteScalarAsync();
                    }

                    // Check if Products table exists
                    using (var command = connection.CreateCommand())
                    {
                        command.CommandText = @"
                            SELECT COUNT(*) 
                            FROM INFORMATION_SCHEMA.TABLES 
                            WHERE TABLE_NAME = 'Products'";
                        var result = await command.ExecuteScalarAsync();
                        var tableExists = Convert.ToInt32(result) > 0;

                        if (!tableExists)
                        {
                            return Ok(new
                            {
                                status = "degraded",
                                message = "SQL connection successful but Products table does not exist",
                                connectionState = "Open"
                            });
                        }
                    }

                    return Ok(new
                    {
                        status = "healthy",
                        message = "SQL connection successful",
                        connectionState = connection.State.ToString(),
                        database = connection.Database,
                        serverVersion = connection.ServerVersion
                    });
                }
            }
            catch (SqlException sqlEx)
            {
                _logger.LogError(sqlEx, "SQL Exception occurred while checking health");
                
                return Ok(new
                {
                    status = "unhealthy",
                    error = sqlEx.Message,
                    errorType = "SqlException",
                    errorNumber = sqlEx.Number,
                    errorClass = sqlEx.Class,
                    state = sqlEx.State
                });
            }
            catch (Azure.Identity.AuthenticationFailedException authEx)
            {
                _logger.LogError(authEx, "Authentication failed while acquiring token");
                
                return Ok(new
                {
                    status = "unhealthy",
                    error = authEx.Message,
                    errorType = "AuthenticationException"
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error occurred while checking SQL health");
                
                return Ok(new
                {
                    status = "unhealthy",
                    error = ex.Message,
                    errorType = ex.GetType().Name
                });
            }
        }
    }
}
