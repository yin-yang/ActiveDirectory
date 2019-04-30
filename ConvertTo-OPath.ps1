# Powershell script to convert LDAP filter (purportedSearch) to OPATH filter  
#  
################################################################################# 
#  
# This script is not officially supported by Microsoft, use it at your own risk.  
# Microsoft has no liability, obligations, warranty, or responsibility regarding  
# any result produced by use of this file. 
# 
################################################################################# 
# 
# Examples on ways to use this script in Powershell... 
#  
# To convert a manually entered filter and display the result: 
#  
# .\ConvertFrom-LdapFilter "(&(mailnickname=*))" 
#  
# To convert the LDAP filter on an existing address list and display the result: 
#  
# .\ConvertFrom-LdapFilter (Get-AddressList "My Address List").LdapRecipientFilter 
#  
# To convert the LDAP filter on an existing address list and update the address list with the new filter: 
#  
# Set-AddressList "My Address List" -RecipientFilter ( .\ConvertFrom-LdapFilter (Get-AddressList "My Address List").LdapRecipientFilter ) 
#  
# To convert all existing legacy address lists and display the result without actually updating them: 
#  
# Get-AddressList | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { .\ConvertFrom-LdapFilter $_.LdapRecipientFilter } 
#  
# To convert all existing legacy address lists and output the name, current LDAP filter, and the generated OPATH to a tab-delimited file without actually updating the address lists: 
#  
# Get-AddressList | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { $_.Name + [char]9 + $_.LdapRecipientFilter + [char]9 + (.\ConvertFrom-LdapFilter $_.LdapRecipientFilter) } > C:\suggestedfilters.txt 
#  
# To convert all existing legacy address lists and actually update the address lists without prompting: 
#  
# Get-AddressList | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { Set-AddressList $_.Name -RecipientFilter (.\ConvertFrom-LdapFilter $_.LdapRecipientFilter) -ForceUpgrade } 
#  
# To convert all legacy address lists, GALs, and email address policies, without prompting, run three commands: 
#  
# Get-AddressList | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { Set-AddressList $_.Name -RecipientFilter (.\ConvertFrom-LdapFilter $_.LdapRecipientFilter) -ForceUpgrade } 
# Get-GlobalAddressList | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { Set-GlobalAddressList $_.Name -RecipientFilter (.\ConvertFrom-LdapFilter $_.LdapRecipientFilter) -ForceUpgrade } 
# Get-EmailAddressPolicy | WHERE { $_.RecipientFilterType -eq 'Legacy' } | foreach { Set-EmailAddressPolicy $_.Name -RecipientFilter (.\ConvertFrom-LdapFilter $_.LdapRecipientFilter) -ForceUpgrade } 
#  
trap { 
    write-host $_.Exception.Message -fore Red 
    continue 
} 
 
function convert-filter { 
    $output = BuildFilterFromString 
    return $output 
 
} 
 
function BuildFilterFromString { 
    $script:filterString = $script:filterString.Trim() 
    [string[]]$conditions = GetConditionsFromString 
    if ($conditions.Length -gt 1) { 
        throw "Invalid filter string." 
    } 
     
    return $conditions 
} 
 
