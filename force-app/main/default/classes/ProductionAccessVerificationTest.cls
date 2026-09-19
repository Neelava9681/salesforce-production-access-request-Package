@isTest
private class ProductionAccessVerificationTest {

    @isTest
    static void testGenerateOTP_WithRequests() {
        List<ProductionAccessVerification.OTPRequest> requests = new List<ProductionAccessVerification.OTPRequest>();
        ProductionAccessVerification.OTPRequest req = new ProductionAccessVerification.OTPRequest();
        req.dummyInput = 'Test';
        requests.add(req);

        Test.startTest();
        List<ProductionAccessVerification.OTPResult> results = ProductionAccessVerification.generateOTP(requests);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should generate 1 result');
        System.assertNotEquals(null, results[0].otpCode, 'OTP code should not be null');
        System.assertEquals(6, results[0].otpCode.length(), 'OTP code should be 6 digits');
        System.assert(Integer.valueOf(results[0].otpCode) >= 100000, 'OTP should be >= 100000');
    }

    @isTest
    static void testGenerateOTP_NullAndEmptyRequests() {
        Test.startTest();
        List<ProductionAccessVerification.OTPResult> nullResults = ProductionAccessVerification.generateOTP(null);
        List<ProductionAccessVerification.OTPResult> emptyResults = ProductionAccessVerification.generateOTP(new List<ProductionAccessVerification.OTPRequest>());
        Test.stopTest();

        System.assertEquals(1, nullResults.size(), 'Null input should generate 1 default OTP result');
        System.assertEquals(1, emptyResults.size(), 'Empty list should generate 1 default OTP result');
    }

    @isTest
    static void testValidateCode_Matching() {
        Boolean isValidExact = ProductionAccessVerification.validateCode('123456', '123456');
        Boolean isValidTrimmed = ProductionAccessVerification.validateCode(' 654321 ', '654321');

        System.assertEquals(true, isValidExact, 'Exact matching codes should return true');
        System.assertEquals(true, isValidTrimmed, 'Trimmed matching codes should return true');
    }

    @isTest
    static void testValidateCode_NotMatching() {
        Boolean isValid = ProductionAccessVerification.validateCode('123456', '654321');
        System.assertEquals(false, isValid, 'Mismatched codes should return false');
    }

    @isTest
    static void testValidateCode_BlankOrNull() {
        System.assertEquals(false, ProductionAccessVerification.validateCode(null, '123456'), 'Null entered code should return false');
        System.assertEquals(false, ProductionAccessVerification.validateCode('123456', null), 'Null target code should return false');
        System.assertEquals(false, ProductionAccessVerification.validateCode('', '123456'), 'Empty entered code should return false');
        System.assertEquals(false, ProductionAccessVerification.validateCode('123456', ' '), 'Blank target code should return false');
    }
}
