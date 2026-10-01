@IsTest
private class ProductionAccessApprovalRestResourceTest {

    @TestSetup
    static void setupTestData() {

        // Profile query must happen before creating the test user.
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

        // 1. Create the test user in SYSTEM_MODE
        Database.insert(adminUser, AccessLevel.SYSTEM_MODE);

        // 2. Get the Permission Set
        PermissionSet testAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        // 3. Assign Permission Set to the test user in SYSTEM_MODE
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = testAccessPermissionSet.Id
        );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);

        // 4. Everything related to the Production Access Request
        //    runs as the System Administrator test user.
        System.runAs(adminUser) {

            Production_Access_Request__c req =
                new Production_Access_Request__c(
                    Developer_Name__c = 'Test Developer',
                    Developer_Email__c = 'dev@example.com',
                    Ticket_Number__c = 'INC-12345',
                    Reason__c = 'Emergency Bug Fix',
                    Access_Type__c = 'System Administrator',
                    Requested_Duration__c = 2,
                    Requested_Start__c = Datetime.now(),
                    Requested_End__c = Datetime.now().addHours(2),
                    Status__c = 'Approved'
                );

            insert req;
        }
    }


    private static void setupRestContext(
        String token,
        String recordId,
        String action
    ) {

        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();

        request.requestURI =
            '/services/apexrest/productionAccess/approveReject/';

        request.httpMethod = 'GET';

        if (String.isNotBlank(token)) {
            request.addParameter('token', token);
        }

        if (String.isNotBlank(recordId)) {
            request.addParameter('id', recordId);
        }

        if (String.isNotBlank(action)) {
            request.addParameter('action', action);
        }

        RestContext.request = request;
        RestContext.response = response;
    }

    @IsTest
    static void testApproveRequestWithRawId() {
        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];
    
        System.runAs(adminUser) {
            Production_Access_Request__c req = [
                SELECT Id, Status__c
                FROM Production_Access_Request__c
                LIMIT 1
            ];
    
            // Important: The REST class only processes requests
            // having Pending Approval or Pending status.
            req.Status__c = 'Pending Approval';
            update req;
    
            setupRestContext(null, req.Id, 'Approve');
    
            Test.startTest();
            ProductionAccessApprovalRestResource.handleApprovalOrRejection();
            Test.stopTest();
    
            Production_Access_Request__c updated = [
                SELECT Status__c
                FROM Production_Access_Request__c
                WHERE Id = :req.Id
            ];
    
            System.assertEquals(
                'Approved',
                updated.Status__c,
                'Request should be marked as Approved.'
            );
    
            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains('APPROVED successfully'),
                'Response should contain the approval message.'
            );
        }
    }


    @IsTest
    static void testMissingParameters() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            setupRestContext(null, null, null);

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains('Invalid request parameters')
            );
        }
    }


    @IsTest
    static void testMissingAction() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            String token =
                ProductionAccessApprovalRestResource.encodeToken(req.Id);

            setupRestContext(token, null, null);

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains('Invalid request parameters')
            );
        }
    }


    @IsTest
    static void testRecordNotFound() {

        // Profile query must happen before creating the test user.
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        User adminUser = new User(
            Alias = 'tstadm2',
            Email = 'testadmin2@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testadmin2_' + DateTime.now().getTime() + '@example.com'
        );

        // 1. Create the test user in SYSTEM_MODE
        Database.insert(adminUser, AccessLevel.SYSTEM_MODE);

        // 2. Get the Permission Set
        PermissionSet testAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        // 3. Assign Permission Set in SYSTEM_MODE
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = testAccessPermissionSet.Id
        );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);

        // 4. Create and delete the request as the admin user
        System.runAs(adminUser) {

            Production_Access_Request__c req =
                new Production_Access_Request__c(
                    Developer_Name__c = 'Test Developer',
                    Developer_Email__c = 'dev@example.com',
                    Ticket_Number__c = 'INC-12345',
                    Reason__c = 'Emergency Bug Fix',
                    Access_Type__c = 'System Administrator',
                    Requested_Duration__c = 2,
                    Requested_Start__c = Datetime.now(),
                    Requested_End__c = Datetime.now().addHours(2),
                    Status__c = 'Approved'
                );

            insert req;

            Id deletedId = req.Id;

            // Delete as admin user
            delete req;

            setupRestContext(
                null,
                deletedId,
                'Approve'
            );
        }

        Test.startTest();

        ProductionAccessApprovalRestResource.handleApprovalOrRejection();

        Test.stopTest();

        System.assert(
            RestContext.response.responseBody
                .toString()
                .contains(
                    'Production Access Request record not found.'
                )
        );
    }


    @IsTest
    static void testAlreadyProcessed() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            // Update as admin user
            req.Status__c = 'Approved';

            update req;

            String token =
                ProductionAccessApprovalRestResource.encodeToken(req.Id);

            setupRestContext(
                token,
                null,
                'Approve'
            );

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains('already been processed')
            );
        }
    }


    @IsTest
    static void testEncodeDecodeTokenRoundTrip() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            String token =
                ProductionAccessApprovalRestResource.encodeToken(req.Id);

            String decoded =
                ProductionAccessApprovalRestResource.decodeToken(token);

            System.assertEquals(
                String.valueOf(req.Id),
                decoded
            );
        }
    }


    @IsTest
    static void testEncodeTokenBlankInput() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            String result =
                ProductionAccessApprovalRestResource.encodeToken('');

            System.assertEquals(
                '',
                result
            );
        }
    }


    @IsTest
    static void testDecodeTokenBlankInput() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            String result =
                ProductionAccessApprovalRestResource.decodeToken('');

            System.assertEquals(
                null,
                result
            );
        }
    }


    @IsTest
    static void testDecodeTokenInvalidToken() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            String result =
                ProductionAccessApprovalRestResource.decodeToken(
                    'NOT_VALID_BASE64!!!'
                );

            System.assertEquals(
                null,
                result
            );
        }
    }


    @IsTest
    static void testNullResponseInitialisedInternally() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            String token =
                ProductionAccessApprovalRestResource.encodeToken(req.Id);

            RestRequest request = new RestRequest();

            request.requestURI =
                '/services/apexrest/productionAccess/approveReject/';

            request.httpMethod = 'GET';

            request.addParameter(
                'token',
                token
            );

            request.addParameter(
                'action',
                'Approve'
            );

            RestContext.request = request;
            RestContext.response = null;

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            System.assertNotEquals(
                null,
                RestContext.response
            );
        }
    }

    @IsTest
    static void testRejectRequest() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id, Status__c
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            // Make sure the request is in a processable state.
            req.Status__c = 'Pending Approval';
            update req;

            setupRestContext(
                null,
                req.Id,
                'Reject'
            );

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            Production_Access_Request__c updated = [
                SELECT Status__c
                FROM Production_Access_Request__c
                WHERE Id = :req.Id
            ];

            System.assertEquals(
                'Rejected',
                updated.Status__c,
                'Request should be marked as Rejected.'
            );

            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains('REJECTED'),
                'Response should contain the rejection message.'
            );
        }
    }


    @IsTest
    static void testInvalidAction() {

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tstadm'
            LIMIT 1
        ];

        System.runAs(adminUser) {

            Production_Access_Request__c req = [
                SELECT Id, Status__c
                FROM Production_Access_Request__c
                LIMIT 1
            ];

            // Make sure the request is still processable.
            req.Status__c = 'Pending Approval';
            update req;

            setupRestContext(
                null,
                req.Id,
                'InvalidAction'
            );

            Test.startTest();

            ProductionAccessApprovalRestResource.handleApprovalOrRejection();

            Test.stopTest();

            System.assert(
                RestContext.response.responseBody
                    .toString()
                    .contains(
                        'Invalid action parameter specified.'
                    ),
                'Invalid action should return an error response.'
            );

            System.assertEquals(
                'Pending Approval',
                [
                    SELECT Status__c
                    FROM Production_Access_Request__c
                    WHERE Id = :req.Id
                ].Status__c,
                'Invalid action should not change the request status.'
            );
        }
    }
}