function GetConditionsFromString { 
    $script:filterString = $script:filterString.Trim() 
    $exitThisLevel = $false; 
         
    while (!($exitThisLevel)) { 
        # Special cases for default filters 
        # This is so that we match the ones given on the msexchangeteam.com blog 
        if ($script:filterString.StartsWith("(&(objectClass=user)(objectCategory=person)(mailNickname=*)(msExchHomeServerName=*))")) {
            # All Users 
            $script:filterString = $script:filterString.Remove(0, 83).Trim() 
            return "RecipientType -eq 'UserMailbox'" 
        } 
        if ($script:filterString.StartsWith("(& (mailnickname=*) (| (objectCategory=group) ))")) {
            # All Groups 
            $script:filterString = $script:filterString.Remove(0, 47).Trim() 
            return "( RecipientType -eq 'MailUniversalDistributionGroup' -or RecipientType -eq 'MailUniversalSecurityGroup' -or RecipientType -eq 'MailNonUniversalGroup' -or RecipientType -eq 'DynamicDistributionGroup' )" 
        } 
        if ($script:filterString.StartsWith("(& (mailnickname=*) (| (&(objectCategory=person)(objectClass=contact)) ))")) {
            # All Contacts 
            $script:filterString = $script:filterString.Remove(0, 72).Trim() 
            return "RecipientType -eq 'MailContact'" 
        } 
        if ($script:filterString.StartsWith("(& (mailnickname=*) (| (objectCategory=publicFolder) ))")) {
            # Public Folders 
            $script:filterString = $script:filterString.Remove(0, 54).Trim() 
            return "RecipientType -eq 'PublicFolder'" 
        } 
        if ($script:filterString.StartsWith("(& (mailnickname=*) (| (&(objectCategory=person)(objectClass=user)(!(homeMDB=*))(!(msExchHomeServerName=*)))(&(objectCategory=person)(objectClass=user)(|(homeMDB=*)(msExchHomeServerName=*)))(&(objectCategory=person)(objectClass=contact))(objectCategory=group)(objectCategory=publicFolder)(objectCategory=msExchDynamicDistributionList) ))")) {
            # Default Global Address List 
            $script:filterString = $script:filterString.Remove(0, 336).Trim() 
            return "( Alias -ne `$null -and (ObjectClass -eq 'user' -or ObjectClass -eq 'contact' -or ObjectClass -eq 'msExchSystemMailbox' -or ObjectClass -eq 'msExchDynamicDistributionList' -or ObjectClass -eq 'group' -or ObjectClass -eq 'publicFolder') )" 
        } 
        # End of default filter cases 
 
        if ($script:filterString.StartsWith("(")) { 
            $script:filterString = $script:filterString.Remove(0, 1).Trim() 
        } 
        else { 
            throw "Invalid filter string." 
        } 
         
        if ($script:filterString.StartsWith("(")) { 
            GetConditionsFromString 
        } 
        else { 
            $isNegative = $script:filterString.StartsWith("!") 
            $mustBeValueComparison = $false 
            if ($isNegative) { 
                $script:filterString = $script:filterString.Remove(0, 1).Trim() 
                if ($script:filterString.StartsWith("(")) { 
                    $script:filterString = $script:filterString.Remove(0, 1).Trim() 
                } 
                else { 
                    $mustBeValueComparison = $true 
                } 
            } 
             
            $op = "" 
            if ($script:filterString.StartsWith("|(homeMDB=*)(msExchHomeServerName=*))")) { 
                $script:filterString = $script:filterString.Remove(0, 36) 
                $newCondition = " ( recipientType -eq 'UserMailbox' )" 
                if ($isNegative) { 
                    $newCondition = " -not (" + $newCondition + " )" 
                } 
                $newCondition 
            } 
            elseif ($script:filterString.StartsWith("&") -or $script:filterString.StartsWith("|")) { 
                if ($mustBeValueComparison) { 
                    throw "Invalid filter string." 
                } 
                if ($script:filterString.StartsWith("&")) { 
                    $op = "and" 
                } 
                else { 
                    $op = "or" 
                } 
                 
                $script:filterString = $script:filterString.Remove(0, 1).Trim() 
                 
                if ($script:filterString.StartsWith("(")) { 
                    [string[]]$theseConditions = GetConditionsFromString 
                     
                    $newCondition = "" 
                    for ([int]$x = 0; $x -lt $theseConditions.Length; $x++) { 
                        $newCondition = $newCondition + $theseConditions[$x] 
                        if (($x + 1) -lt $theseConditions.Count) { 
                            $newCondition = $newCondition + " -" + $op 
                        } 
                    } 
                     
                    if ($isNegative) { 
                        $newCondition = " -not (" + $newCondition + " )" 
                    } 
                    elseif ($theseConditions.Length -gt 1) { 
                        $newCondition = " (" + $newCondition + " )" 
                    } 
                } 
                else { 
                    $newCondition = GetValueComparison 
                } 
 
                $newCondition 
            } 
            else { # this better be a value comparison  
                GetValueComparison 
            } 
             
            if ($isNegative -and -not $mustBeValueComparison) { 
                if ($script:filterString.StartsWith(")")) { 
                    $script:filterString = $script:filterString.Remove(0, 1).Trim() 
                } 
                else { 
                    throw "Invalid filter string." 
                } 
            } 
                 
            if ($script:filterString.StartsWith(")")) { 
                $script:filterString = $script:filterString.Remove(0, 1).Trim() 
            } 
            else { 
                throw "Invalid filter string." 
            } 
        } 
         
        if (($script:filterString.StartsWith(")")) -or ($script:filterString.Length -eq 0)) { 
            $exitThisLevel = $true 
        } 
    } 
     
    return 
} 
 
