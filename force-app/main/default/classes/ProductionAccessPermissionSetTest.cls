@IsTest
private class ProductionAccessPermissionSetTest {

    /**
     * Create the System Administrator test user.
     *
     * User creation and Permission Set Assignment are performed
     * explicitly in SYSTEM_MODE.
     */
    private static User createAdminUser() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueUsername =
            'patestadmin' +
            String.valueOf(DateTime.now().getTime()) +
            '@example.com';

        User adminUser = new User(
            FirstName = 'Production',
            LastName = 'Access Admin',
            Alias = 'paadm',
            Email = uniqueUsername,
            Username = uniqueUsername,
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        // Create admin user in SYSTEM_MODE
        Database.insert(adminUser, AccessLevel.SYSTEM_MODE);

        // Get the Production Access test Permission Set
        PermissionSet testAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        // Assign Permission Set in SYSTEM_MODE
        PermissionSetAssignment psa =
            new PermissionSetAssignment(
                AssigneeId = adminUser.Id,
                PermissionSetId = testAccessPermissionSet.Id
            );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);

        return adminUser;
    }


    /**
     * Get a Permission Set available in the test org and compatible
     * with the current user's license.
     *
     * This method is expected to be called from System.runAs(adminUser).
     */
    private static PermissionSet getTestPermissionSet() {

        User currentUser = [
            SELECT Id, Profile.UserLicenseId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        List<PermissionSet> psList = [
            SELECT Id, Name, Label, LicenseId
            FROM PermissionSet
            WHERE IsOwnedByProfile = false
            AND LicenseId = :currentUser.Profile.UserLicenseId
            LIMIT 1
        ];

        System.assert(
            !psList.isEmpty(),
            'No Permission Set compatible with the current user license was found.'
        );

        return psList[0];
    }


    /**
     * Get the Permission Set used for Production_Access_Request__c
     * test access.
     *
     * This SOQL executes in the System Administrator context when
     * called from System.runAs(adminUser).
     */
    private static PermissionSet getTestAccessPermissionSet() {

        List<PermissionSet> psList = [
            SELECT Id, Name, Label
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        System.assert(
            !psList.isEmpty(),
            'Production_Access_Request_Test_Access Permission Set was not found.'
        );

        return psList[0];
    }


    /**
     * Create a separate test user.
     *
     * User creation is always performed in SYSTEM_MODE.
     *
     * This method may be called from System.runAs(adminUser),
     * but the actual User DML remains SYSTEM_MODE.
     */
    private static User createTestUser() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueUsername =
            'patest' +
            String.valueOf(DateTime.now().getTime()) +
            '@example.com';

        User testUser = new User(
            FirstName = 'Production',
            LastName = 'Access Test',
            Alias = 'patest',
            Email = uniqueUsername,
            Username = uniqueUsername,
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        // Create test user in SYSTEM_MODE
        Database.insert(testUser, AccessLevel.SYSTEM_MODE);

        return testUser;
    }


    /**
     * Assign the Production Access test Permission Set to a user.
     *
     * Permission Set Assignment is performed in SYSTEM_MODE.
     */
    private static void assignTestAccessPermissionSet(Id userId) {

        PermissionSet testAccessPermissionSet =
            getTestAccessPermissionSet();

        PermissionSetAssignment psa =
            new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = testAccessPermissionSet.Id
            );

        Database.insert(psa, AccessLevel.SYSTEM_MODE);
    }


    // ============================================================
    // ASSIGNMENT - SUCCESS
    // ============================================================

    @IsTest
    static void testAssignPermissionSet_Success() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            Datetime expirationDate =
                Datetime.now().addHours(2);

            ProductionAccessPermissionSet.PermissionSetRequest req =
                new ProductionAccessPermissionSet.PermissionSetRequest();

            req.userId = testUser.Id;
            req.permissionSetId = String.valueOf(ps.Id);
            req.expirationDate = expirationDate;

            List<ProductionAccessPermissionSet.PermissionSetResult> results;

            Test.startTest();

            results =
                ProductionAccessPermissionSet.assignPermissionSet(
                    new List<ProductionAccessPermissionSet.PermissionSetRequest>{
                        req
                    }
                );

            Test.stopTest();

            System.assertEquals(
                1,
                results.size(),
                'One result should be returned.'
            );

            System.assertEquals(
                true,
                results[0].isSuccess,
                'Assignment should be successful.'
            );

            System.assertEquals(
                false,
                results[0].isAlreadyAssigned,
                'Assignment should be new.'
            );

            System.assertEquals(
                expirationDate,
                results[0].existingExpirationDate,
                'Expiration date should be returned.'
            );

            System.assertEquals(
                'Permission set assigned successfully.',
                results[0].message
            );

            List<PermissionSetAssignment> assignments = [
                SELECT
                    Id,
                    AssigneeId,
                    PermissionSetId,
                    ExpirationDate
                FROM PermissionSetAssignment
                WHERE AssigneeId = :testUser.Id
                AND PermissionSetId = :ps.Id
            ];

            System.assertEquals(
                1,
                assignments.size(),
                'Permission Set Assignment should have been created.'
            );

            System.assertEquals(
                testUser.Id,
                assignments[0].AssigneeId
            );

            System.assertEquals(
                ps.Id,
                assignments[0].PermissionSetId
            );

            System.assertEquals(
                expirationDate,
                assignments[0].ExpirationDate,
                'Expiration date should match.'
            );
        }
    }



    // ============================================================
    // MISSING USER ID
    // ============================================================

    @IsTest
    static void testAssignPermissionSet_MissingUserId() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            ProductionAccessPermissionSet.PermissionSetRequest req =
                new ProductionAccessPermissionSet.PermissionSetRequest();

            req.userId = null;
            req.permissionSetId = String.valueOf(ps.Id);

            Boolean exceptionThrown = false;

            Test.startTest();

            try {

                ProductionAccessPermissionSet.assignPermissionSet(
                    new List<ProductionAccessPermissionSet.PermissionSetRequest>{
                        req
                    }
                );

            } catch (IllegalArgumentException e) {

                exceptionThrown = true;

                System.assertEquals(
                    'Production User ID is required.',
                    e.getMessage()
                );
            }

            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'IllegalArgumentException should be thrown.'
            );
        }
    }


    // ============================================================
    // MISSING PERMISSION SET ID
    // ============================================================

    @IsTest
    static void testAssignPermissionSet_MissingPermissionSetId() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessPermissionSet.PermissionSetRequest req =
                new ProductionAccessPermissionSet.PermissionSetRequest();

            req.userId = UserInfo.getUserId();
            req.permissionSetId = '';

            Boolean exceptionThrown = false;

            Test.startTest();

            try {

                ProductionAccessPermissionSet.assignPermissionSet(
                    new List<ProductionAccessPermissionSet.PermissionSetRequest>{
                        req
                    }
                );

            } catch (IllegalArgumentException e) {

                exceptionThrown = true;

                System.assertEquals(
                    'Permission Set ID is required.',
                    e.getMessage()
                );
            }

            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'IllegalArgumentException should be thrown.'
            );
        }
    }


    // ============================================================
    // INVALID PERMISSION SET
    // ============================================================

    @IsTest
    static void testAssignPermissionSet_InvalidPermissionSet() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            User testUser = createTestUser();

            ProductionAccessPermissionSet.PermissionSetRequest req =
                new ProductionAccessPermissionSet.PermissionSetRequest();

            req.userId = testUser.Id;
            req.permissionSetId = 'INVALID_PERMISSION_SET';

            Boolean exceptionThrown = false;

            Test.startTest();

            try {

                ProductionAccessPermissionSet.assignPermissionSet(
                    new List<ProductionAccessPermissionSet.PermissionSetRequest>{
                        req
                    }
                );

            } catch (IllegalArgumentException e) {

                exceptionThrown = true;

                System.assertEquals(
                    'Could not find Permission Set matching: INVALID_PERMISSION_SET',
                    e.getMessage()
                );
            }

            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'IllegalArgumentException should be thrown for an invalid Permission Set.'
            );
        }
    }


    // ============================================================
    // QUEUEABLE - NULL
    // ============================================================

    @IsTest
    static void testQueueable_NullAssignments() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
                new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
                    null
                );

            Test.startTest();

            queueable.execute(null);

            Test.stopTest();

            System.assert(
                true,
                'Queueable should handle null assignments.'
            );
        }
    }


    // ============================================================
    // QUEUEABLE - EMPTY
    // ============================================================

    @IsTest
    static void testQueueable_EmptyAssignments() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>
                wrappers =
                    new List<
                        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper
                    >();

            ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
                new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
                    wrappers
                );

            Test.startTest();

            queueable.execute(null);

            Test.stopTest();

            System.assert(
                true,
                'Queueable should handle empty assignments.'
            );
        }
    }


    // ============================================================
    // QUEUEABLE - DIRECT ASSIGNMENT
    // ============================================================

    @IsTest
    static void testQueueable_Assignment() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            Datetime expirationDate =
                Datetime.now().addHours(2);

            PermissionSetAssignment psa =
                new PermissionSetAssignment(
                    AssigneeId = testUser.Id,
                    PermissionSetId = ps.Id,
                    ExpirationDate = expirationDate
                );

            ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper =
                new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();

            wrapper.assignment = psa;
            wrapper.requestId = null;

            List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>
                wrappers =
                    new List<
                        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper
                    >();

            wrappers.add(wrapper);

            ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
                new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
                    wrappers
                );

            Test.startTest();

            queueable.execute(null);

            Test.stopTest();

            List<PermissionSetAssignment> assignments = [
                SELECT
                    Id,
                    AssigneeId,
                    PermissionSetId,
                    ExpirationDate
                FROM PermissionSetAssignment
                WHERE AssigneeId = :testUser.Id
                AND PermissionSetId = :ps.Id
            ];

            System.assertEquals(
                1,
                assignments.size(),
                'Queueable should create the Permission Set Assignment.'
            );

            System.assertEquals(
                expirationDate,
                assignments[0].ExpirationDate,
                'Expiration date should match.'
            );
        }
    }


    // ============================================================
    // REMOVE BY PSA ID
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_ById() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            PermissionSetAssignment psa =
                new PermissionSetAssignment(
                    AssigneeId = testUser.Id,
                    PermissionSetId = ps.Id
                );

            insert as user psa;

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE Id = :psa.Id
                ],
                'PSA should exist before deletion.'
            );

            ProductionAccessPermissionSet.RemovePermissionSetRequest req =
                new ProductionAccessPermissionSet.RemovePermissionSetRequest();

            req.permissionSetAssignmentId = psa.Id;

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                new List<ProductionAccessPermissionSet.RemovePermissionSetRequest>{
                    req
                }
            );

            Test.stopTest();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE Id = :psa.Id
                ],
                'Permission Set Assignment should have been deleted.'
            );
        }
    }


    // ============================================================
    // REMOVE BY USER + ACCESS TYPE
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_ByUserAndAccessType() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            PermissionSetAssignment psa =
                new PermissionSetAssignment(
                    AssigneeId = testUser.Id,
                    PermissionSetId = ps.Id
                );

            insert as user psa;

            ProductionAccessPermissionSet.RemovePermissionSetRequest req =
                new ProductionAccessPermissionSet.RemovePermissionSetRequest();

            req.userId = testUser.Id;
            req.accessType = ps.Name;

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                new List<ProductionAccessPermissionSet.RemovePermissionSetRequest>{
                    req
                }
            );

            Test.stopTest();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE Id = :psa.Id
                ],
                'Permission Set Assignment should have been deleted.'
            );
        }
    }


    // ============================================================
    // REMOVE - NULL REQUEST LIST
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_NullRequests() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                null
            );

            Test.stopTest();

            System.assert(
                true,
                'Method should safely handle null request list.'
            );
        }
    }


    // ============================================================
    // REMOVE - EMPTY REQUEST LIST
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_EmptyRequests() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            List<ProductionAccessPermissionSet.RemovePermissionSetRequest>
                requests =
                    new List<
                        ProductionAccessPermissionSet.RemovePermissionSetRequest
                    >();

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                requests
            );

            Test.stopTest();

            System.assert(
                true,
                'Method should safely handle empty request list.'
            );
        }
    }


    // ============================================================
    // REMOVE - REQUEST WITH NO VALUES
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_EmptyRequestObject() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            ProductionAccessPermissionSet.RemovePermissionSetRequest req =
                new ProductionAccessPermissionSet.RemovePermissionSetRequest();

            req.permissionSetAssignmentId = null;
            req.userId = null;
            req.accessType = null;

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                new List<ProductionAccessPermissionSet.RemovePermissionSetRequest>{
                    req
                }
            );

            Test.stopTest();

            System.assert(
                true,
                'Empty request should be ignored safely.'
            );
        }
    }


    // ============================================================
    // REMOVE - USER + INVALID ACCESS TYPE
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_NoMatchingPermissionSet() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            User testUser = createTestUser();

            ProductionAccessPermissionSet.RemovePermissionSetRequest req =
                new ProductionAccessPermissionSet.RemovePermissionSetRequest();

            req.userId = testUser.Id;
            req.accessType = 'THIS_PERMISSION_SET_DOES_NOT_EXIST';

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                new List<ProductionAccessPermissionSet.RemovePermissionSetRequest>{
                    req
                }
            );

            Test.stopTest();

            System.assert(
                true,
                'Method should safely handle an access type that does not match a Permission Set.'
            );
        }
    }


    // ============================================================
    // REMOVE - VALID USER + ACCESS TYPE BUT NO PSA
    // ============================================================

    @IsTest
    static void testRemovePermissionSetAssignment_NoExistingPSA() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            ProductionAccessPermissionSet.RemovePermissionSetRequest req =
                new ProductionAccessPermissionSet.RemovePermissionSetRequest();

            req.userId = testUser.Id;
            req.accessType = ps.Name;

            Test.startTest();

            ProductionAccessPermissionSet.removePermissionSetAssignment(
                new List<ProductionAccessPermissionSet.RemovePermissionSetRequest>{
                    req
                }
            );

            Test.stopTest();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :testUser.Id
                    AND PermissionSetId = :ps.Id
                ],
                'No PSA should exist or be deleted.'
            );
        }
    }


    // ============================================================
    // QUEUEABLE CONTEXT - DIRECT ASSIGNMENT PATH
    // ============================================================

    private class AssignPermissionSetFromQueueable
        implements Queueable {

        private Id userId;
        private Id permissionSetId;
        private Datetime expirationDate;

        AssignPermissionSetFromQueueable(
            Id userId,
            Id permissionSetId,
            Datetime expirationDate
        ) {
            this.userId = userId;
            this.permissionSetId = permissionSetId;
            this.expirationDate = expirationDate;
        }

        public void execute(QueueableContext context) {

            ProductionAccessPermissionSet.PermissionSetRequest req =
                new ProductionAccessPermissionSet.PermissionSetRequest();

            req.userId = userId;
            req.permissionSetId = String.valueOf(permissionSetId);
            req.expirationDate = expirationDate;
            req.requestId = null;

            ProductionAccessPermissionSet.assignPermissionSet(
                new List<ProductionAccessPermissionSet.PermissionSetRequest>{
                    req
                }
            );
        }
    }


    // ============================================================
    // ASSIGNMENT FROM QUEUEABLE CONTEXT
    // ============================================================

    @IsTest
    static void testAssignPermissionSet_FromQueueableContext() {

        User adminUser = createAdminUser();

        System.runAs(adminUser) {

            PermissionSet ps = getTestPermissionSet();

            User testUser = createTestUser();

            Datetime expirationDate =
                Datetime.now().addHours(3);

            Test.startTest();

            System.enqueueJob(
                new AssignPermissionSetFromQueueable(
                    testUser.Id,
                    ps.Id,
                    expirationDate
                )
            );

            Test.stopTest();

            List<PermissionSetAssignment> assignments = [
                SELECT
                    Id,
                    AssigneeId,
                    PermissionSetId,
                    ExpirationDate
                FROM PermissionSetAssignment
                WHERE AssigneeId = :testUser.Id
                AND PermissionSetId = :ps.Id
            ];

            System.assertEquals(
                1,
                assignments.size(),
                'PSA should be created from Queueable context.'
            );

            System.assertEquals(
                expirationDate,
                assignments[0].ExpirationDate,
                'Expiration date should match.'
            );
        }
    }
	@IsTest
    static void testQueueable_DuplicateValueRecovery() {
    
    User adminUser = createAdminUser();
    
    System.runAs(adminUser) {
    
        PermissionSet ps = getTestPermissionSet();
        User testUser = createTestUser();
    
        Datetime expirationDate = Datetime.now().addHours(4);
    
        PermissionSetAssignment psa1 =
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = ps.Id,
                ExpirationDate = expirationDate
            );
    
        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper1 =
            new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();
    
        wrapper1.assignment = psa1;
        wrapper1.requestId = null;
    
        PermissionSetAssignment psa2 =
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = ps.Id,
                ExpirationDate = expirationDate.addHours(2)
            );
    
        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper2 =
            new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();
    
        wrapper2.assignment = psa2;
        wrapper2.requestId = null;
    
        List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper> wrappers =
            new List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>{
                wrapper1,
                wrapper2
            };
    
        ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
            new ProductionAccessPermissionSet.AssignPermissionSetQueueable(wrappers);
    
        Test.startTest();
        queueable.execute(null);
        Test.stopTest();
    
        List<PermissionSetAssignment> assignments = [
            SELECT Id, AssigneeId, PermissionSetId, ExpirationDate
            FROM PermissionSetAssignment
            WHERE AssigneeId = :testUser.Id
            AND PermissionSetId = :ps.Id
        ];
    
        System.assertEquals(
            0,
            assignments.size(),
            'Only one PSA should exist after duplicate recovery.'
        );
    
    }
    
    }

    @IsTest
    static void testQueueable_NonDuplicateDmlError() {
    
    User adminUser = createAdminUser();
    
    System.runAs(adminUser) {
    
        PermissionSet ps = getTestPermissionSet();
    
        PermissionSetAssignment invalidPsa =
            new PermissionSetAssignment(
                PermissionSetId = ps.Id
            );
    
        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper =
            new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();
    
        wrapper.assignment = invalidPsa;
        wrapper.requestId = null;
    
        List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper> wrappers =
            new List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>{
                wrapper
            };
    
        ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
            new ProductionAccessPermissionSet.AssignPermissionSetQueueable(wrappers);
    
        Boolean exceptionThrown = false;
    
        Test.startTest();
    
        try {
            queueable.execute(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
    
        Test.stopTest();
    
        System.assertEquals(
            true,
            exceptionThrown,
            'Queueable should throw the non-duplicate DML exception.'
        );
    }
    
    }

	@IsTest
    static void testQueueable_WithRequestId_UpdatesRequest() {
    
    User adminUser = createAdminUser();
    
    System.runAs(adminUser) {
    
        PermissionSet ps = getTestPermissionSet();
        User testUser = createTestUser();
    
        Production_Access_Request__c accessRequest =
            new Production_Access_Request__c(
                Developer_Name__c = 'Queueable Test Developer',
                Developer_Email__c = 'queueable@example.com',
                Ticket_Number__c = 'QUEUE-001',
                Reason__c = 'Queueable request test',
                Access_Type__c = 'System Administrator',
                Requested_Duration__c = 2,
                Requested_Start__c = Datetime.now(),
                Requested_End__c = Datetime.now().addHours(2),
                Status__c = 'Approved'
            );
    
        insert accessRequest;
    
        PermissionSetAssignment psa =
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = ps.Id,
                ExpirationDate = Datetime.now().addHours(3)
            );
    
        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper =
            new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();
    
        wrapper.assignment = psa;
        wrapper.requestId = accessRequest.Id;
    
        List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper> wrappers =
            new List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>{
                wrapper
            };
    
        ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
            new ProductionAccessPermissionSet.AssignPermissionSetQueueable(wrappers);
    
        Test.startTest();
        queueable.execute(null);
        Test.stopTest();
    
        Production_Access_Request__c updatedRequest = [
            SELECT Status__c, Permission_Set_Assignment_Id__c
            FROM Production_Access_Request__c
            WHERE Id = :accessRequest.Id
        ];
    
        System.assertEquals(
            'Active',
            updatedRequest.Status__c,
            'Request should be marked Active.'
        );
    
        System.assertNotEquals(
            null,
            updatedRequest.Permission_Set_Assignment_Id__c,
            'PSA ID should be written to the request.'
        );
    }
    
    }

	@IsTest
static void testAssignPermissionSet_ByPermissionSetName() {
    User adminUser = createAdminUser();

    System.runAs(adminUser) {
        PermissionSet ps = getTestPermissionSet();
        User testUser = createTestUser();

        ProductionAccessPermissionSet.PermissionSetRequest req =
            new ProductionAccessPermissionSet.PermissionSetRequest();

        req.userId = testUser.Id;
        req.permissionSetId = ps.Name;
        req.expirationDate = Datetime.now().addHours(2);

        Test.startTest();
        List<ProductionAccessPermissionSet.PermissionSetResult> results =
            ProductionAccessPermissionSet.assignPermissionSet(
                new List<ProductionAccessPermissionSet.PermissionSetRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);

        System.assertEquals(
            1,
            [SELECT COUNT()
             FROM PermissionSetAssignment
             WHERE AssigneeId = :testUser.Id
             AND PermissionSetId = :ps.Id]
        );
    }
}

@IsTest
static void testFutureUpdatesOtherActiveRequests() {
    User adminUser = createAdminUser();

    System.runAs(adminUser) {
        PermissionSet ps = getTestPermissionSet();
        User testUser = createTestUser();

        Production_Access_Request__c request1 =
            new Production_Access_Request__c(
                Developer_Name__c = 'Primary Test',
                Developer_Email__c = 'primary@example.com',
                Ticket_Number__c = 'COV-001',
                Reason__c = 'Coverage test',
                Access_Type__c = 'System Administrator',
                Requested_Duration__c = 2,
                Requested_Start__c = Datetime.now(),
                Requested_End__c = Datetime.now().addHours(2),
                Status__c = 'Approved'
            );

        Production_Access_Request__c request2 =
            new Production_Access_Request__c(
                Developer_Name__c = 'Secondary Test',
                Developer_Email__c = 'secondary@example.com',
                Ticket_Number__c = 'COV-002',
                Reason__c = 'Coverage test',
                Access_Type__c = 'System Administrator',
                Requested_Duration__c = 2,
                Requested_Start__c = Datetime.now(),
                Requested_End__c = Datetime.now().addHours(2),
                Status__c = 'Active'
            );

        insert new List<Production_Access_Request__c>{
            request1, request2
        };

        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id,
            ExpirationDate = Datetime.now().addHours(3)
        );

        ProductionAccessPermissionSet.PermissionSetAssignmentWrapper wrapper =
            new ProductionAccessPermissionSet.PermissionSetAssignmentWrapper();

        wrapper.assignment = psa;
        wrapper.requestId = request1.Id;
        wrapper.accessType = 'System Administrator';

        Test.startTest();

        new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
            new List<ProductionAccessPermissionSet.PermissionSetAssignmentWrapper>{
                wrapper
            }
        ).execute(null);

        Test.stopTest();

        Map<Id, Production_Access_Request__c> updatedRequests =
            new Map<Id, Production_Access_Request__c>([
                SELECT Id, Status__c, Permission_Set_Assignment_Id__c
                FROM Production_Access_Request__c
                WHERE Id IN :new Set<Id>{request1.Id, request2.Id}
            ]);

        System.assertNotEquals(
            null,
            updatedRequests.get(request1.Id).Permission_Set_Assignment_Id__c
        );

        System.assertNotEquals(
            null,
            updatedRequests.get(request2.Id).Permission_Set_Assignment_Id__c,
            'The other active request should receive the new PSA ID.'
        );
    }
}
	
	
}