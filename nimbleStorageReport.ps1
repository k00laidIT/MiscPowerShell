#Requires -Version 5
#Requires -Module HPENimblePowershellToolkit

<#
.Synopsis
  Generates report of nimble storage utilization based on the $nimbles list of devices. This can be in FQDN or IP form.
.Notes
   Version: 1.0
   Author: Jim Jones
   Modified Date: 8/21/2020

   This script uses stored credentials for scheduled running. If running for the first time a new computer You will need to run to store the credentials
    $credpath='c:\users\jim\creds\myadmincred.xml'
    GET-CREDENTIAL –Credential (Get-Credential) | EXPORT-CLIXML $credpath
.EXAMPLE
  .\nimblereport.ps1 -authpath "c:\creds\nimble.xml"
#>

[CmdletBinding()]
Param (    
    [string]$authPath = 'C:\creds\nimble.xml'
)

#Email Variables
$date = Get-Date
$sgToken        = "SendGridToken"
$fromAddress    = "myvac@mydomain.com"
$fromName       = "US VAC"
$toName         = "NetOps"
$toAddress      = "me@me.com"

#Provide authentication file
$creds = IMPORT-CLIXML -path $authpath

#Specify path to list of nimble arrays. This should be a standard text file, 1 per line.
$arraypath = ".\nimble.txt"
$nimbles = Get-Content -Path $arraypath

[System.Collections.ArrayList]$AllArrayInfo = @()
[System.Collections.ArrayList]$AllVolumeInfo = @()
foreach($nimble in $nimbles) {
    Connect-NSGroup $nimble -Credential $creds -IgnoreServerCertificate
    
    #Get general Array information
    $arrayinfo = Get-NSArray | Select-Object name, model, serial, `
        @{Name="CapacityTB";Expression={[math]::round($_.usable_capacity_bytes / 1Tb, 2)}}, `
        @{Name="UsedSpaceTB";Expression={[math]::round($_.usage / 1Tb, 2)}}, `
        @{Name="FreeSpaceTB";Expression={[math]::round(($_.usable_capacity_bytes-$_.usage) / 1Tb, 2)}}, `
        @{Name="SnapUsageTB";Expression={[math]::round($_.snap_usage_bytes / 1Tb, 2)}}, `
        @{Name="PercentFree";Expression={(($_.usable_capacity_bytes-$_.usage)/$_.usable_capacity_bytes).tostring("P")}}        
    
    $null = $AllArrayInfo.Add($arrayinfo)

    #Get Volume Information
    $volumes = Get-NSVolume
    foreach($volume in $volumes) {
        $volumeinfo = Get-NSVolume -Name $volume.name | Select-Object @{Name="Array";Expression={$nimble}},name, app_category, `
            @{Name="SizeTB";Expression={[math]::round(($_.size*1024*1024) / 1Tb, 2)}}, `
            @{Name="CompressedUsageTB";Expression={[math]::round($_.vol_usage_compressed_bytes / 1Tb, 2)}}, `
            @{Name="FreeSpaceBytes";Expression={[math]::round((($_.size*1024*1024)-$_.vol_usage_compressed_bytes) / 1Tb, 2)}}, `
            @{Name="PercentFree";Expression={((($_.size*1024*1024)-$_.vol_usage_compressed_bytes)/($_.size*1024*1024)).tostring("P")}}                    
        $null = $AllVolumeInfo.Add($volumeinfo)
    }    
}

$AllArrayInfo | Sort-Object -Property "PercentFree" | Export-Csv -Path ".\ArrayInfo.csv" -NoTypeInformation
$AllVolumeInfo | Sort-Object -Property "PercentFree" | Export-Csv -Path ".\VolumeInfo.csv" -NoTypeInformation

#Send Mail
Import-Module PSSendGrid

$arrayParameters = @{
    FromAddress = $fromAddress
    ToAddress   = $toAddress 
    Subject     = "Nimble Storage Array Information Report for $date"
    Body        = "See attached Nimble Storage Array Information Report for $date"
    Token       = $sgToken
    FromName    = $fromName
    ToName      = $toName 
    AttachmentPath        = ".\ArrayInfo.csv"
}
Send-PSSendGridMail @arrayParameters

$volumeParameters = @{
    FromAddress = $fromAddress
    ToAddress   = $toAddress 
    Subject     = "Nimble Storage Volume Usage Report for $date"
    Body        = "See attached Nimble Storage Volume Usage Report for $date"
    Token       = $sgToken
    FromName    = $fromName
    ToName      = $toName 
    AttachmentPath        = ".\VolumeInfo.csv"
}
Send-PSSendGridMail @volumeParameters