function GetValueComparison { 
    $operatorPos = $script:filterString.IndexOf("=") 
    $valuePos = $operatorPos + 1 
    if (($script:filterString[$operatorPos - 1] -eq '<') -or 
        ($script:filterString[$operatorPos - 1] -eq '>')) { 
        $operatorPos-- 
    } 
     
    if ($operatorPos -lt 1) { 
        throw "Invalid filter string." 
    } 
     
    $property = $script:filterString.Substring(0, $operatorPos).Trim() 
    $opstring = $script:filterString.Substring($operatorPos, $valuePos - $operatorPos) 
                 
    $startPos = 0 
    # DN-valued attribute may contain parenthesis. Need to look for the end 
    # of the DN. 
    if ($property.ToLower() -eq "homemdb") { 
        if (!($script:filterString[$valuePos] -eq '*')) { 
            $startPos = $script:filterString.IndexOf(",DC=") 
        } 
    } 
    $endPos = $script:filterString.IndexOf(")", $startPos) 
    if ($endPos -lt 0) { 
        throw "Invalid filter string." 
    } 
     
    $val = $script:filterString.Substring($valuePos, $endPos - $valuePos) 
    $script:filterString = $script:filterString.Substring($endPos) 
     
    [string]$compType = "" 
    if ($opstring -eq "=") { 
        if ($val -eq "*") { 
            $compType = "exists" 
        } 
        else { 
            if ($val.IndexOf("*") -gt -1) { 
                $compType = "like" 
            } 
            else { 
                $compType = "equals" 
            } 
        } 
    } 
    elseif ($opstring -eq "<=") { 
        $compType = "lessthanorequals" 
    } 
    elseif ($opstring -eq ">=") { 
        $compType = "greaterthanorequals" 
    } 
    else { 
        throw "Invalid filter string." 
    } 
     
    [string]$opathProp = GetOpathPropFromLdapProp $property 
    [string]$opathVal = GetOpathValFromLdapVal $opathProp $val 
    [string]$opathComparison = GetOpathComparisonFromLdapComparison $opathProp $compType $opathVal 
     
    $newCondition = " ( " + $opathProp + $opathComparison + " )" 
    if ($isNegative) { 
        $newCondition = " -not " + $newCondition 
    } 
         
    $newCondition 
} 
 
function GetOpathComparisonFromLdapComparison([string]$opathProp, [string]$ldapComparison, [string]$opathVal) { 
    if ($opathProp -eq "ObjectCategory" -and $ldapComparison -eq "equals") { 
        return " -like '" + $opathVal + "'" 
    } 
    else { 
        [string]$opathComparison = "" 
     
        if ($ldapComparison -eq "equals") { $opathComparison = " -eq '" } 
        elseif ($ldapComparison -eq "like") { $opathComparison = " -like '" } 
        elseif ($ldapComparison -eq "lessthanorequals") { $opathComparison = " -le '" } 
        elseif ($ldapComparison -eq "greaterthanorequals") { $opathComparison = " -ge '" } 
        elseif ($ldapComparison -eq "exists") { $opathComparison = " -ne `$null" } 
        else { throw "Could not convert unknown comparison type to OPATH comparison." } 
 
        if ($ldapComparison -ne "exists") { 
            $opathComparison = $opathComparison + $opathVal + "'" 
        } 
 
        return $opathComparison 
    } 
} 
 
function GetOpathValFromLdapVal([string]$opathProp, [string]$ldapVal) { 
    if ($opathProp -like "*Enabled") { 
        $newBool = [System.Convert]::ToBoolean($ldapVal) 
        return "$" + $newBool.ToString().ToLower() 
    } 
    else { 
        return $ldapVal 
    } 
} 
 
