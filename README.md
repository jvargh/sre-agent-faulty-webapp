# FaultyWebApp

A secure .NET 8 web application demonstrating enterprise-grade Azure architecture with private networking, managed identities, and zero-trust principles.

[![.NET 8](https://img.shields.io/badge/.NET-8.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![Azure](https://img.shields.io/badge/Azure-Deployed-0078D4?logo=microsoft-azure)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Live Demo

**Application:** [https://app-y7njcffivri2q.azurewebsites.net](https://app-y7njcffivri2q.azurewebsites.net)

## ✨ Features

### Security-First Architecture
- 🔒 **Private Endpoint Only** - Azure SQL accessible exclusively via VNet
- 🆔 **Entra ID Authentication** - No passwords or SQL authentication
- 🎭 **Managed Identity** - Zero secrets, credential-free authentication
- 🌐 **VNet Integration** - Complete network isolation
- 🔐 **Token-Based Auth** - JWT tokens for SQL Server access

### Application Features
- 📊 **Product Dashboard** - Full CRUD operations with responsive UI
- 💚 **Real-Time Health Monitoring** - Live system status indicator
- ⚡ **Auto-Migration** - Database schema created on startup
- 📱 **Mobile-Responsive** - Bootstrap 5 design
- 🔄 **RESTful API** - Complete CRUD endpoints

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │   App Service (P1v3)   │
         │  .NET 8 Web App        │
         │  + Managed Identity    │
         └────────┬───────────────┘
                  │
         VNet Integration (10.0.0.0/24)
                  │
                  ▼
         ┌────────────────────────┐
         │   Virtual Network      │
         │   10.0.0.0/16          │
         └────────┬───────────────┘
                  │
         Private Endpoint (10.0.1.0/24)
                  │
                  ▼
         ┌────────────────────────┐
         │   Azure SQL Database   │
         │   Entra ID Only Auth   │
         │   Private Access Only  │
         └────────────────────────┘
```

### Key Components

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **App Service** | Hosts .NET 8 web application | P1v3 Linux, System-assigned managed identity |
| **Azure SQL** | Database with Entra ID auth | Basic tier, private endpoint only |
| **Virtual Network** | Network isolation | 10.0.0.0/16 with 2 subnets |
| **Private Endpoint** | Secure SQL connectivity | In dedicated subnet (10.0.1.0/24) |
| **Managed Identity** | Credential-free authentication | System-assigned, granted SQL roles |

## 🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- Azure subscription with Owner or Contributor access

### Deploy in 5 Steps

#### 1. Clone and Navigate
```bash
git clone <repository-url>
cd FaultyWebApp
```

#### 2. Login to Azure
```bash
az login
azd auth login
```

#### 3. Deploy Infrastructure & Application
```bash
azd up
```
*Takes ~6-8 minutes. Creates all Azure resources and deploys the app.*

#### 4. Grant SQL Permissions
Navigate to [Azure Portal](https://portal.azure.com) → SQL Databases → FaultyWebAppDb → Query editor

```sql
-- Sign in with Entra ID, then run:
ALTER ROLE db_datareader ADD MEMBER [<your-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<your-app-name>];
ALTER ROLE db_ddladmin ADD MEMBER [<your-app-name>];
GO
```

#### 5. Secure SQL Server
```bash
az sql server update \
  --name <sql-server-name> \
  --resource-group <resource-group> \
  --enable-public-network false
```

**Done!** Your secure application is live. 🎉

## 📖 Documentation

- **[Complete Deployment Guide](DEPLOYMENT-SUMMARY.md)** - Detailed setup, troubleshooting, and configuration
- **[Infrastructure as Code](infra/)** - Bicep templates for Azure resources
- **[API Documentation](#api-endpoints)** - RESTful API reference

## 🛠️ Technology Stack

### Backend
- **.NET 8.0** - Latest LTS framework
- **ASP.NET Core MVC** - Web framework
- **Entity Framework Core 8** - ORM with migrations
- **Azure.Identity** - Managed identity SDK
- **Microsoft.Data.SqlClient** - SQL Server connectivity

### Frontend
- **Bootstrap 5.3** - Responsive UI framework
- **Vanilla JavaScript** - No framework dependencies
- **CSS3** - Custom styling

### Infrastructure
- **Azure App Service** - PaaS hosting
- **Azure SQL Database** - Managed database
- **Azure Virtual Network** - Network isolation
- **Private Endpoint** - Secure connectivity
- **Azure Developer CLI** - Deployment automation

## 📡 API Endpoints

### Products API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/products` | List all products |
| `GET` | `/api/products/{id}` | Get product by ID |
| `POST` | `/api/products` | Create new product |
| `PUT` | `/api/products/{id}` | Update product |
| `DELETE` | `/api/products/{id}` | Delete product |

### Health Check

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Returns "Healthy" if database connection works |

### Example: Create Product
```bash
curl -X POST https://app-y7njcffivri2q.azurewebsites.net/api/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sample Product",
    "description": "Product description",
    "price": 29.99
  }'
```

## 🔒 Security Features

### Zero-Trust Architecture
✅ **No Secrets Stored** - Managed identity eliminates credential storage  
✅ **Private Networking** - SQL Server not accessible from internet  
✅ **Token-Based Auth** - JWT tokens for database access  
✅ **TLS 1.2+** - Encrypted communications only  
✅ **Entra ID Integration** - Enterprise identity provider  

### Authentication Flow
```
1. App Service starts
2. Managed Identity acquires token from Entra ID
3. Token scoped for SQL Database (https://database.windows.net/.default)
4. Token attached to SQL connection (no password needed)
5. Azure SQL validates token with Entra ID
6. Connection established with granted permissions
```

## 🎨 Dashboard UI

The application includes a fully-featured product management dashboard:

### Features
- **Live Health Status** - Green/red indicator with 30-second refresh
- **Product Table** - Sortable, searchable list with all product details
- **Add Products** - Modal form with validation
- **Delete Products** - Confirmation dialog before deletion
- **Responsive Design** - Mobile-friendly layout
- **Empty States** - Helpful messages when no data exists

## Running Locally

For local development, `DefaultAzureCredential` will attempt to authenticate using:
1. Azure CLI (if logged in)
2. Visual Studio
3. Visual Studio Code
4. Environment variables

Ens🧪 Local Development

### Setup
```bash
# Clone repository
git clone <repository-url>
cd FaultyWebApp

# Install dependencies
dotnet restore

# Apply migrations
dotnet ef database update

# Run application
dotnet run
```

### Configuration
Update `appsettings.Development.json`:
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=FaultyWebApp;Trusted_Connection=True;"
  }
}
```

### Testing
```bash
# Run tests
dotnet test

# Build release
dotnet build -c Release

# Publish
dotnet publish -c Release -o ./publish
```

## 📊 Cost Estimate

**Monthly Azure Costs (East US 2):**

| Resource | SKU | Cost |
|----------|-----|------|
| App Service Plan | P1v3 Linux | ~$146/month |
| SQL Database | Basic (2GB) | ~$5/month |
| Private Endpoint | Standard | ~$7.30/month |
| Private DNS Zone | Standard | ~$0.50/month |
| **Total** | | **~$159/month** |

**💡 Cost Optimization:**
- Use S1 App Service: Save ~$76/month
- Use SQL Serverless: Variable ~$15/month
- Stop services when not in use
4. Verify firewall rules allow private endpoint traffic

### Authentication Issues

1. Confirm Managed Identity is enabled
2. Verify SQL user was created for the Managed Identity
3. Check role memberships in the database
4. Ensure token scope is `https://database.windows.net/.default`

## Additional Resources

- [Azure SQL Database Private Endpoint](https://docs.microsoft.com/azure/azure-sql/database/private-endpoint-overview)
- [Azure Managed Identity](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
- [DefaultAzureCredential](https://docs.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)
- [Entity Framework Core with Azure SQL](https://docs.microsoft.com/ef/core/)
🐛 Troubleshooting

### Common Issues

**Problem:** Health check returns "Unhealthy"  
**Solution:** Verify SQL permissions were granted to managed identity

**Problem:** API returns 500 error  
**Solution:** Check App Service logs: `az webapp log tail --name <app-name> --resource-group <rg-name>`

**Problem:** Private endpoint not working  
**Solution:** Verify VNet integration is enabled and DNS resolves to private IP

📚 **Full troubleshooting guide:** [DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md#troubleshooting)

## 📁 Project Structure

```
FaultyWebApp/
├── Controllers/          # API and MVC controllers
│   ├── ProductsController.cs
│   └── HomeController.cs
├── Data/                 # Database context and models
│   └── ApplicationDbContext.cs
├── Migrations/           # EF Core database migrations
├── Views/                # Razor views
│   ├── Home/
│   │   └── Index.cshtml  # Product dashboard
│   └── Shared/
│       └── _Layout.cshtml
├── wwwroot/              # Static files
│   ├── css/
│   └── js/
├── infra/                # Infrastructure as Code
│   ├── main.bicep
│   └── modules/
│       ├── network.bicep
│       ├── sql.bicep
│       └── webapp.bicep
├── Program.cs            # Application entry point
├── appsettings.json      # Configuration
├── azure.yaml            # Azure Developer CLI config
└── README.md             # This file
```

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Azure Developer CLI](https://aka.ms/azd)
- Follows [Azure Architecture Best Practices](https://learn.microsoft.com/azure/architecture/)
- Implements [Zero Trust Security](https://www.microsoft.com/security/business/zero-trust)

## 📞 Support

- 📧 **Issues:** [GitHub Issues](https://github.com/your-repo/issues)
- 📚 **Documentation:** [DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/your-repo/discussions)

## 🎯 Roadmap

- [ ] Add Application Insights integration
- [ ] Implement CI/CD with GitHub Actions
- [ ] Add authentication for web UI
- [ ] Implement caching layer (Redis)
- [ ] Add automated testing suite
- [ ] Create Docker support
- [ ] Add OpenAPI/Swagger documentation

---

**Built with ❤️ using .NET 8 and Azure**

*Last Updated: January 7, 2026*