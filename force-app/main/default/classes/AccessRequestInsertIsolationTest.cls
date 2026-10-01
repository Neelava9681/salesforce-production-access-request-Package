/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class AccessRequestInsertIsolationTest {

     @IsTest
    static void testInsertRequest() {
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
            UserName = 'testadmin_' + DateTime.now().getTime() + '@example.com'
        );

        // 1. Create the test user first
        insert adminUser;

        // 2. Get your Permission Set
        PermissionSet testAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Production_Access_Request_Test_Access'
            LIMIT 1
        ];

        // 3. Assign Permission Set to the test user
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = testAccessPermissionSet.Id
        );

        insert psa;

        Production_Access_Request__c req =
            new Production_Access_Request__c(
                Developer_Name__c = 'Package Test',
                Status__c = 'Pending Approval'
            );

        System.runAs(adminUser) {
            Test.startTest();
            insert req;
            Test.stopTest();
        }
        System.assertNotEquals(null, req.Id);
    }
}