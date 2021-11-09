# Script to check the password expiry of VMware Cloud Foundation Credentials
# Written by Brian O'Connell - VMware

#User Variables
$sddcManagerFQDN = "sfo-vcf01.sfo.rainpole.io"
$sddcManagerAdminUser = "administrator@vsphere.local"
$sddcManagerAdminPassword = "VMw@re1!"

# Requires PowerVCF Module
#Requires -Module PowerVCF

Function Get-VCFPasswordExpiry
{
<#
		.SYNOPSIS
    	Gets expiry of VMware Cloud Foundation credentials

    	.DESCRIPTION
    	The Get-VCFPasswordExpiry gets expiry of VMware Cloud Foundation credentials

    	.EXAMPLE
    	Get-VCFPasswordExpiry -fqdn $sddcManagerFQDN -username $sddcManagerAdminUser -password $sddcManagerAdminPassword
        This example gets expiry of every VMware Cloud Foundation credential
        
       .EXAMPLE
    	Get-VCFPasswordExpiry -fqdn $sddcManagerFQDN -username $sddcManagerAdminUser -password $sddcManagerAdminPassword -resourceType VCENTER
        This example gets expiry of every VMware Cloud Foundation VCENTER credential
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateSet("VCENTER", "PSC", "ESXI", "BACKUP", "NSXT_MANAGER", "NSXT_EDGE", "VRSLCM", "WSA", "VROPS", "VRLI", "VRA", "VXRAIL_MANAGER")] [ValidateNotNullOrEmpty()] [String]$resourceType
    )
# Request an SDDC manager Token
Request-VCFToken -fqdn $fqdn -username $username -password $password
# Build the required headers
$credentialheaders = @{"Content-Type" = "application/json"}
$credentialheaders.Add("Authorization", "Bearer $accessToken")
# Get all credential objects that are not type SERVICE
if (!$PsBoundParameters.ContainsKey("resourceType")) {
$credentials = Get-VCFCredential | where-object {$_.accountType -ne "SERVICE"}
}
else {
    $credentials = Get-VCFCredential -resourceType $resourceType | where-object {$_.accountType -ne "SERVICE"}
}
$validationArray = @()
Foreach ($credential in $credentials) {
    $resourceType = $credential.resource.resourceType
    $resourceID = $credential.resource.resourceId
    $username = $credential.username
    $credentialType = $credential.credentialType
    $body = '[
    {
        "resourceType": "'+$resourceType+'",
        "resourceId": "'+$resourceID+'",
        "credentials": [
            {
                "username": "'+$username+'",
                "credentialType": "'+$credentialType+'"
            }
        ]
    }
]'
    $uri = "https://$sddcManagerFQDN/v1/credentials/validations"
    # Submit a credential validation request
            $response = Invoke-RestMethod -Method POST -URI $uri -headers $credentialheaders -body $body
            $validationTaskId = $response.id

            Do {
                # Keep checking until executionStatus is not IN_PROGRESS
                $validationTaskuri = "https://$sddcManagerFQDN/v1/credentials/validations/$validationTaskId"
                $validationTaskResponse = Invoke-RestMethod -Method GET -URI $validationTaskuri -headers $credentialheaders
            }
            While ($validationTaskResponse.executionStatus -eq "IN_PROGRESS")
            # Build the output
            $validationObject = New-Object -TypeName psobject
            $validationObject | Add-Member -notepropertyname 'Resource Name' -notepropertyvalue $validationTaskResponse.validationChecks.resourceName
            $validationObject | Add-Member -notepropertyname 'Username' -notepropertyvalue $validationTaskResponse.validationChecks.username
            $validationObject | Add-Member -notepropertyname 'Number Of Days To Expiry' -notepropertyvalue $validationTaskResponse.validationChecks.passwordDetails.numberOfDaysToExpiry
            
            Write-Output "Checking Password Expiry for username $($validationTaskResponse.validationChecks.username) from resource $($validationTaskResponse.validationChecks.resourceName)"
            # Add each credential result to the array
            $validationArray += $validationObject
           #break
}
# Print the array
$validationArray
}
