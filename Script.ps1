# Variables
$ResourceGroup = "homework2-rg"
$KeyVault = "Paaswords-for-homework"
$AppID = "b6471310-a4dc-4324-8b9d-264efad9022f"
$TenantID = "7e1792ae-4f1a-4ff7-b80b-57b69beb7168"

$Credential = Get-Credential -Message "Please Enter Password:" -username $AppID
Connect-AzAccount -Credential $Credential -Tenant $TenantID -ServicePrincipal
