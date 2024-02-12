#1. Load in csv file for employees

function Get-EmployeeFromCsv{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$Delimiter,
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap
    )

    try{
        $SyncProperties=$SyncFieldMap.GetEnumerator()
        $Properties=ForEach($Property in $SyncProperties){
            @{Name=$Property.Value;Expression=[scriptblock]::Create("`$_.$($Property.Key)")}
        }
    
        Import-Csv -Path $FilePath -Delimiter $Delimiter | Select-Object -Property $Properties
    }catch{
        Write-Error $_.Exception.Message
    }
}

#2.  Load in employees already in AD
function Get-EmployeesFromAD{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$UniqueID

    )

    try{
        Get-ADUser -Filter {$UniqueID -like "*"} -Server $Domain -Properties @($SyncFieldMap.Values)

    }catch{
        Write-Error -Message $_.Exception.Message
    }
}

Get-EmployeesFromAD -SyncFieldMap $SyncFieldMap -UniqueID $UniqueId -Domain "hp.com"

#3. Compare those.

function Compare-Users{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$UniqueID,
        [Parameter(Mandatory)]
        [string]$CsvFilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$Domain
    )

    $CSVUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap
    $ADUsers=Get-EmployeesFromAD -SyncFieldMap $SyncFieldMap -UniqueID $UniqueId -Domain $Domain
    
    Compare-Object -ReferenceObject $ADUsers -DifferenceObject $CSVUsers -Property $UniqueId -IncludeEqual
}

#Get the new users
#Get the synced users
#Get removed users

function Get-UserSyncData{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$UniqueID,
        [Parameter(Mandatory)]
        [string]$CsvFilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$OUProperty
        

    )

    try{
        $CompareData=Compare-Users -SyncFieldMap $SyncFieldMap -UniqueID $UniqueId -CsvFilePath $CsvFilePath -Delimiter $Delimiter -Domain $Domain

        $NewUsersID=$CompareData | where SideIndicator -eq "=>"
        $SyncedUsersID=$CompareData | where SideIndicator -eq "=="
        $RemovedUsersID=$CompareData | where SideIndicator -eq "<="

        $NewUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap | where $UniqueId -In $NewUsersID.$UniqueId
        $SyncedUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap | where $UniqueId -In $SyncedUsersID.$UniqueId
        $RemovedUsers=Get-EmployeesFromAD -SyncFieldMap $SyncFieldMap -Domain $Domain -UniqueID $UniqueId | where $UniqueId -In $RemovedUsersID.$UniqueId

        @{
            New=$NewUsers
            Synced=$SyncedUsers
            Removed=$RemovedUsers
            Domain=$Domain
            UniquieID=$UniqueID
            OUProperty=$OUProperty
        }
    }catch{
            Write-Error $_.Exception.Message
    }
}

function New-UserName{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GivenName,
        [Parameter(Mandatory)]
        [string]$Surname,
        [Parameter(Mandatory)]
        [string]$Domain
    )

    [regex]$Pattern="\s|-|'"
    $index=1

    do{
        $Username="$SurName$($GivenName.Substring(0,$index))" -replace $Pattern,""
        $index++ #the 2nd part is because otherwise if the first name isn't long enough it can't loop through enough to call the substring again
    }while((Get-AdUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike "$Surname$GivenName"))

    if(Get-AdUser -Filter "SamAccountName -like '$Username'" -Server $Domain){
        throw "No usernames available for this user!"
    }else{
        $Username
    }
}

