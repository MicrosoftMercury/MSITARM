      # Login to Azure Subscription
      Login-AzureRmAccount
      $templatePath = $PSScriptRoot
      $TemplateFile = $templatePath + "\azuredeploy.multivm.json" 
      $TemplateParameterFile = $templatePath + "\azuredeploy.parameters.multivm.json" 
      # Provide location for Deployment. IT should be West US
      $Location = "West US"
      $AvSet = "TestAvSet"
      # Provide resource group name. It should be starting from ICTO number e.g. 2357-Alfred-UAT
      $resourceGroupName = "2357-Test-10"
      
      # Provide storage account details. e.g. 2357alfreduatsa
      $destStorageAccount = "2357test110"
      
      # Provide the VMName. E.G. alfrediaasuat
      $vmName = 'AzGITAlfred0'

      
      if (!$cred) { $cred = (Get-Credential).GetNetworkCredential() }
      # Login to Azure Portal
      Login-AzureRmAccount -Credential $cred

      # Select the subscription id. Please do not change this
      $subscriptionId = "<<subscription ID here>>"
      Select-AzureRmSubscription -SubscriptionID $subscriptionId;

      # Create requested resource group
    $exists = Get-AzureRmResourceGroup -Location $Location | Where-Object {$_.ResourceGroupName -eq $resourceGroupName}
    if (!$exists) {
        New-AzureRMResourceGroup -Name $resourceGroupName -Location $Location -Force
    }

      #Create the new storage account
      New-AzureRMStorageAccount -AccountName $destStorageAccount -Location $Location -ResourceGroupName $ResourceGroupName -Type "Standard_LRS"
      
    # Get my pwd for domain joining this VM
    if (!$cred) { $cred = (Get-Credential).GetNetworkCredential() }

   
      # Do the new Azure deployment 
      New-AzureRmResourceGroupDeployment -Name ($env:computername + (split-path ((ls).DirectoryName[0]) -leaf)).substring(0,5) -ResourceGroupName $resourceGroupName `
            -TemplateFile $TemplateFile `
            -TemplateParameterFile $TemplateParameterFile `
            -vmName $vmName   `
            -domainJoinUserName ($cred.Domain+'\'+$cred.UserName) `
            -domainJoinPassword $cred.SecurePassword `
            -localAdminUserName 'azmin' `
            -localAdminPassword $cred.SecurePassword `
            -localAdmins ($cred.Domain+'\'+$cred.UserName) `
            -userImageStorageAccountName $destStorageAccount `
            -numberOfInstances 2 
           

