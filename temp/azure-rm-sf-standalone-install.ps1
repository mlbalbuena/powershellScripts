<#
 script to install service fabric standalone in azure arm
 # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-for-windows-server

 <#
    The CleanCluster.ps1 will clean these certificates or you can clean them up using script 'CertSetup.ps1 -Clean -CertSubjectName CN=ServiceFabricClientCert'.
    Server certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\server.pfx with the password 1230909376
    Client certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\client.pfx with the password 940188492
    Modify thumbprint in C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\ClusterConfig.X509.OneNode.json
#>
# https://github.com/Azure/AzureStack-QuickStart-Templates/blob/master/201-vm-windows-pushcertificate/azuredeploy.json
# query keyvault during deployment
# https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-keyvault-parameter
#>


param(
    [switch]$remove,
    [switch]$force,
    [string]$configurationFile = ".\ClusterConfig.X509.OneNode.json", # ".\ClusterConfig.X509.MultiMachine.json", #".\ClusterConfig.Unsecure.DevCluster.json",
    $packageUrl = "https://go.microsoft.com/fwlink/?LinkId=730690",
    $packageName = "Microsoft.Azure.ServiceFabric.WindowsServer.latest.zip",
    $timeout = 1200,
    $appId,
    $appPassword,
    $tenantId,
    $vaultName,
    $secretName
)

function main()
{
    $Error.Clear()
    $scriptPath = ([io.path]::GetDirectoryName($MyInvocation.ScriptName))
    $downloadPath = "$scriptPath\download"
    Start-Transcript -Path "$scriptPath\install.log"
    $currentLocation = (get-location).Path

    if ($appId -and $appPassword -and $tenantId -and $vaultName -and $secretName)
    {
        if(!(download-cert))
        {
            return 1
        }
    }

    if (!(test-path $downloadPath))
    {
        [io.directory]::CreateDirectory($downloadPath)
    }

    set-location $downloadPath
    $packagePath = "$(get-location)\$([io.path]::GetFileNameWithoutExtension($packageName))"

    if ($force -and (test-path $packagePath))
    {
        [io.directory]::Delete($packagePath, $true)
    }

    if (!(test-path $packagePath))
    {
        (new-object net.webclient).DownloadFile($packageUrl, "$(get-location)\$packageName")
        Expand-Archive $packageName
    }

    Set-Location $packagePath

    if ($remove)
    {
        .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFile -Force
        .\CleanFabric.ps1
    }
    else
    {
        .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFile
        .\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFile -AcceptEULA -NoCleanupOnFailure -GenerateX509Cert -Force -TimeoutInSeconds $timeout -MaxPercentFailedNodes 100
    }

    Connect-ServiceFabricCluster -ConnectionEndpoint localhost:19000
    Get-ServiceFabricNode |Format-Table

    Set-Location $currentLocation
    Stop-Transcript
}

function download-cert()
{
    #  requires WMF 5.0
    #  verify NuGet package
    #
    $nuget = get-packageprovider nuget -Force
    if (-not $nuget -or ($nuget.Version -lt 2.8.5.22))
    {
        write-host "installing nuget package..."
        install-packageprovider -name NuGet -minimumversion 2.8.5.201 -force
    }

    #  install AzureRM module
    #  min need AzureRM.profile, AzureRM.KeyVault
    #
    if (-not (get-module AzureRM -ListAvailable))
    { 
        write-host "installing AzureRm powershell module..." 
        install-module AzureRM -force 
    } 

    #  write-host onto azure account
    #
    write-host "logging onto azure account with app id = $appId ..."

    $creds = new-object Management.Automation.PSCredential ($appId, (convertto-securestring $appPassword -asplaintext -force))
    ## todo remove after test
    login-azurermaccount -credential $creds -serviceprincipal -tenantid $tenantId -confirm:$false

    #  get the secret from key vault
    #
    write-host "getting secret '$secretName' from keyvault '$vaultName'..."
    $secret = get-azurekeyvaultsecret -vaultname $vaultName -name $secretName

    $certCollection = New-Object Security.Cryptography.X509Certificates.X509Certificate2Collection

    $bytes = [Convert]::FromBase64String($secret.SecretValueText)
    $certCollection.Import($bytes, $null, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
	
    add-type -AssemblyName System.Web
    $password = [Web.Security.Membership]::GeneratePassword(38, 5)
    $protectedCertificateBytes = $certCollection.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $password)

    $pfxFilePath = join-path $env:TEMP "$([guid]::NewGuid()).pfx"
    write-host "writing the cert as '$pfxFilePath'..."
    [io.file]::WriteAllBytes($pfxFilePath, $protectedCertificateBytes)

    #  get cert info
    #
    $selfsigned = $false
    $wildcard = $false
    $cert = $null
    $foundcert = $false
    $san = $false

    # look for enhanced key usage having 'server authentication' and ca false
    #
    foreach ($cert in $certCollection)
    {
        if (!($cert.Extensions.CertificateAuthority) -and $cert.EnhancedKeyUsageList -imatch "Server Authentication")
        {
            $foundcert = $true
            break
        }
    }

	
    #  apply certificate
    #
    if ($foundcert)
    {
    }
    else
    {
        write-host "unable to find cert"
        return 1
    }

    <#
    #  clean up
    #  
    if (test-path($pfxFilePath))
    {
        write-host "running cleanup..."
        remove-item $pfxFilePath
    }
    #>
}

main