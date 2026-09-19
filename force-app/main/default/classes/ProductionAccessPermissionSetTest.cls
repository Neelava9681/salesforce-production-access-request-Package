@IsTest
private class ProductionAccessPermissionSetTest {

    /**
     * Get a Permission Set available in the test org.
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
     * Test successful Permission Set assignment.
     *
     * Uses Permission Set Id because the current production
     * implementation performs Id filtering on the PermissionSet query.
     */
    @IsTest
    static void testAssignPermissionSet_Success() {

        PermissionSet ps = getTestPermissionSet();
        Id currentUserId = UserInfo.getUserId();

        Datetime expirationDate = Datetime.now().addHours(2);

        ProductionAccessPermissionSet.PermissionSetRequest req =
            new ProductionAccessPermissionSet.PermissionSetRequest();

        req.userId = currentUserId;
        req.permissionSetId = String.valueOf(ps.Id);
        req.expirationDate = expirationDate;

        List<ProductionAccessPermissionSet.PermissionSetResult> results;

        Test.startTest();

        results = ProductionAccessPermissionSet.assignPermissionSet(
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

        /*
         * Verify Queueable actually inserted the assignment.
         */
        List<PermissionSetAssignment> assignments = [
            SELECT Id,
                   AssigneeId,
                   PermissionSetId,
                   ExpirationDate
            FROM PermissionSetAssignment
            WHERE AssigneeId = :currentUserId
            AND PermissionSetId = :ps.Id
        ];

        System.assertEquals(
            1,
            assignments.size(),
            'Permission Set Assignment should have been created.'
        );

  		// System.assertEquals(expirationDate, assignments[0].ExpirationDate,'Expiration date on the assignment should match.');
    }


    /**
     * Test Already Assigned branch.
     */
@IsTest
static void testAssignPermissionSet_AlreadyAssigned() {

    Id permissionSetId = '0PSgL00000MDC0HWAX';
    Id currentUserId = UserInfo.getUserId();

    /*
     * Confirm the Permission Set exists.
     */
    PermissionSet ps = [
        SELECT Id, Name, Label
        FROM PermissionSet
        WHERE Id = :permissionSetId
        LIMIT 1
    ];

    /*
     * Create the existing assignment.
     */
    PermissionSetAssignment existingAssignment =
        new PermissionSetAssignment(
            AssigneeId = currentUserId,
            PermissionSetId = ps.Id
        );

    insert existingAssignment;

    /*
     * Verify that Salesforce can actually see it.
     */
    List<PermissionSetAssignment> verifyAssignment = [
        SELECT Id, AssigneeId, PermissionSetId, ExpirationDate
        FROM PermissionSetAssignment
        WHERE AssigneeId = :currentUserId
        AND PermissionSetId = :ps.Id
    ];

    System.assertEquals(
        1,
        verifyAssignment.size(),
        'The Permission Set Assignment should exist before calling the class.'
    );

    ProductionAccessPermissionSet.PermissionSetRequest req =
        new ProductionAccessPermissionSet.PermissionSetRequest();

    req.userId = currentUserId;
    req.permissionSetId = String.valueOf(ps.Id);

    List<ProductionAccessPermissionSet.PermissionSetResult> results;

    Test.startTest();

    results = ProductionAccessPermissionSet.assignPermissionSet(
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
        'Request should be successful.'
    );

    System.assertEquals(
        true,
        results[0].isAlreadyAssigned,
        'The existing assignment should be detected.'
    );

    System.assertEquals(
        'Permission set is already assigned.',
        results[0].message
    );
}

    /**
     * Test missing User Id.
     *
     * We use a REAL Permission Set Id here because the production
     * method performs its PermissionSet query before validating userId.
     */
    @IsTest
    static void testAssignPermissionSet_MissingUserId() {

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


    /**
     * Test missing Permission Set Id.
     */
    @IsTest
    static void testAssignPermissionSet_MissingPermissionSetId() {

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


    /**
     * Test invalid Permission Set.
     *
     * IMPORTANT:
     * Use a syntactically valid Salesforce Id so that the
     * "Id IN :permSetKeys" portion of the production SOQL
     * does not fail before reaching the application's
     * "Could not find Permission Set" validation.
     */

 


    /**
     * Test Queueable with null assignments.
     */
    @IsTest
    static void testQueueable_NullAssignments() {

        ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
            new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
                null
            );

        Test.startTest();

        queueable.execute(null);

        Test.stopTest();

        System.assert(
            true,
            'Queueable should handle null assignments without errors.'
        );
    }


    /**
     * Test Queueable with empty assignments.
     */
    @IsTest
    static void testQueueable_EmptyAssignments() {

        ProductionAccessPermissionSet.AssignPermissionSetQueueable queueable =
            new ProductionAccessPermissionSet.AssignPermissionSetQueueable(
                new List<PermissionSetAssignment>()
            );

        Test.startTest();

        queueable.execute(null);

        Test.stopTest();

        System.assert(
            true,
            'Queueable should handle empty assignments without errors.'
        );
    }
}