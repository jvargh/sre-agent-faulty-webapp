using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using FaultyWebApp.Data;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllersWithViews();

// Configure Azure SQL connection with Managed Identity
var sqlConnectionString = builder.Configuration.GetConnectionString("DefaultConnection");

if (string.IsNullOrEmpty(sqlConnectionString))
{
    throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
}

// Register DefaultAzureCredential for managed identity authentication
builder.Services.AddSingleton<TokenCredential>(new DefaultAzureCredential(
    new DefaultAzureCredentialOptions
    {
        // This will use Managed Identity in Azure
        // For local development, it will try Azure CLI, Visual Studio, etc.
        ExcludeEnvironmentCredential = false,
        ExcludeManagedIdentityCredential = false,
        ExcludeSharedTokenCacheCredential = false,
        ExcludeVisualStudioCredential = false,
        ExcludeVisualStudioCodeCredential = false,
        ExcludeAzureCliCredential = false,
        ExcludeAzurePowerShellCredential = true,
        ExcludeInteractiveBrowserCredential = true
    }));

// Configure DbContext with SQL Server and Managed Identity authentication
builder.Services.AddDbContext<ApplicationDbContext>((serviceProvider, options) =>
{
    var credential = serviceProvider.GetRequiredService<TokenCredential>();
    
    var sqlConnection = new SqlConnection(sqlConnectionString);
    
    // Get access token for Azure SQL using managed identity
    // The scope for Azure SQL Database is always https://database.windows.net/.default
    var tokenRequestContext = new TokenRequestContext(new[] { "https://database.windows.net/.default" });
    var token = credential.GetToken(tokenRequestContext, default);
    sqlConnection.AccessToken = token.Token;
    
    options.UseSqlServer(sqlConnection);
});

// Add health checks
builder.Services.AddHealthChecks()
    .AddDbContextCheck<ApplicationDbContext>();

var app = builder.Build();

// Auto-create database and apply migrations on startup
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    try
    {
        var context = services.GetRequiredService<ApplicationDbContext>();
        Console.WriteLine("Applying database migrations...");
        context.Database.Migrate(); // This will create the database and apply all migrations
        Console.WriteLine("✓ Database migrations applied successfully");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error applying migrations: {ex.Message}");
        Console.WriteLine($"   Stack trace: {ex.StackTrace}");
    }
}

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

// Map health check endpoint
app.MapHealthChecks("/health");

app.Run();
