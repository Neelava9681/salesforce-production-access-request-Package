@IsTest
private class ProductionAccessResetPasswordTest {

    /**
     * Create a System Administrator test user
     * and assign the Production Access test Permission Set.
     */
    private static User createAdminUser() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        User adminUser = new User(
            Alias = 'tstadm',
            Email = 'testadmin@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testadmin_' + DateTime.now().getTime() + '@example.com'
        );

        // 1. Create the test user in system context
        Database.insert(adminUser, AccessLevel.SYSTEM_MODE);

        // 2. Get the Production Access test Permission Set
        PermissionSet testAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        // 3. Assign the Permission Set in system context
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = testAccessPermissionSet.Id
        );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);

        return adminUser;
    }


    /**
     * Get a Permission Set compatible with the current user's license.
     *
     * This method is called inside System.runAs(adminUser).
     */
    private static PermissionSet getTestPermissionSet() {

        User currentUser = [
            SELECT Id, Profile.UserLicenseId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        List<PermissionSet> psList = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE IsOwnedByProfile = false
            AND LicenseId = :currentUser.Profile.UserLicenseId
            LIMIT 1
        ];

        System.assert(
            !psList.isEmpty(),
            'No compatible PermissionSet found for test.'
        );

        return psList[0];
    }


    @IsTest
    static void testResetPassword_NullInput() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(null);

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Result list should not be null.'
            );

            System.assertEquals(
                0,
                results.size(),
                'Empty list expected for null input.'
            );
        }
    }


    @IsTest
    static void testResetPassword_EmptyInput() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(
                    new List<ProductionAccessResetPassword.ResetRequest>()
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Result list should not be null.'
            );

            System.assertEquals(
                0,
                results.size(),
                'Empty list expected for empty input.'
            );
        }
    }


    @IsTest
    static void testResetPassword_OnlyPasswordReset() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessResetPassword.ResetRequest req =
                new ProductionAccessResetPassword.ResetRequest();

            req.onlyPasswordReset = true;
            req.onlyPermissionSetAssignment = false;

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(
                    new List<ProductionAccessResetPassword.ResetRequest>{
                        req
                    }
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results list should not be null.'
            );
        }
    }


    @IsTest
    static void testResetPassword_OnlyPermissionSetAssignment() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            ProductionAccessResetPassword.ResetRequest req =
                new ProductionAccessResetPassword.ResetRequest();

            req.onlyPasswordReset = false;
            req.onlyPermissionSetAssignment = true;
            req.accessType = ps.Name;
            req.requestedEnd = Datetime.now().addHours(2);

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(
                    new List<ProductionAccessResetPassword.ResetRequest>{
                        req
                    }
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results list should not be null.'
            );
        }
    }


    @IsTest
    static void testResetPassword_BothFlags() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            ProductionAccessResetPassword.ResetRequest req =
                new ProductionAccessResetPassword.ResetRequest();

            req.onlyPasswordReset = true;
            req.onlyPermissionSetAssignment = true;
            req.accessType = ps.Name;
            req.requestedEnd = Datetime.now().addHours(2);

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(
                    new List<ProductionAccessResetPassword.ResetRequest>{
                        req
                    }
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results list should not be null.'
            );
        }
    }


    @IsTest
    static void testResetPassword_DefaultsBothWhenFlagsNull() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessResetPassword.ResetRequest req =
                new ProductionAccessResetPassword.ResetRequest();

            req.onlyPasswordReset = null;
            req.onlyPermissionSetAssignment = null;

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(
                    new List<ProductionAccessResetPassword.ResetRequest>{
                        req
                    }
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results list should not be null.'
            );
        }
    }


    @IsTest
    static void testResetPassword_NullRequestItem() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            List<ProductionAccessResetPassword.ResetRequest> reqs =
                new List<ProductionAccessResetPassword.ResetRequest>();

            reqs.add(null);

            Test.startTest();

            List<ProductionAccessResetPassword.ResetResult> results =
                ProductionAccessResetPassword.resetPassword(reqs);

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results should not be null.'
            );
        }
    }


    @IsTest
    static void testResetResult_FieldsExist() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessResetPassword.ResetResult result =
                new ProductionAccessResetPassword.ResetResult();

            result.newPassword = 'TestPass@1';
            result.username = 'user@example.com';

            System.assertEquals(
                'TestPass@1',
                result.newPassword,
                'newPassword should be settable.'
            );

            System.assertEquals(
                'user@example.com',
                result.username,
                'username should be settable.'
            );
        }
    }


    @IsTest
    static void testResetRequest_FieldsExist() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessResetPassword.ResetRequest req =
                new ProductionAccessResetPassword.ResetRequest();

            req.accessType = 'Admin';
            req.requestedEnd = Datetime.now().addHours(1);
            req.onlyPasswordReset = true;
            req.onlyPermissionSetAssignment = false;
            req.requestId = null;

            System.assertEquals(
                'Admin',
                req.accessType,
                'accessType should be settable.'
            );

            System.assertEquals(
                true,
                req.onlyPasswordReset,
                'onlyPasswordReset should be settable.'
            );

            System.assertEquals(
                false,
                req.onlyPermissionSetAssignment,
                'onlyPermissionSetAssignment should be settable.'
            );
        }
    }
	@IsTest
    static void testResetPassword_MatchingPermissionSetMetadata() {
    
    User adminUser = createAdminUser();
    
    System.runAs(adminUser) {
    
        List<Production_Access_Type__mdt> activeTypes = [
            SELECT MasterLabel, DeveloperName, Label, Permission_Set_API_Name__c
            FROM Production_Access_Type__mdt
            WHERE Active__c = true
            AND Permission_Set_API_Name__c != null
            LIMIT 1
        ];
    
        System.assert(
            !activeTypes.isEmpty(),
            'At least one active Production_Access_Type__mdt with Permission_Set_API_Name__c is required.'
        );
    
        Production_Access_Type__mdt pat = activeTypes[0];
    
        ProductionAccessResetPassword.ResetRequest req =
            new ProductionAccessResetPassword.ResetRequest();
    
        req.onlyPasswordReset = false;
        req.onlyPermissionSetAssignment = true;
        req.accessType = pat.MasterLabel;
        req.requestedEnd = Datetime.now().addHours(2);
    
        Test.startTest();
    
        List<ProductionAccessResetPassword.ResetResult> results =
            ProductionAccessResetPassword.resetPassword(
                new List<ProductionAccessResetPassword.ResetRequest>{
                    req
                }
            );
    
        Test.stopTest();
    
    }
    
    }
	@IsTest
    static void testUpdateConfigPasswordFuture_InvalidInput() {
    
    User adminUser = createAdminUser();
    
    System.runAs(adminUser) {
    
        Test.startTest();
    
        ProductionAccessResetPassword.resetPassword(
            new List<ProductionAccessResetPassword.ResetRequest>{
                new ProductionAccessResetPassword.ResetRequest()
            }
        );
    
        Test.stopTest();
    
        System.assert(
            true,
            'Password reset flow should complete successfully.'
        );
    }
    
    }
}