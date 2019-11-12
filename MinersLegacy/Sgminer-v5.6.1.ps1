﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject[]]$Devices
)

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\$($Name)\sgminer.exe"
$HashSHA256 = "7A29E1280898D049BEE35B1CE4A6F05A7B3A3219AC805EA51BEFD8B9AFDE7D85"
$Uri = "https://github.com/nicehash/sgminer/releases/download/5.6.1/sgminer-5.6.1-nicehash-51-windows-amd64.zip"
$ManualUri = "https://github.com/nicehash/sgminer"

$Miner_BaseName = $Name -split '-' | Select-Object -Index 0
$Miner_Version = $Name -split '-' | Select-Object -Index 1
$Miner_Config = $Config.MinersLegacy.$Miner_BaseName.$Miner_Version
if (-not $Miner_Config) {$Miner_Config = $Config.MinersLegacy.$Miner_BaseName."*"}

$Commands = [PSCustomObject]@{
    "yescrypt"     = " --kernel yescrypt --worksize 4 --rawintensity 256" #Yescrypt

    # Unprofitable algirithms as of 09/08/2019
    #"groestlcoin"  = " --kernel groestlcoin --gpu-threads 2 --worksize 128 --intensity d" #Groestl
    #"lbry"         = " --kernel lbry" #Lbry
    #"lyra2rev2"    = " --kernel lyra2rev2 --gpu-threads 2 --worksize 128 --intensity d" #Lyra2RE2
    #"neoscrypt"    = " --kernel neoscrypt --gpu-threads 1 --worksize 64 --intensity 15" #NeoScrypt, broken
    #"sibcoin-mod"  = " --kernel sibcoin-mod" #Sib
    #"skein"        = " --kernel skein --gpu-threads 2 --worksize 256 --intensity d" #Skein

    # ASIC - never profitable 23/05/2018    
    #"blake2s"     = "" #Blake2s
    #"blake"       = "" #Blakecoin
    #"cryptonight" = " --gpu-threads 1 --worksize 8 --rawintensity 896" #CryptoNight
    #"decred"      = "" #Decred
    #"lbry"        = "" #Lbry
    #"maxcoin"     = "" #Keccak
    #"myriadcoin-groestl" = " --gpu-threads 2 --worksize 64 --intensity d" #MyriadGroestl
    #"nist5"       = "" #Nist5
    #"pascal"      = "" #Pascal
    #"vanilla"     = " --intensity d" #BlakeVanilla
}
#Commands from config file take precedence
if ($Miner_Config.Commands) {$Miner_Config.Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {$Commands | Add-Member $_ $($Miner_Config.Commands.$_) -Force}}

#CommonCommands from config file take precedence
if ($Miner_Config.CommonCommands) {$CommonCommands = $Miner_Config.CommonCommands}
else {$CommonCommands = " $(if (-not $Config.ShowMinerWindow) {' --text-only'})"}

$Devices = @($Devices | Where-Object Type -EQ "GPU" | Where-Object Vendor -EQ "AMD")
$Devices | Select-Object Model -Unique | ForEach-Object {
    $Miner_Device = @($Devices | Where-Object Model -EQ $_.Model)
    $Miner_Port = $Config.APIPort + ($Miner_Device | Select-Object -First 1 -ExpandProperty Id) + 1

    $Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {$Algorithm_Norm = Get-Algorithm $_; $_} | Where-Object {$Pools.$Algorithm_Norm.Protocol -eq "stratum+tcp" <#temp fix#>} | ForEach-Object {
        $Miner_Name = (@($Name) + @($Miner_Device.Model | Sort-Object -unique | ForEach-Object {$Model = $_; "$(@($Miner_Device | Where-Object Model -eq $Model).Count)x$Model"}) | Select-Object) -join '-'

        #Get commands for active miner devices
        $Command = Get-CommandPerDevice -Command $Commands.$_ -ExcludeParameters @("algorithm", "k", "kernel") -DeviceIDs $Miner_Device.Type_Vendor_Index

        #Allow time to build binaries
        if (-not (Get-Stat "$($Miner_Name)_$($Algorithm_Norm)_HashRate")) {$WarmupTime = 90} else {$WarmupTime = 30}

        [PSCustomObject]@{
            Name        = $Miner_Name
            BaseName    = $Miner_BaseName
            Version     = $Miner_Version
            DeviceName  = $Miner_Device.Name
            Path        = $Path
            HashSHA256  = $HashSHA256
            Arguments   = ("$Command$CommonCommands --api-listen --api-port $Miner_Port --url $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) --user $($Pools.$Algorithm_Norm.User) --pass $($Pools.$Algorithm_Norm.Pass) --gpu-platform $($Miner_Device.PlatformId | Sort-Object -Unique) --device $(($Miner_Device | ForEach-Object {'{0:x}' -f $_.Type_Vendor_Index}) -join ',')" -replace "\s+", " ").trim()
            HashRates   = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
            API         = "Xgminer"
            Port        = $Miner_Port
            URI         = $Uri
            Environment = @("GPU_FORCE_64BIT_PTR=0")
            WarmupTime  = $WarmupTime #seconds
        }
    }
}
