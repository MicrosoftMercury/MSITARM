#Requires -RunAsAdministrator

function deploy {
       Param(
         [string] [Parameter(Mandatory=$true)] $SubscriptionId,
         [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
         [string] [Parameter(Mandatory=$true)] $ResourceGroupName,
         [string] $OuPath = 'OU=ITManaged,OU=ITServices,DC=redmond,DC=corp,DC=microsoft,DC=com',
         [string] $TemplateFile =  'template.json',
         [string] $TemplateParameterFile = 'templateParams.json',
         [switch] $PromptToContinue
       )

       Set-StrictMode -Version 3
       $error.Clear()

       $TemplateFile=(Get-Location).Path + "\$templateFile"
       $TemplateParameterFile = (Get-Location).Path + "\$TemplateParameterFile"

       if($PSCmdlet.MyInvocation.BoundParameters['Verbose'] -eq $true) {
            $VerbosePreference = "Continue"
        } else {
            $VerbosePreference = "SilentlyContinue"
        }

       
       #Check if PS Module is installed
       try {
            Import-Module Azure -ErrorAction SilentlyContinue
       } catch {
            write-host -f red 'You need to install Azure Powershell.  For help updating this module visit: https://azure.microsoft.com/en-us/downloads/'
            return $false
       }

       #Check if PS Module is right version
       if (Get-Module -ListAvailable | Where-Object { $_.Name -eq 'AzureResourceManager' -and $_.Version -ge '0.9.9' }) {
              write-host -f red "The version of the Azure PowerShell cmdlets installed on this machine are not compatible with this script.  For help updating this script visit: http://go.microsoft.com/fwlink/?LinkID=623011"
              return $false
       }
       
       #Check if CloudMS Module is installed
       try {
            Import-Module .\CloudMSUtilities.psm1 -ErrorAction SilentlyContinue
       } catch {
            write-host -f red 'You need to install CloudMSUtilities.  For help updating this module visit: https://[needurl]'
            return $false
       }

       #check if Path to resource JSON is ok
        Write-host -f Gray "Check if Path to Template JSON..."
       If (Test-Path -Path $TemplateFile)
       {
            Write-host -f Green "$TemplateFile found."
       }
       Else
       {
            write-host -f red  "$TemplateFile not found, please navigate to the directory where deployscript.ps1 is located and re-run!"
            return $false
                       
       }

       #check if Path to parameter JSON is ok
       Write-host -f Gray "Check if Path to Parameters JSON..."
       If (Test-Path -Path $TemplateParameterFile)
       {
            Write-host -f Green "$TemplateParameterFile found."
       }
       Else
       {
           write-host -f red  "$TemplateFile not found, please navigate to the directory where deployscript.ps1 is located and re-run!"
           return $false
       }
            
       Write-host -f Gray "Connect to Azure..."
       try {
            
              #Check if the user is already logged in for this session
              $AzureRmContext = Get-AzureRmContext | out-null
              write-host -f Green "Using Azure Cached Crentials."

       } catch {

              #Prompts user to login to Azure account
              Login-AzureRmAccount | out-null
              write-host -f Green "logged into Azure."
              $error.Clear()
       }

       #Selects the Azure subscription to be used
       Write-host -f Gray "Connect to subcription $SubscriptionId..."
       Set-AzureRmContext -SubscriptionId $SubscriptionId | out-null
         
            if($error) {
                Write-host -f red "stopping due to errors!"
                Write-host -f red $error[0]
                $error.Clear()
                return $false
            }
       write-host -f Green "Connected to subcription $SubscriptionId."
  
       #Get contents of the template parameters file
       Write-host -f Gray 'Reading template file contents...'
       $params = New-Object -TypeName Hashtable
       $TemplateFilePath = [System.IO.Path]::Combine($PSScriptRoot, $TemplateFile)
       $TemplateParameterFilePath = [System.IO.Path]::Combine($PSScriptRoot, $TemplateParameterFile)
       
       $JsonParams = Get-Content $TemplateParameterFile | ConvertFrom-Json
       $JsonTemp = Get-Content $TemplateFilePath | ConvertFrom-Json

		#Request for domain join credentials
        $variable = Get-Variable -Name DomainCreds -Scope Global -ErrorAction SilentlyContinue
        if(!$variable) {$global:DomainCreds=$null}

		do {
            #$domainCreds=[Security.Principal.WindowsIdentity]::getcurrent()
            #$global:DomainCreds=$domainCreds

		   if($global:DomainCreds) {
              
                    Write-Host -f Green "using Cached Domain Credentials for $($DomainCreds.UserName)."
                    $DomainCreds = $global:DomainCreds
                    $ValidCredential = $true
                
            }else{

		        $DomainCreds = Get-Credential -Message 'DOMAIN ACCOUNT: Please enter the domain credentials'
            
                Add-Type -AssemblyName System.DirectoryServices.AccountManagement
                $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
        
		    Try 
            {
                $ValidCredential = $DS.ValidateCredentials($DomainCreds.UserName, $($DomainCreds.GetNetworkCredential().Password))
            } 
            Catch 
            {
                $global:DomainCreds=$null
                $ValidCredential = $false
            }
              if($validCredential -eq $false){
                Write-host -f red "Invalid Credentials!"
                $cont = read-host "Try again? (Y)es"
                if($cont -ne 'Y') {
                    write-host -f Gray "Stopping."
                    return $false
                }
               }
            }

        } until ($validcredential -eq $true -or $cont -ne 'Y')
        $error.Clear()
        $global:DomainCreds=$domainCreds
        
        do {
            $variable = Get-Variable -Name localCreds -Scope Global -ErrorAction SilentlyContinue
            if(!$variable) {$global:localCreds=$null}
            
            if(!$global:localCreds) {
                if($JsonParams.parameters.localAdminUserName.value.length -eq 0 -or $JsonParams.parameters.localAdminUserName.value -eq "[prompt]" ) {
		            #Request for local account credentials
		            $LocalCreds = Get-Credential -Message 'LOCAL ACCOUNT: Please enter the credentials' 
                    $global:localCreds=$LocalCreds
                     $JsonParams.parameters.localAdminUserName.value=$($global:localCreds).UserName
                     $JsonParams.parameters.localAdminPassword.value=$($global:localCreds).Password
                 } else {
                    Write-Host -f Green "using parameter values local Credentials for $($JsonParams.parameters.localAdminUserName.value)."	
                        $secpasswd = ConvertTo-SecureString  $JsonParams.parameters.localAdminPassword.value -AsPlainText -Force
                        $global:localCreds = New-Object System.Management.Automation.PSCredential ($JsonParams.parameters.localAdminUserName.value, $secpasswd)
                        $localCreds=$global:localCreds 
                                         }
                }else {
                    $localCreds=$global:localCreds 
                    $JsonParams.parameters.localAdminUserName.value=$($global:localCreds).UserName
                    $JsonParams.parameters.localAdminPassword.value=$($global:localCreds).Password
                }
               
            if( $localcreds.UserName -match "^\w{1,19}$")   {
                $validCredential=$true
             }else {
                $validCredential=$false
                 $localCreds=$null
                 $global:localCreds=$null
                 $JsonParams.parameters.localAdminUserName.value = ""
            }
 
            if($validCredential -eq $false){
                Write-host -f red "Invalid Credentials!"
                $cont = read-host "Try again? (Y)es"
                if($cont -ne 'Y') {
                    write-host -f Gray "Stopping."
                    return $false
                } else {$global:localCreds=$null}
               }

         } until ($validcredential -eq $true -or $cont -ne 'Y')
         
       #ensure we have values for VM's, Additional Admins and Diagnostics Storage.

       $variable = Get-Variable -Name vmNamePart -Scope Global -ErrorAction SilentlyContinue
       
        if(!$variable) {$global:vmNamePart=$null}
        if(!$global:vmNamePart) {
            if($JsonParams.parameters.vmName.value.length -eq 0 -or $JsonParams.parameters.vmName.value -eq "[prompt]" ) {
                $JsonParams.parameters.vmName.value = $(read-host "VMName name part? ").ToString() 
                $global:vmNamePart= $JsonParams.parameters.vmName.value
            } else {
                $global:vmNamePart= $JsonParams.parameters.vmName.value
                 $vmNamePart= $global:vmNamePart
            }
        }else {
            Write-Host -f Green "using Cached VM Name Part $($global:vmNamePart)."
            $JsonParams.parameters.vmName.value = $global:vmNamePart
        }

       $variable = Get-Variable -Name AdditionalAdmins -Scope Global -ErrorAction SilentlyContinue
       if(!$variable) {$global:AdditionalAdmins=$null}

       if(!$global:AdditionalAdmins) {
	       if($JsonParams.parameters.AdditionalAdmins.value.length -eq 0 -or $JsonParams.parameters.AdditionalAdmins.value -eq "[prompt]" ) {
                $JsonParams.parameters.AdditionalAdmins.value =  $(read-host "AdditionalAdmins ? ").ToString()  
                $global:AdditionalAdmins = $JsonParams.parameters.AdditionalAdmins.value
            }else {
             $global:AdditionalAdmins = $JsonParams.parameters.AdditionalAdmins.value
             $AdditionalAdmins = $global:AdditionalAdmins 
            } 
         }else 
            {
                Write-Host -f Green "using Cached AdditionalAdmins $($global:AdditionalAdmins)."
                $JsonParams.parameters.AdditionalAdmins.value = $global:AdditionalAdmins
            }
       
        
        $variable = Get-Variable -Name numberOfInstances -Scope Global -ErrorAction SilentlyContinue
        if(!$variable) {$global:numberOfInstances=$null}

        if(!$global:numberOfInstances) {
            if($JsonParams.parameters.numberOfInstances.value -eq 0 ) {
                $JsonParams.parameters.numberOfInstances.value =  $(read-host "Number of Instances? ") 
                if(!$([int]$($JsonParams.parameters.numberOfInstances.value.Replace('"',"")) -ge 1)){
                    write-host -f red "Number of instances must be => 1"
                    return $false
                }
                $global:numberOfInstances=$JsonParams.parameters.numberOfInstances.value
                $numberOfInstances=$global:numberOfInstances
            } else {
                $numberOfInstances=$JsonParams.parameters.numberOfInstances.value
                $global:numberOfInstances=$numberOfInstances
            }
        } else
            {
                Write-Host -f Green "using Cached numberOfInstances $($global:numberOfInstances)."
                $JsonParams.parameters.numberOfInstances.value = $global:numberOfInstances
                $numberOfInstances=$global:numberOfInstances
            }

        $variable = Get-Variable -Name imagePublisher -Scope Global -ErrorAction SilentlyContinue
        if(!$variable) {$global:imagePublisher=$null}

        if(!$global:imagePublisher) {
            if($JsonParams.parameters.imagePublisher.value.length -eq 0 -or $JsonParams.parameters.imagePublisher.value -eq "[prompt]" ) {
               
		        #Request for local account credentials
                write-host -f Gray "Available imagePublisher"
                $JsonTemp.parameters.imagePublisher.allowedValues 
                 
                $tries=1
                $valid=$false
                do {
		        $imagePublisher = [string] $(Read-Host 'imagePublisher?') 
               
                    if(!$($JsonTemp.parameters.imagePublisher.allowedValues -match $imagePublisher)) {
                        write-host -f red "$imagepublisher is not valid"
                        $valid= $false
                        $tries+=1
                    }else {$valid=$true}
                    if($tries -gt 3){return $false}
                } until ($valid)

                $global:imagePublisher=$imagePublisher  
                $JsonParams.parameters.imagePublisher.value=$imagePublisher        
                      
            }  else {
                $imagePublisher=$JsonParams.parameters.imagePublisher.value
                $global:imagePublisher=$imagePublisher 
            }
        } else {
                Write-Host -f Green "using Cached imagePublisher for $($imagePublisher)."	
                $sku=$global:imagePublisher 
                $JsonParams.parameters.imagePublisher.value=$imagePublisher
        }

                
        $variable = Get-Variable -Name imageOffer -Scope Global -ErrorAction SilentlyContinue
        if(!$variable) {$global:imageOffer=$null}

        if(!$global:imageOffer) {
            if($JsonParams.parameters.imageOffer.value.length -eq 0 -or $JsonParams.parameters.imageOffer.value -eq "[prompt]" ) {
               
		        #Request for local account credentials
                write-host -f Gray "Available imageOffer"
                $results=(Get-AzureRmVMImageOffer -Location $ResourceGroupLocation -PublisherName $imagePublisher) | select Publisher -ExpandProperty Offer | where { $_ -like '*Windows*' -or $_ -like '*SQL*' } 
                $results 
                $tries=1
                $valid=$false
                do {
		        $imageOffer = [string] $(Read-Host 'Offer?') 

                    if(!$($results -match $imageOffer)) {
                        write-host -f red "$imageOffer is not valid"
                        $valid= $false
                        $tries+=1
                    }else {$valid=$true}
                    if($tries -gt 3){return $false}
                 } until ($valid)

                $global:imageOffer=$imageOffer  
                $JsonParams.parameters.imageOffer.value=$imageOffer        
                      
            }  else {
                $imageOffer=$JsonParams.parameters.imageOffer.value
                $global:imageOffer=$imageOffer 
            }
        } else {
                Write-Host -f Green "using Cached imageOffer for $($imageOffer)."	
                $imageOffer=$global:imageOffer 
                $JsonParams.parameters.imageOffer.value=$imageOffer
        }

        $variable = Get-Variable -Name sku -Scope Global -ErrorAction SilentlyContinue
        if(!$variable) {$global:sku=$null}

        if(!$global:sku) {
            if($JsonParams.parameters.sku.value.length -eq 0 -or $JsonParams.parameters.sku.value -eq "[prompt]" ) {
               
		        #Request for local account credentials
                write-host -f Gray "Available SKU"
                $results = (Get-AzureRmVMImageSku -Location $ResourceGroupLocation -PublisherName $imagePublisher -Offer $imageOffer) | select -ExpandProperty Skus 
                $results 
                $tries=1
                $valid=$false
                do {
		        $sku = [string] $(Read-Host 'SKU?') 

                    if(!$($results -match $sku)) {
                        write-host -f red "$sku is not valid"
                        $valid= $false
                        $tries+=1
                    }else {$valid=$true}
                    if($tries -gt 3){return $false}
                } until ($valid)

                $global:sku=$sku  
                $JsonParams.parameters.sku.value=$sku        
                      
            }  else {
                $sku=$JsonParams.parameters.sku.value
                $global:sku=$sku 
            }
        } else {
                Write-Host -f Green "using Cached SKU for $($sku)."	
                $sku=$global:sku 
                $JsonParams.parameters.sku.value=$sku
        }
        

       #Get server name
       $ServerName = $JsonParams.parameters.vmName.value
      
       #Get number of VMs to be created
       $NumberOfInstances = $JsonParams.parameters.numberOfInstances.value
       
       #Get domain name
       $DomainName = $JsonParams.parameters.domainName.value

       #populate parameters with local account 
       $JsonParams.parameters.LocalAdminUserName.Value = $LocalCreds.UserName
       $JsonParams.parameters.LocalAdminPassword.Value = $($LocalCreds.GetNetworkCredential().Password)
     
        try {
              

        #build a Hashtable with Parameters
        $params = @{
                   "localAdminUserName"=$JsonParams.parameters.LocalAdminUserName.Value; 
                   "localAdminPassword"=$JsonParams.parameters.LocalAdminPassword.Value; 
                   "vmName"=$JsonParams.parameters.vmName.Value; 
                   "additionalAdmins"=$JsonParams.parameters.additionalAdmins.Value; 
                   "imagePublisher"=$JsonParams.parameters.imagePublisher.Value; 
                   "imageOffer"=$JsonParams.parameters.imageOffer.Value; 
                   "sku"=$JsonParams.parameters.sku.Value; 
                   "APPid"=$JsonParams.parameters.APPid.Value; 
                   "orgID"=$JsonParams.parameters.orgID.Value; 
                   "domainName"=$JsonParams.parameters.domainName.Value; 
                   "env"=$JsonParams.parameters.env.Value;
                   "snoozeDate"=$JsonParams.parameters.snoozeDate.Value;
                   "storageAccountType"=$JsonParams.parameters.storageAccountType.Value;
                   "userImageStorageAccountName"=$JsonParams.parameters.userImageStorageAccountName.Value;
                   "vmSize"=$JsonParams.parameters.vmSize.Value;
                   "vnetId"=$JsonParams.parameters.vnetId.Value;
                   "numberOfInstances"=[int]$JsonParams.parameters.numberOfInstances.Value;
                  }

            } catch {
         
                write-host -f red $error[0]
                $error.Clear()
                return $false
            }
            Write-host -f Green 'Data loaded.'
            
            ################################################################
               write-host -f gray "################################################################"
               Write-Host -f gray " reset-cache to clear the cached data. Show-Cache to see it."

                Show-Cache

            write-host -f gray "################################################################"
            if($PromptToContinue) {
                $cont = read-host "Continue? (Y)es"
                if($cont -ne 'Y') {
                    write-host -f Gray "Stopping."
                    return $false
                }
            }
                $error.clear()
            ################################################################
            Write-host -f Gray 'Checking for deployments in progress...'
           do {

            $building= get-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName | ? {$_.provisioningstate -ne 'Failed' -and $_.provisioningstate -ne 'Succeeded' -and $_.provisioningstate -ne 'Canceled'}

            if($building) {
                Write-host -f Gray 'Another Deployment is in progress, sleeping.'
                write-host -f Gray "$($building.DeploymentName) is $($building.ProvisioningState) at $($building.Timestamp) "
                Start-Sleep -s 30
            }
           } until (!$building)

           $deploymentName=(('ARMDomainJoinVM-') + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
           Write-host -f Gray "New-AzureRMResourceGroupDeployment -Name $deploymentName starting..."
           
           try {

           $buildTemplate= New-AzureRmResourceGroupDeployment -Name $deploymentName `
                                                                 -ResourceGroupName $ResourceGroupName `
                                                                 -TemplateFile $TemplateFilePath `
                                                                 -TemplateParameterObject $params `
                                                                 -Force -Verbose

                

                if($($buildTemplate.ProvisioningState) -eq "Failed") {
                    throw "$($buildTemplate.DeploymentName) status of $($buildTemplate.ProvisioningState) on $($buildTemplate.Timestamp)"
                } else {
                    write-host -f Green "$($buildTemplate.DeploymentName) status of $($buildTemplate.ProvisioningState) on $($buildTemplate.Timestamp)"
                }
            } catch {
                Write-host -f red "stopping due to errors"
                Write-host -f red $error[0]
                $error.Clear()
                return $false
            }
           

        $sleep = $false	

        for ($i = 0; $i -lt $NumberOfInstances; $i++) {
           
            #Check VM status, wait until its ready
            get-VMBuildStatus $($ServerName + $i) -ResourceGroupName $ResourceGroupName -waitfor
           		  

		  #Get IP address of the VM
		  Write-host -f Gray 'Getting VM IP address...'
		  $AzureIp = (Get-AzureRmNetworkInterface -Name ($ServerName + $i + 'nic1') -ResourceGroupName $ResourceGroupName).IpConfigurations[0].PrivateIpAddress
		  Write-host -f Green "$($ServerName + $i) => IPAddress = $AzureIp"
		  
		  #Setting PrivateIpAllocationMethod to Static
		  Write-host -f Gray 'Setting Private IP allocation method to Static...'
		  $Nic = (Get-AzureRmNetworkInterface -Name ($ServerName + $i + 'nic1') -ResourceGroupName $ResourceGroupName)
		  $Nic.IpConfigurations[0].PrivateIpAllocationMethod = 'Static'
		  $nicData= Set-AzureRmNetworkInterface -NetworkInterface $Nic
		   
          write-host -f Green "NetworkInterface $($ServerName + $i + 'nic1') status of $($nicData.ProvisioningState)"

          
          Write-host -f Gray 'Configuring WinRM...'
            
                $LocalWinRMscript = {
                    $ip = $args[0]
                    iex $("winrm set winrm/config/client `'@{TrustedHosts=`"$ip`"}`'")
                }
             
                $result = Invoke-Command -ScriptBlock $LocalWinRMscript -ArgumentList $AzureIp
                        
            if(!$sleep){  # only need to wait once
                Write-host -f Gray 'Waiting for 1 minutes for the NIC to setup...'
		        Start-Sleep -s (1*60)
                $sleep = $true
            }
           write-host -f Green "Local WinRM ready"

          Write-host -f Gray 'Is Machine already domain joined?...'
          $isInDomain=$(invoke-command -computername $AzureIp -scriptblock {((gwmi win32_computersystem).partofdomain)} -ErrorAction SilentlyContinue -Credential ($DomainCreds) -SessionOption (New-PsSessionOption -SkipCACheck -SkipCNCheck))

          if(!$isInDomain) {

            $error.clear()  #above generates error until machine is Domain joined
            write-host -f Green "$($ServerName + $i) is ready to Domain Join"

            try {
            
                #Get the domain user's SID
               Write-host -f Gray  "Peparing Remote machine: adding $($DomainCreds.userName) to administrators and Configuring Winrm..."
                $DomainCredsString =  $DomainCreds.UserName
                $index = $DomainCredsString.IndexOf('\')
             
                $domain = $DomainCredsString.Substring(0, $index)
                $alias =  $DomainCredsString.Substring($index + 1,$DomainCredsString.length - $index -1)
    
                $objUser = New-Object System.Security.Principal.NTAccount($domain, $alias)
                $Sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
                $strSid = $Sid.Value  
        
                #Add the Domain user to the administrators group on the new VM by SID 
                $PrepareScript = {
                    try{
                    $mysid = $args[0]
                    $myuser = $args[1]
                    $mypwd = $args[2]

                    $computer = [ADSI]("WinNT://localhost,computer")
                    $AdminsGroup=Get-WmiObject -Class Win32_Group -computername localhost -Filter "SID='S-1-5-32-544' AND LocalAccount='True'"
                    $grp = $computer.psbase.children.find($AdminsGroup.Name)
                    $grp.Add("WinNT://$($mysid)")

                     write-host -f green "user added to Local Administrators"

                    }catch{
                        if(!$([string] $error[0] -match 'already a member')) {
                         throw $error[0]
                        } else {
                            $error.clear()
                        }

                    }

                    try {
                    #Create a sched task on the RB server to configure WinRM via PSExec...
                    $A = New-ScheduledTaskAction  -Execute "PSExec.exe" -Argument "\\$($env:Computername) -acceptEula -s -h -n 10 cmd /c winrm quickconfig -q -force"
                    $T = New-ScheduledTaskTrigger -AtStartup
                    $S = New-ScheduledTaskSettingsSet
                    $D = New-ScheduledTask -Action $A -Trigger $T -Settings $S
                    
                    $task=Register-ScheduledTask "winrm quickconfig" -InputObject $D -Password $mypwd -User $($env:computername+"\"+$myuser) -Force
                
                    write-host -f green "$($task.TaskName) is $($task.State) to run AtStartup"

                     }catch{
                        
                         throw $error[0]
                        

                    }
                }
    
                get-WinRMStatus  $($AzureIp) -waitfor -creds $LocalCreds
                $ret= invoke-command -computername $AzureIp -ScriptBlock $PrepareScript -Credential $LocalCreds -ArgumentList $strSid,$LocalCreds.UserName,$($LocalCreds.GetNetworkCredential().Password) -SessionOption (New-PsSessionOption -SkipCACheck -SkipCNCheck)
                $ret                

          	 } catch{
                write-host -f red $error[0]
                return $false
             }

            #only if the above completes succeffully do we want to join the domain.
                if(!$error) { 
		        
                    try {
                           #Get the OU based on DomainName
                           $OU=Get-DomainOu $DomainName
            
                            if($OU -ne 'Other'){

                               Write-host -f Gray  "Joining computer to the '$($DomainName)' domain in the ITManaged OU..."
    		                    Add-Computer -ComputerName $AzureIp -DomainName $DomainName -Credential $DomainCreds -LocalCredential $LocalCreds -OUPath $OU -Restart
                                write-host -f Green "Added $($ServerName + $i) to '$($DomainName)'. ou=$OU "
	                        }
                            else{
            

                                Write-host -f Gray "Joining computer to the '$($DomainName)' domain in the default OU..."
    		                    Add-Computer -ComputerName $AzureIp -DomainName $DomainName -Credential $DomainCreds -LocalCredential $LocalCreds -Restart
                                write-host -f Green "Added $($ServerName + $i) to '$($DomainName)'. "
                            }	  
            
                        } catch {
                            write-host -f red $error[0]
                            $error.Clear()
                            Return $false
                        }
                } else {
                    write-host -f red $error[0]
                    $error.Clear()
                    Return $false
                }

            } else {
             write-host -f Green "$($ServerName + $i) is  Domain Joined. "
            }         

            Write-host -f Gray "Begin VM Health check in 2 min..."
            #Check VM status, wait until its ready
            try {
                
               start-sleep -Seconds (2*60)

                get-VMBuildStatus $($ServerName + $i) -ResourceGroupName $ResourceGroupName -waitfor  
                get-WinRMStatus  $($AzureIp) -waitfor -creds $DomainCreds
                Write-host -f Green "VM is healthy"

            } catch {
                write-host -f red $error
                Write-host -f red "VM health check Failed"
                Return $false
                $error.Clear()
            }
                       
            if($AzureIp) {
               Write-host -f Gray "Begin VM Configuration"
               get-WinRMStatus  $($AzureIp) -waitfor -creds $DomainCreds
               Write-host -f Gray  'Configure Virtual machine'
               $InstallResults= invoke-command -ComputerName $AzureIp -ScriptBlock $VMConfiguration -Credential $DomainCreds -SessionOption (New-PsSessionOption -SkipCACheck -SkipCNCheck)
               Write-host -f Green "VM Construction Complete"            
            }

            if($error) {
                write-host -f red $error
                write-host -f red "Stopping due to errors"
                $error.Clear()
                return $false
            }

            if($JsonParams.parameters.additionalAdmins.value.length -gt 0) {
                                          
                Write-host -f Gray  'Adding Additional Admins'
               
                Add-AdditionalAdmins -computername $AzureIp -UserAccounts $JsonParams.parameters.additionalAdmins.value -creds $DomainCreds 
               
                write-host -f Green "Adding Additional Admin is Completed. "                

            }

           
            if(!$error) {
               
                write-host -f Green "$($ServerName + $i) is Completed Sucessfully. "
             

            }else {
                write-host -f red "Stopping due to errors"
                $error.Clear()
                return $false
            }
       }
}


 $params = @{
                   "TemplateFile"="template.json"; 
                   "TemplateParameterFile"="templateParam.json"; 
                   "SubscriptionId"="e4a74065-cc6c-4f56-b451-f07a3fde61de"; 
                   "ResourceGroupLocation"="central us"; 
                   "ResourceGroupName"="cptApp1";
                   
                  }

deploy -TemplateFile $params.TemplateFile `
       -SubscriptionId $params.SubscriptionId `
       -ResourceGroupLocation $params.ResourceGroupLocation `
       -ResourceGroupName $params.ResourceGroupName `
       -PromptToContinue