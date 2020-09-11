using namespace System.Net

#Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

#region Catch Block code
function Catch-Block {
    Param($Message)
    Write-Warning "Failed trying to do: $Message"
    Write-Warning "Exception is probably $($_.exception)"
    Write-Warning "If not run `$error[0] | Format-List -Force to find out"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = '{"status":"unsuccessful","message":"Failed at step: ' + $Message + '", "exception":"' + $_.exception + '"}'
    })
    exit
}
#endregion

#region Get-PR-Exists
function Get-PR-Exists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
                   Position=0,
                   ValueFromPipeline=$true,
                   HelpMessage="Azure DevOps Organization name")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $organization,
        [Parameter(Mandatory=$true,
                Position=1,
                ValueFromPipeline=$true,
                HelpMessage="Azure DevOps project name")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $project,
        [Parameter(Mandatory=$true,
                Position=2,
                ValueFromPipeline=$true,
                HelpMessage="Azure DevOps PAT")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $pat,
        [Parameter(Mandatory=$true,
                Position=3,
                ValueFromPipeline=$true,
                HelpMessage="Source refname")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $sourcerefname,
        [Parameter(Mandatory=$true,
                Position=4,
                ValueFromPipeline=$true,
                HelpMessage="Repository ID")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $repo
    )

    $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($pat)"))
    $header = @{authorization = "Basic $token"}

    try {
        $msg = "Query api to see if pr already exists"
        Write-Information $msg
        
        $apiPath = "https://dev.azure.com/" + $organization + "/" + $project + "/_apis/git/repositories/"
        Write-Information $apiPath
        $Uri = $($apiPath) + $($repo) + '/pullrequests?searchCriteria.sourceRefName='+ $($sourcerefname) + '&searchCriteria.targetRefName=refs/heads/master&searchCriteria.status=active&api-version=5.1'
        Write-Information $Uri
        $pullrequest = Invoke-RestMethod -Uri $Uri -Method 'GET' -ContentType 'application/json' -Headers $header
        Write-Information "There is a $($pullrequest) that exists in our system"
        Return $pullrequest
    }
    catch {
        Catch-Block -Message $msg
    }
}
#endregion

#region Create-PR
function Create-PR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
                   Position=0,
                   ValueFromPipeline=$true,
                   HelpMessage="Azure DevOps Organization name")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $organization,
        [Parameter(Mandatory=$true,
                Position=1,
                ValueFromPipeline=$true,
                HelpMessage="Azure DevOps project name")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $project,
        [Parameter(Mandatory=$true,
                Position=2,
                ValueFromPipeline=$true,
                HelpMessage="Azure DevOps PAT")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $pat,
        [Parameter(Mandatory=$true,
                Position=3,
                ValueFromPipeline=$true,
                HelpMessage="Source refname")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $sourcerefname,
        [Parameter(Mandatory=$true,
                Position=4,
                ValueFromPipeline=$true,
                HelpMessage="Repository ID")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $repo
    )

    $apiPath = "https://dev.azure.com/" + $organization + "/" + $project + "/_apis/git/repositories/"

    $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($pat)"))
    $header = @{authorization = "Basic $token"}
    
    $body= @{
        "sourceRefName" = $($sourcerefname)
        "targetRefName" = "refs/heads/master"
        "title" = "Release Feature"
        "description" = "Release Feature"
        "AutoCompleteSetBy.Id" = "e5daca38-2a40-6943-9891-84cf28dfff12"
        } | ConvertTo-Json    

    try {
        $msg = "Creating the following PR:"
        Write-Information $msg
        $apiPath = "https://dev.azure.com/" + $organization + "/" + $project + "/_apis/git/repositories/"
        Write-Information $apiPath
        $Uri = $($apiPath) + $($repo) + '/pullrequests?api-version=5.1'
        Write-Information $Uri
        $createdpullrequest = Invoke-RestMethod -Uri $Uri -Method 'POST' -ContentType 'application/json' -Body $body -Headers $header
        Write-Information "$($createdpullrequest) has now been created in the system"
        Return $createdpullrequest

    }
    catch {
        Catch-Block -Message $msg
    }
}
#EndRegion

# Write to the Azure Functions log stream.
Write-Information "PowerShell HTTP trigger function processed a request."

# Validate call
$pat = $Request.Body.pat
$project = $Request.Body.project
$organization = $Request.Body.organization
$sourcerefname = $Request.Body.sourcerefname
$repo = $Request.Body.repo

Write-Information $pat
Write-Information $project 
Write-Information $organization
Write-Information $sourcerefname 
Write-Information $repo 

if (-not $pat -or -not $project -or -not $organization -or -not $sourcerefname -or -not $repo){
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = '{"status":"unsuccessful","message":"Please provide body values for pat, project, organization, source and repository ID}'
    })
    exit
}

#---------------------------------------------------------------------------

$output = New-Object -TypeName psobject 
Add-Member -InputObject $output -MemberType NoteProperty -Name 'organization' -Value $organization
Add-Member -InputObject $output -MemberType NoteProperty -Name 'project' -Value $project
Add-Member -InputObject $output -MemberType NoteProperty -Name 'sourcerefname' -Value $sourcerefname
Add-Member -InputObject $output -MemberType NoteProperty -Name 'repo' -Value $repo

try {
        $msg = 'Checking existing PR'
        $pullrequestdata = Get-PR-Exists -organization $organization -project $project -pat $pat -sourcerefname $sourcerefname -repo $repo
    }
    catch {
        Catch-Block -Message $msg
    }
    
$taskOut = New-Object -TypeName psobject

if ($pullrequestdata.value.count -eq 0) {
    Write-Information "There isn't a pull request in the system creating one"
    Add-Member -InputObject $taskOut -MemberType NoteProperty -Name 'NoPR' -Value $True
    }

Write-Information $taskOut.NoPR

if ($taskOut.NoPR -eq $True) {
    Write-Information "Creating a PR"
    $pullrequestdata = Create-PR -organization $organization -project $project -pat $pat -sourcerefname $sourcerefname -repo $repo
}

Add-Member -InputObject $output -MemberType NoteProperty -Name 'pullrequest' -Value $pullrequestdata

#---------------------------------------------------------------------------
##IF reviewers $status [HttpStatusCode]::BADREQUEST
$status = [HttpStatusCode]::OK
Add-Member -InputObject $output -MemberType NoteProperty -Name 'status' -Value 'successful'

#Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $output | ConvertTo-Json
})

