public with sharing class ProductionAccessVerification {

    public class OTPRequest {
        @InvocableVariable
        public String dummyInput;
    }

    public class OTPResult {
        @InvocableVariable
        public String otpCode;
    }

    @InvocableMethod(
        label='Generate Production OTP'
        description='Generates a random 6-digit verification OTP code'
    )
    public static List<OTPResult> generateOTP(List<OTPRequest> requests) {
        List<OTPResult> results = new List<OTPResult>();
        Integer count = (requests != null && !requests.isEmpty()) ? requests.size() : 1;
        for (Integer i = 0; i < count; i++) {
            Integer randomNumber = Math.mod(Math.abs(Crypto.getRandomInteger()), 900000) + 100000;
            OTPResult res = new OTPResult();
            res.otpCode = String.valueOf(randomNumber);
            results.add(res);
        }
        return results;
    }

    public static Boolean validateCode(String enteredCode, String targetCode) {
        if (String.isBlank(enteredCode) || String.isBlank(targetCode)) {
            return false;
        }
        return enteredCode.trim().equals(targetCode.trim());
    }
}