function GetOpathPropFromLdapProp([string]$ldapProp) { 
    $ldapProp = $ldapProp.ToLower() 
 
    if ($ldapProp -eq "altrecipient") { return "ForwardingAddress" } 
    elseif ($ldapProp -eq "authorig") { return "AcceptMessagesOnlyFrom" } 
    elseif ($ldapProp -eq "c") { return "CountryOrRegion" } 
    elseif ($ldapProp -eq "canonicalname") { return "RawCanonicalName" } 
    elseif ($ldapProp -eq "cn") { return "CommonName" } 
    elseif ($ldapProp -eq "co") { return "Co" } 
    elseif ($ldapProp -eq "company") { return "Company" } 
    elseif ($ldapProp -eq "countrycode") { return "CountryCode" } 
    elseif ($ldapProp -eq "deleteditemflags") { return "DeletedItemFlags" } 
    elseif ($ldapProp -eq "deliverandredirect") { return "DeliverToMailboxAndForward" } 
    elseif ($ldapProp -eq "delivcontlength") { return "MaxReceiveSize" } 
    elseif ($ldapProp -eq "department") { return "Department" } 
    elseif ($ldapProp -eq "description") { return "Description" } 
    elseif ($ldapProp -eq "directreports") { return "DirectReports" } 
    elseif ($ldapProp -eq "displayname") { return "DisplayName" } 
    elseif ($ldapProp -eq "displaynameprintable") { return "SimpleDisplayName" } 
    elseif ($ldapProp -eq "distinguisedname") { return "Id" } 
    elseif ($ldapProp -eq "dlmemrejectperms") { return "RejectMessagesFromDLMembers" } 
    elseif ($ldapProp -eq "dlmemsubmitperms") { return "AcceptMessagesOnlyFromDLMembers" } 
    elseif ($ldapProp -eq "extensionattribute1") { return "customAttribute1" } 
    elseif ($ldapProp -eq "extensionattribute2") { return "customAttribute2" } 
    elseif ($ldapProp -eq "extensionattribute3") { return "customAttribute3" } 
    elseif ($ldapProp -eq "extensionattribute4") { return "customAttribute4" } 
    elseif ($ldapProp -eq "extensionattribute5") { return "customAttribute5" } 
    elseif ($ldapProp -eq "extensionattribute6") { return "customAttribute6" } 
    elseif ($ldapProp -eq "extensionattribute7") { return "customAttribute7" } 
    elseif ($ldapProp -eq "extensionattribute8") { return "customAttribute8" } 
    elseif ($ldapProp -eq "extensionattribute9") { return "customAttribute9" } 
    elseif ($ldapProp -eq "extensionattribute10") { return "customAttribute10" } 
    elseif ($ldapProp -eq "extensionattribute11") { return "customAttribute11" } 
    elseif ($ldapProp -eq "extensionattribute12") { return "customAttribute12" } 
    elseif ($ldapProp -eq "extensionattribute13") { return "customAttribute13" } 
    elseif ($ldapProp -eq "extensionattribute14") { return "customAttribute14" } 
    elseif ($ldapProp -eq "extensionattribute15") { return "customAttribute15" } 
    elseif ($ldapProp -eq "facsimiletelephonenumber") { return "fax" } 
    elseif ($ldapProp -eq "garbagecollperiod") { return "RetainDeletedItemsFor" } 
    elseif ($ldapProp -eq "givenname") { return "FirstName" } 
    elseif ($ldapProp -eq "grouptype") { return "GroupType" } 
    elseif ($ldapProp -eq "objectguid") { return "Guid" } 
    elseif ($ldapProp -eq "hidedlmembership") { return "HiddenGroupMembershipEnabled" } 
    elseif ($ldapProp -eq "homemdb") { return "Database" } 
    elseif ($ldapProp -eq "homemta") { return "HomeMTA" } 
    elseif ($ldapProp -eq "homephone") { return "HomePhone" } 
    elseif ($ldapProp -eq "info") { return "Notes" } 
    elseif ($ldapProp -eq "initials") { return "Initials" } 
    elseif ($ldapProp -eq "internetencoding") { return "InternetEncoding" } 
    elseif ($ldapProp -eq "l") { return "City" } 
    elseif ($ldapProp -eq "legacyexchangedn") { return "LegacyExchangeDN" } 
    elseif ($ldapProp -eq "localeid") { return "LocaleID" } 
    elseif ($ldapProp -eq "mail") { return "WindowsEmailAddress" } 
    elseif ($ldapProp -eq "mailnickname") { return "Alias" } 
    elseif ($ldapProp -eq "managedby") { return "ManagedBy" } 
    elseif ($ldapProp -eq "manager") { return "Manager" } 
    elseif ($ldapProp -eq "mapirecipient") { return "MapiRecipient" } 
    elseif ($ldapProp -eq "mdboverhardquotalimit") { return "ProhibitSendReceiveQuota" } 
    elseif ($ldapProp -eq "mdboverquotalimit") { return "ProhibitSendQuota" } 
    elseif ($ldapProp -eq "mdbstoragequota") { return "IssueWarningQuota" } 
    elseif ($ldapProp -eq "mdbusedefaults") { return "UseDatabaseQuotaDefaults" } 
    elseif ($ldapProp -eq "member") { return "Members" } 
    elseif ($ldapProp -eq "memberof") { return "MemberOfGroup" } 
    elseif ($ldapProp -eq "mobile") { return "MobilePhone" } 
    elseif ($ldapProp -eq "msds-phoneticompanyname") { return "PhoneticCompany" } 
    elseif ($ldapProp -eq "msds-phoneticdepartment") { return "PhoneticDepartment" } 
    elseif ($ldapProp -eq "msds-phoneticdsiplayname") { return "PhoneticDisplayName" } 
    elseif ($ldapProp -eq "msds-phoneticfirstname") { return "PhoneticFirstName" } 
    elseif ($ldapProp -eq "msds-phoneticlastname") { return "PhoneticLastName" } 
    elseif ($ldapProp -eq "msexchassistantname") { return "AssistantName" } 
    elseif ($ldapProp -eq "msexchdynamicdlbasedn") { return "RecipientContainer" } 
    elseif ($ldapProp -eq "msexchdynamicdlfilter") { return "LdapRecipientFilter" } 
    elseif ($ldapProp -eq "msexchelcexpirysuspensionend") { return "ElcExpirationSuspensionEndDate" } 
    elseif ($ldapProp -eq "msexchelcexpirysuspensionstart") { return "ElcExpirationSuspensionStartDate" } 
    elseif ($ldapProp -eq "msexchelcmailboxflags") { return "ElcMailboxFlags" } 
    elseif ($ldapProp -eq "msexchexpansionservername") { return "ExpansionServer" } 
    elseif ($ldapProp -eq "msexchexternaloofoptions") { return "ExternalOofOptions" } 
    elseif ($ldapProp -eq "msexchhidefromaddresslists") { return "HiddenFromAddressListsEnabled" } 
    elseif ($ldapProp -eq "msexchhomeservername") { return "ServerLegacyDN" } 
    elseif ($ldapProp -eq "msexchmailboxfolderset") { return "MailboxFolderSet" } 
    elseif ($ldapProp -eq "msexchmailboxguid") { return "ExchangeGuid" } 
    elseif ($ldapProp -eq "msexchmailboxsecuritydescriptor") { return "ExchangeSecurityDescriptor" } 
    elseif ($ldapProp -eq "msexchmailboxtemplatelink") { return "ManagedFolderMailboxPolicy" } 
    elseif ($ldapProp -eq "msexchmasteraccountsid") { return "MasterAccountSid" } 
    elseif ($ldapProp -eq "msexchmaxblockedsenders") { return "MaxBlockedSenders" } 
    elseif ($ldapProp -eq "msexchmaxsafesenders") { return "MaxSafeSenders" } 
    elseif ($ldapProp -eq "msexchmdbrulesquota") { return "RulesQuota" } 
    elseif ($ldapProp -eq "msexchmessagehygieneflags") { return "MessageHygieneFlags" } 
    elseif ($ldapProp -eq "msexchmessagehygienescldeletethreshold") { return "SCLDeleteThresholdInt" } 
    elseif ($ldapProp -eq "msexchmessagehygienescljunkthreshold") { return "SCLJunkThresholdInt" } 
    elseif ($ldapProp -eq "msexchmessagehygienesclquarantinethreshold") { return "SCLQuarantineThresholdInt" } 
    elseif ($ldapProp -eq "msexchmessagehygienesclrejectthreshold") { return "SCLRejectThresholdInt" } 
    elseif ($ldapProp -eq "msexchmobilealloweddeviceids") { return "ActiveSyncAllowedDeviceIDs" } 
    elseif ($ldapProp -eq "msexchmobiledebuglogging") { return "ActiveSyncDebugLogging" } 
    elseif ($ldapProp -eq "msexchmobilemailboxflags") { return "MobileMailboxFlags" } 
    elseif ($ldapProp -eq "msexchmobilemailboxpolicylink") { return "ActiveSyncMailboxPolicy" } 
    elseif ($ldapProp -eq "msexchomaadminextendedsettings") { return "MobileAdminExtendedSettings" } 
    elseif ($ldapProp -eq "msexchomaadminwirelessenable") { return "MobileFeaturesEnabled" } 
    elseif ($ldapProp -eq "msexchpfrooturl") { return "PublicFolderRootUrl" } 
    elseif ($ldapProp -eq "msexchpftreetype") { return "PublicFolderType" } 
    elseif ($ldapProp -eq "msexchpoliciesexcluded") { return "PoliciesExcluded" } 
    elseif ($ldapProp -eq "msexchpoliciesincluded") { return "PoliciesIncluded" } 
    elseif ($ldapProp -eq "msexchprotocolsettings") { return "ProtocolSettings" } 
    elseif ($ldapProp -eq "msexchpurportedsearchui") { return "PurportedSearchUI" } 
    elseif ($ldapProp -eq "msexchquerybasedn") { return "QueryBaseDN" } 
    elseif ($ldapProp -eq "msexchqueryfilter") { return "RecipientFilter" } 
    elseif ($ldapProp -eq "msexchqueryfiltermetadata") { return "RecipientFilterMetadata" } 
    elseif ($ldapProp -eq "msexchrecipientdisplaytype") { return "RecipientDisplayType" } 
    elseif ($ldapProp -eq "msexchrecipienttypedetails") { return "RecipientTypeDetailsValue" } 
    elseif ($ldapProp -eq "msexchreciplimit") { return "RecipientLimits" } 
    elseif ($ldapProp -eq "msexchrequireauthtosendto") { return "RequireAllSendersAreAuthenticated" } 
    elseif ($ldapProp -eq "msexchresourcecapacity") { return "ResourceCapacity" } 
    elseif ($ldapProp -eq "msexchresourcedisplay") { return "ResourcePropertiesDisplay" } 
    elseif ($ldapProp -eq "msexchresourcemetadata") { return "ResourceMetaData" } 
    elseif ($ldapProp -eq "msexchresourcesearchproperties") { return "ResourceSearchProperties" } 
    elseif ($ldapProp -eq "msexchsafesendershash") { return "SafeSendersHash" } 
    elseif ($ldapProp -eq "msexchsaferecipientshash") { return "SafeRecipientsHash" } 
    elseif ($ldapProp -eq "msexchumaudiocodec") { return "CallAnsweringAudioCodec" } 
    elseif ($ldapProp -eq "msexchumdtmfmap") { return "UMDtmfMap" } 
    elseif ($ldapProp -eq "msexchumenabledflags") { return "UMEnabledFlags" } 
    elseif ($ldapProp -eq "msexchumlistindirectorysearch") { return "AllowUMCallsFromNonUsers" } 
    elseif ($ldapProp -eq "msexchumoperatornumber") { return "OperatorNumber" } 
    elseif ($ldapProp -eq "msexchumpinchecksum") { return "UMPinChecksum" } 
    elseif ($ldapProp -eq "msexchumrecipientdialplanlink") { return "UMRecipientDialPlanId" } 
    elseif ($ldapProp -eq "msexchumserverwritableflags") { return "UMServerWritableFlags" } 
    elseif ($ldapProp -eq "msexchumspokenname") { return "UMSpokenName" } 
    elseif ($ldapProp -eq "msexchumtemplatelink") { return "UMMailboxPolicy" } 
    elseif ($ldapProp -eq "msexchuseoab") { return "OfflineAddressBook" } 
    elseif ($ldapProp -eq "msexchuseraccountcontrol") { return "ExchangeUserAccountControl" } 
    elseif ($ldapProp -eq "msexchuserculture") { return "LanguagesRaw" } 
    elseif ($ldapProp -eq "msexchversion") { return "ExchangeVersion" } 
    elseif ($ldapProp -eq "name") { return "Name" } 
    elseif ($ldapProp -eq "ntsecuritydescriptor") { return "NTSecurityDescriptor" } 
    elseif ($ldapProp -eq "objectcategory") { return "ObjectCategory" } 
    elseif ($ldapProp -eq "objectclass") { return "ObjectClass" } 
    elseif ($ldapProp -eq "objectsid") { return "Sid" } 
    elseif ($ldapProp -eq "oofreplytooriginator") { return "SendOofMessageToOriginatorEnabled" } 
    elseif ($ldapProp -eq "otherfacsimiletelephonenumber") { return "OtherFax" } 
    elseif ($ldapProp -eq "otherhomephone") { return "OtherHomePhone" } 
    elseif ($ldapProp -eq "othertelephone") { return "OtherTelephone" } 
    elseif ($ldapProp -eq "pager") { return "Pager" } 
    elseif ($ldapProp -eq "pfcontacts") { return "PublicFolderContacts" } 
    elseif ($ldapProp -eq "physicaldeliveryofficename") { return "Office" } 
    elseif ($ldapProp -eq "postalcode") { return "PostalCode" } 
    elseif ($ldapProp -eq "postofficebox") { return "PostOfficeBox" } 
    elseif ($ldapProp -eq "primarygroupid") { return "PrimaryGroupId" } 
    elseif ($ldapProp -eq "proxyaddresses") { return "EmailAddresses" } 
    elseif ($ldapProp -eq "publicdelegates") { return "GrantSendOnBehalfTo" } 
    elseif ($ldapProp -eq "pwdlastset") { return "PasswordLastSetRaw" } 
    elseif ($ldapProp -eq "reporttooriginator") { return "ReportToOriginatorEnabled" } 
    elseif ($ldapProp -eq "reporttoowner") { return "ReportToManagerEnabled" } 
    elseif ($ldapProp -eq "samaccountname") { return "SamAccountName" } 
    elseif ($ldapProp -eq "showinaddressbook") { return "AddressListMembership" } 
    elseif ($ldapProp -eq "sidhistory") { return "SidHistory" } 
    elseif ($ldapProp -eq "sn") { return "LastName" } 
    elseif ($ldapProp -eq "st") { return "StateOrProvince" } 
    elseif ($ldapProp -eq "submissioncontlength") { return "MaxSendSize" } 
    elseif ($ldapProp -eq "streetaddress") { return "StreetAddress" } 
    elseif ($ldapProp -eq "targetaddress") { return "ExternalEmailAddress" } 
    elseif ($ldapProp -eq "telephoneassistant") { return "TelephoneAssistant" } 
    elseif ($ldapProp -eq "telephonenumber") { return "Phone" } 
    elseif ($ldapProp -eq "textencodedoraddress") { return "TextEncodedORAddress" } 
    elseif ($ldapProp -eq "title") { return "Title" } 
    elseif ($ldapProp -eq "unauthorig") { return "RejectMessagesFrom" } 
    elseif ($ldapProp -eq "unicodepwd") { return "UnicodePassword" } 
    elseif ($ldapProp -eq "useraccountcontrol") { return "UserAccountControl" } 
    elseif ($ldapProp -eq "usercertificate") { return "Certificate" } 
    elseif ($ldapProp -eq "userprincipalname") { return "UserPrincipalName" } 
    elseif ($ldapProp -eq "usersmimecertificate") { return "SMimeCertificate" } 
    elseif ($ldapProp -eq "whenchanged") { return "WhenChanged" } 
    elseif ($ldapProp -eq "whencreated") { return "WhenCreated" } 
    elseif ($ldapProp -eq "wwwhomepage") { return "WebPage" } 
    else { throw "Could not convert LDAP attribute '" + $ldapProp + "' to Opath." } 
} 
 
$script:filterString = $args[0] 
if ($script:filterString.Length -gt 0) { 
    convert-filter 
} 
else { 
    write-host "No LDAP filter supplied." 
} 