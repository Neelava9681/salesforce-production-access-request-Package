@IsTest
private class ProductionAccessTokenGeneratorTest {

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

        // 3. Assign Permission Set to the test user in system context
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = testAccessPermissionSet.Id
        );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);

        return adminUser;
    }


    @IsTest
    static void testGenerateToken_NullInput() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            Test.startTest();

            List<ProductionAccessTokenGenerator.TokenResult> results =
                ProductionAccessTokenGenerator.generateToken(null);

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results should not be null.'
            );

            System.assertEquals(
                0,
                results.size(),
                'Null input should return an empty list.'
            );
        }
    }


    @IsTest
    static void testGenerateToken_EmptyInput() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            List<ProductionAccessTokenGenerator.TokenRequest> requests =
                new List<ProductionAccessTokenGenerator.TokenRequest>();

            Test.startTest();

            List<ProductionAccessTokenGenerator.TokenResult> results =
                ProductionAccessTokenGenerator.generateToken(requests);

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results should not be null.'
            );

            System.assertEquals(
                0,
                results.size(),
                'Empty input should return an empty list.'
            );
        }
    }


    @IsTest
    static void testGenerateToken_SingleRequest() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessTokenGenerator.TokenRequest request =
                new ProductionAccessTokenGenerator.TokenRequest();

            request.recordId = 'a0ygL0000000001AAA';

            Test.startTest();

            List<ProductionAccessTokenGenerator.TokenResult> results =
                ProductionAccessTokenGenerator.generateToken(
                    new List<ProductionAccessTokenGenerator.TokenRequest>{
                        request
                    }
                );

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results should not be null.'
            );

            System.assertEquals(
                1,
                results.size(),
                'One request should return one result.'
            );

            System.assertNotEquals(
                null,
                results[0].token,
                'Generated token should not be null.'
            );

            System.assert(
                String.isNotBlank(results[0].token),
                'Generated token should not be blank.'
            );
        }
    }


    @IsTest
    static void testGenerateToken_MultipleRequests() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessTokenGenerator.TokenRequest request1 =
                new ProductionAccessTokenGenerator.TokenRequest();

            request1.recordId = 'a0ygL0000000001AAA';

            ProductionAccessTokenGenerator.TokenRequest request2 =
                new ProductionAccessTokenGenerator.TokenRequest();

            request2.recordId = 'a0ygL0000000002AAA';

            List<ProductionAccessTokenGenerator.TokenRequest> requests =
                new List<ProductionAccessTokenGenerator.TokenRequest>{
                    request1,
                    request2
                };

            Test.startTest();

            List<ProductionAccessTokenGenerator.TokenResult> results =
                ProductionAccessTokenGenerator.generateToken(requests);

            Test.stopTest();

            System.assertNotEquals(
                null,
                results,
                'Results should not be null.'
            );

            System.assertEquals(
                2,
                results.size(),
                'Two requests should return two results.'
            );

            System.assertNotEquals(
                null,
                results[0].token,
                'First token should not be null.'
            );

            System.assertNotEquals(
                null,
                results[1].token,
                'Second token should not be null.'
            );

            System.assert(
                String.isNotBlank(results[0].token),
                'First token should not be blank.'
            );

            System.assert(
                String.isNotBlank(results[1].token),
                'Second token should not be blank.'
            );

            System.assertNotEquals(
                results[0].token,
                results[1].token,
                'Tokens for different requests should be different.'
            );
        }
    }


    @IsTest
    static void testGenerateToken_TokenCanBeDecoded() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            Production_Access_Request__c requestRecord =
                new Production_Access_Request__c(
                    Developer_Name__c = 'Test Developer',
                    Developer_Email__c = 'test@example.com',
                    Ticket_Number__c = 'TEST-001',
                    Reason__c = 'Test Production Access',
                    Access_Type__c = 'System Administrator',
                    Requested_Duration__c = 2,
                    Requested_Start__c = Datetime.now(),
                    Requested_End__c = Datetime.now().addHours(2),
                    Status__c = 'Pending Approval'
                );

            insert requestRecord;

            ProductionAccessTokenGenerator.TokenRequest tokenRequest =
                new ProductionAccessTokenGenerator.TokenRequest();

            tokenRequest.recordId = String.valueOf(requestRecord.Id);

            Test.startTest();

            List<ProductionAccessTokenGenerator.TokenResult> results =
                ProductionAccessTokenGenerator.generateToken(
                    new List<ProductionAccessTokenGenerator.TokenRequest>{
                        tokenRequest
                    }
                );

            Test.stopTest();

            System.assertEquals(
                1,
                results.size(),
                'One result should be returned.'
            );

            System.assertNotEquals(
                null,
                results[0].token,
                'Token should be generated.'
            );

            String decodedRecordId =
                ProductionAccessApprovalRestResource.decodeToken(
                    results[0].token
                );

            System.assertEquals(
                String.valueOf(requestRecord.Id),
                decodedRecordId,
                'Decoded token should contain the original record Id.'
            );
        }
    }
}