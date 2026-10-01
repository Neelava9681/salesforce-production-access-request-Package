public without sharing class ProductionAccessResetPassword {

    public class ResetRequest {
        @InvocableVariable
        public String accessType;

        @InvocableVariable
        public Datetime requestedEnd;

        @InvocableVariable
        public Boolean onlyPasswordReset;

        @InvocableVariable
        public Boolean onlyPermissionSetAssignment;

        @InvocableVariable
        public Id requestId;
    }

    public class ResetResult {
        @InvocableVariable
        public String newPassword;

        @InvocableVariable
        public String username;
    }

    @InvocableMethod(
        label='Reset Production User Password'
        description='Resets production user password, optionally assigns permission set, and returns new password and config details'
    )
    public static List<ResetResult> resetPassword(List<ResetRequest> requests) {
        List<ResetResult> results = new List<ResetResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<Production_Access_Config__mdt> configs = [
            SELECT DeveloperName, MasterLabel, Label, Production_Username__c, Authorizers_Email_IDs__c, Password__c
            FROM Production_Access_Config__mdt
            WHERE Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'No active Production_Access_Config__mdt found.');  return results;
        }

        Production_Access_Config__mdt config = configs[0];
        String targetUsername = config.Production_Username__c;

        if (String.isBlank(targetUsername)) {
            System.debug(LoggingLevel.ERROR, 'Target username is not configured in Production_Access_Config__mdt.');return results;
        }

        List<User> targetUsers = [
            SELECT Id, Email, Username, Name
            FROM User
            WHERE Username = :targetUsername OR Email = :targetUsername
            LIMIT 1
        ];

        if (targetUsers.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'No User found with username/email: ' + targetUsername); return results;
        }

        User targetUser = targetUsers[0];

        for (ResetRequest req : requests) {
            Boolean doPasswordReset = false;
            Boolean doPermissionSetAssignment = false;

            if (req != null) {
                if (req.onlyPasswordReset == true && req.onlyPermissionSetAssignment == true) {
                    doPasswordReset = true;
                    doPermissionSetAssignment = true;
                } else if (req.onlyPasswordReset == true) {
                    doPasswordReset = true;
                    doPermissionSetAssignment = false;
                } else if (req.onlyPermissionSetAssignment == true) {
                    doPasswordReset = false;
                    doPermissionSetAssignment = true;
                } else {
                    doPasswordReset = true;
                    doPermissionSetAssignment = true;
                }
            } else {
                doPasswordReset = true;
                doPermissionSetAssignment = true;
            }

            String passwordToReturn = null;
            if (doPasswordReset) {
                passwordToReturn = generateRandomPassword();
                try {
                    System.setPassword(targetUser.Id, passwordToReturn);
                    String labelVal = String.isNotBlank(config.Label) ? config.Label : config.MasterLabel;
                    updateConfigPasswordFuture(config.DeveloperName, labelVal, passwordToReturn);} catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Error resetting password: ' + e.getMessage());
                }
            } else {
                passwordToReturn = config.Password__c;
            }

            if (doPermissionSetAssignment && req != null && String.isNotBlank(req.accessType)) {
                String selectedType = req.accessType.trim();
                String matchingPermSetApiName = null;

                for (Production_Access_Type__mdt pat : [
                    SELECT MasterLabel, DeveloperName, Label, Permission_Set_API_Name__c
                    FROM Production_Access_Type__mdt
                    WHERE Active__c = true
                ]) {
                    if (selectedType.equalsIgnoreCase(pat.MasterLabel) || 
                        selectedType.equalsIgnoreCase(pat.DeveloperName) ||
                        (pat.Label != null && selectedType.equalsIgnoreCase(pat.Label)) ||
                        (pat.Permission_Set_API_Name__c != null && selectedType.equalsIgnoreCase(pat.Permission_Set_API_Name__c))) {
                        matchingPermSetApiName = pat.Permission_Set_API_Name__c;
                        break;
                    }
                }

                if (String.isBlank(matchingPermSetApiName)) {
                    matchingPermSetApiName = selectedType;
                }

                if (String.isNotBlank(matchingPermSetApiName)) {
                    ProductionAccessPermissionSet.PermissionSetRequest psReq = new ProductionAccessPermissionSet.PermissionSetRequest();
                    psReq.userId = targetUser.Id;
                    psReq.permissionSetId = matchingPermSetApiName;
                    psReq.expirationDate = req.requestedEnd;
                    psReq.requestId = req.requestId;
                    
                    try {
                        ProductionAccessPermissionSet.assignPermissionSet(new List<ProductionAccessPermissionSet.PermissionSetRequest>{ psReq });} catch (Exception e) {
                        System.debug(LoggingLevel.ERROR, 'Error assigning permission set: ' + e.getMessage());
                    }
                }
            }

            ResetResult res = new ResetResult();
            res.newPassword = passwordToReturn;
            res.username = targetUser.Username;
            results.add(res);
        }

        return results;
    }

    @future
    private static void updateConfigPasswordFuture(String devName, String label, String newPassword) {
        if (String.isBlank(devName) || String.isBlank(newPassword)) {return;
        }
        try {
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = 'Production_Access_Config.' + devName;
            customMetadata.label = label;

            Metadata.CustomMetadataValue customField = new Metadata.CustomMetadataValue();
            customField.field = 'Password__c';
            customField.value = newPassword;
            customMetadata.values.add(customField);

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            if (!Test.isRunningTest()) {Metadata.Operations.enqueueDeployment(mdContainer, null);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating Production_Access_Config__mdt Password__c: ' + e.getMessage());
        }
    }

    private static String generateRandomPassword() {
        String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        String password = 'P@ss' + String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 4);
        for (Integer i = 0; i < 4; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            password += chars.substring(idx, idx + 1);
        }
        return password + '!1';
    }
}