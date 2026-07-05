# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = file("credentials.txt")
}


resource "azurerm_resource_group" "service_requests_rg" {
  name     = "service_requests"
  location = "uk south"
}

resource "azurerm_storage_account" "service_requests_storage" {
  name                     = "urbancitystorageayo"
  resource_group_name      = azurerm_resource_group.service_requests_rg.name
  location                 = azurerm_resource_group.service_requests_rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name    = azurerm_storage_account.service_requests_storage.name
  container_access_type = "private"
  depends_on = [ azurerm_storage_account.service_requests_storage]
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name    = azurerm_storage_account.service_requests_storage.name
  container_access_type = "private"
  depends_on = [ azurerm_storage_account.service_requests_storage]
}

resource "azurerm_postgresql_flexible_server" "db_server" {
  name                          = "urbancitypgserver"
  resource_group_name           = azurerm_resource_group.service_requests_rg.name
  location                      = azurerm_resource_group.service_requests_rg.location
  version                       = "16"
  public_network_access_enabled = true
  administrator_login           = var.username
  administrator_password        = var.pg_password
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P30"

  sku_name   = "GP_Standard_D4s_v3"
  create_mode = "Default"
  authentication {
    password_auth_enabled = true
  }
  depends_on = [azurerm_resource_group.service_requests_rg]
}

resource "azurerm_postgresql_flexible_server_database" "db_database" {
  name                = "urban_city_db"
  server_id         = azurerm_postgresql_flexible_server.db_server.id
  collation           = "en_US.utf8"
  charset             = "UTF8"


  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = false
  }
}

# Data Factory, This will point to the storage account I want to get my data from
data "azurerm_storage_account" "storage_account_data" {
  name                = azurerm_storage_account.service_requests_storage.name
  resource_group_name = azurerm_resource_group.service_requests_rg.name
  depends_on = [azurerm_storage_account.service_requests_storage]
}

resource "azurerm_data_factory" "data_factory_server" {
  name                = "urbancityfactory"
  location            = azurerm_resource_group.service_requests_rg.location
  resource_group_name = azurerm_resource_group.service_requests_rg.name
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "blobstoragels" {
  name              = "blob_storage_ls"
  data_factory_id   = azurerm_data_factory.data_factory_server.id
  connection_string = data.azurerm_storage_account.storage_account_data.primary_connection_string
}

resource "azurerm_data_factory_dataset_parquet" "urbancityds" {
  name                = "urban_city_parquet_ds"
  data_factory_id     = azurerm_data_factory.data_factory_server.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.blobstoragels.name

  compression_codec = "snappy"

  azure_blob_storage_location {
    container = "silver"
    filename = "urban_service_requests.parquet"
  }
}



## NOTE THAT DUE TO FLEXIBLE PG SERVER, WE COULDNTY CREATE LS FOR THIS DATASET AND HAD TO DUE IN AZ PORTAL MANUALLY
## Firstly sort out the networking of my created pg server
## Then need to create the pg database Ls MANUALLY
## Then create the dataset in adf
## There after create my ADF pipeline and link source to sink
## Then got all needed certificates and secrets linked to airflow admin connection etc
## The below are the details :
    ## Postgres db ls : AzurePostgreSQL_ls
    ## DataSet name : AzurePostgreSqlTable1
    ## Copy Activity Name : SilverToGoldPipeline
    ## Pipeline Name : UrbanCityDataFactoryPipeline
## Make sure after I have created this extra steps above, I'm destroying all resources from az portal and not terraform destroy command.