function Validate-OU{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$CsvFilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter()]
        [string]$OUProperty
    )

    try{
    $OUNames=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter "," -SyncFieldMap $SyncFieldMap `
    | select -Unique -Property $OUProperty

    foreach($OUName in $OUNames){
        $OUName=$OUName.$OUProperty
        if(-not (Get-ADOrganizationalUnit -Filter "name -eq '$OUName'" -Server $Domain)){
            New-ADOrganizationalUnit -Name $OUName -Server $Domain -ProtectedFromAccidentalDeletion $false
         }
      }
    }catch{
      Write-Error -Message $_.Exception.Message
    }
}

function Check-UserName{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GivenName,
        [Parameter(Mandatory)]
        [string]$Surname,
        [Parameter(Mandatory)]
        [string]$CurrentUserName,
        [Parameter(Mandatory)]
        [string]$Domain
    )

    [regex]$Pattern="\s|-|'"
    $index=1

    do{
        $Username="$SurName$($GivenName.Substring(0,$index))" -replace $Pattern,""
        $index++ #the 2nd part is because otherwise if the first name isn't long enough it can't loop through enough to call the substring again
    }while((Get-AdUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike "$Surname$GivenName") -and ($Username -notlike $CurrentUserName))

    if((Get-AdUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike $CurrentUserName)){
        throw "No usernames available for this user!"
    }else{
        $Username
    }
}
#Check if new users then create
    #needs a username, username needs to be unique
    #placing a user in an OU

function Create-NewUser{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$UserSyncData
    )
    try{
    $NewUsers=$UserSyncData.New

    foreach($NewUser in $NewUsers){
        Write-Verbose "Creating user : {$($NewUser.GivenName) $($NewUser.SurName)}"
        $Username=New-UserName -GivenName $NewUser.GivenName -Surname $NewUser.SurName -Domain $UserSyncData.Domain
        Write-Verbose "Creating user : {$($NewUser.GivenName) $($NewUser.SurName)} with username : {$Username}"

        if(-not ($OU=Get-ADOrganizationalUnit -Filter "name -eq '$($NewUser.$($UserSyncData.OUProperty))'" -Server $UserSyncData.Domain)){
            throw "The organizational unit for {$($NewUser.($UserSyncData.OUProperty))}"
         }
         Write-Verbose "Creating user : {$($NewUser.GivenName) $($NewUser.SurName)} with username : {$Username}, {$OU)}"

         Add-Type -AssemblyName 'System.Web'
         $Password=[System.Web.Security.Membership]::GeneratePassword((Get-Random -Minimum 12 -Maximum 16),4)
         $SecuredPassword=ConvertTo-SecureString -String $Password -AsPlainText -Force

         $NewADUserParams=@{
            EmployeeID=$NewUser.EmployeeID
            GivenName=$NewUser.GivenName
            SurName=$NewUser.SurName
            Name=$Username
            SamAccountName=$Username
            UserPrincipalName="$username@$($UserSyncData.Domain)"
            AccountPassword=$SecuredPassword
            ChangePasswordAtLogon=$true
            Enabled=$true
            Title=$NewUser.Title
            Department=$NewUser.Department
            Office=$NewUser.Office
            Path=$OU.DistinguishedName
            Confirm=$false
            Server=$UserSyncData.Domain

         }
         New-ADUser @NewADUserParams
         Write-Verbose "Created user : {$($NewUser.GivenName) $($NewUser.SurName)} EmpID: {$($NewUser.EmployeeID) Username : {$Username} Password : {$Password}}"
        }
    }catch{
        Write-Error $_.Exception.Message
    }
}



#check synced users
    #Check username
    #Change OUs 
    #Udpate any other fields, position, office

#check removed users, then disable them


$SyncFieldMap=@{
    EmployeeID="EmployeeID"
    FirstName="GivenName"
    LastName="SurName"
    Title="Title"
    Department="Department"
    Office="Office"    
}

$CsvFilePath="C:\Users\Administrator\Documents\PowerShell Project\Employees.csv"
$Delimiter=","
$Domain="hp.com"
$UniqueId="EmployeeID"
$OUProperty="Office"

Validate-OU -SyncFieldMap $SyncFieldMap -CsvFilePath $CsvFilePath `
-Delimiter $Delimiter -Domain $Domain -OUProperty $OUProperty

$UserSyncData=Get-UserSyncData -SyncFieldMap $SyncFieldMap -UniqueID $UniqueId `
-CsvFilePath $CsvFilePath -Delimiter $Delimiter -Domain $Domain -OUProperty $OUProperty

Create-NewUser -UserSyncData $UserSyncData -Verbose

Check-UserName -GivenName "Melissa" -Surname "Ballard" -CurrentUserName "AndersonR" -Domain "hp.com"


